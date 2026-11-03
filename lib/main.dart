import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kDefaultTitle = 'New dialoge';

void main() => runApp(const MyApp());

class Message {
  String text;
  final bool isUser;
  Message(this.text, this.isUser);

  Map<String, dynamic> toJson() => {'t': text, 'u': isUser};
  factory Message.fromJson(Map<String, dynamic> j) =>
      Message(j['t'] as String, j['u'] as bool);
}

class Conversation {
  final String id;
  String title;
  final List<Message> messages;

  Conversation({required this.id, required this.title, List<Message>? messages})
      : messages = messages ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'] as String,
        title: j['title'] as String,
        messages: (j['messages'] as List)
            .map((m) => Message.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ai is eblan XD',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final LlamaController _controller = LlamaController();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<Conversation> _conversations = [];
  Conversation? _current;
  bool _isLoading = false;
  bool _modelLoaded = false;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------- storage ----------

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('conversations');
    final list = <Conversation>[];
    if (raw != null) {
      try {
        for (final c in jsonDecode(raw) as List) {
          list.add(Conversation.fromJson(c as Map<String, dynamic>));
        }
      } catch (_) {}
    }
    if (list.isEmpty) list.add(_createConversation());
    final currentId = prefs.getString('current_id');
    setState(() {
      _conversations = list;
      _current = list.firstWhere((c) => c.id == currentId,
          orElse: () => list.first);
    });
    _scrollToBottom();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('conversations',
        jsonEncode(_conversations.map((c) => c.toJson()).toList()));
    if (_current != null) await prefs.setString('current_id', _current!.id);
  }

  Conversation _createConversation() => Conversation(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: kDefaultTitle,
      );

  // ---------- dialogs ----------

  void _newConversation() {
    final conv = _createConversation();
    setState(() {
      _conversations.insert(0, conv);
      _current = conv;
    });
    _save();
  }

  void _selectConversation(Conversation conv) {
    setState(() => _current = conv);
    _save();
    _scrollToBottom();
  }

  Future<void> _renameConversation(Conversation conv) async {
    final ctrl = TextEditingController(text: conv.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name dialoge'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (newTitle != null && newTitle.trim().isNotEmpty) {
      setState(() => conv.title = newTitle.trim());
      _save();
    }
  }

  void _deleteConversation(Conversation conv) {
    setState(() {
      _conversations.remove(conv);
      if (_conversations.isEmpty) _conversations.add(_createConversation());
      if (_current == conv) _current = _conversations.first;
    });
    _save();
    _scrollToBottom();
  }

  // ---------- model and chat ----------

  Future<void> _pickModel() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() => _isLoading = true);
      try {
        await _controller.loadModel(
          modelPath: result.files.single.path!,
          contextSize: 1024,
          threads: 2,
        );
        setState(() {
          _modelLoaded = true;
          _current?.messages.add(Message('Model loaded.', false));
        });
        _save();
      } catch (e) {
        setState(
            () => _current?.messages.add(Message('Error loading: $e', false)));
      }
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _sendMessage() {
    final conv = _current;
    final prompt = _textController.text.trim();
    if (conv == null || !_modelLoaded || _isGenerating || prompt.isEmpty) {
      return;
    }
    _textController.clear();

    final reply = Message('', false);
    setState(() {
      conv.messages.add(Message(prompt, true));
      conv.messages.add(reply);
      if (conv.title == kDefaultTitle) {
        conv.title =
            prompt.length > 30 ? '${prompt.substring(0, 30)}…' : prompt;
      }
      _isGenerating = true;
    });
    _scrollToBottom();

    _controller.generate(prompt: prompt, maxTokens: 512).listen(
      (token) {
        setState(() => reply.text += token);
        if (_current == conv) _scrollToBottom();
      },
      onDone: () {
        setState(() => _isGenerating = false);
        _save();
      },
      onError: (e) {
        setState(() {
          reply.text += '\n[Error: $e]';
          _isGenerating = false;
        });
        _save();
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  // ---------- UI ----------

  Widget _bubble(Message m) {
    final maxWidth = MediaQuery.of(context).size.width * 0.8;
    return Align(
      alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: m.isUser ? const Color(0xFF7C4DFF) : const Color(0xFF3B2A63),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(m.isUser ? 16 : 4),
            bottomRight: Radius.circular(m.isUser ? 4 : 16),
          ),
        ),
        child: SelectableText(
          m.text.isEmpty ? '...' : m.text,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }

  Widget _drawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Dialoges',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _newConversation();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('New dialog'),
                ),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _conversations.length,
                itemBuilder: (context, i) {
                  final conv = _conversations[i];
                  return ListTile(
                    selected: conv == _current,
                    selectedTileColor: const Color(0xFF3B2A63),
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(conv.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Navigator.pop(context);
                      _selectConversation(conv);
                    },
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'rename') _renameConversation(conv);
                        if (v == 'delete') _deleteConversation(conv);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'rename', child: Text('Rename dialoge')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conv = _current;
    if (conv == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(conv.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
            onPressed: () => _renameConversation(conv),
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New dialoge',
            onPressed: _newConversation,
          ),
        ],
      ),
      drawer: _drawer(),
      body: Column(
        children: [
          if (!_modelLoaded)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _pickModel,
                child: Text(_isLoading ? 'loading...' : 'Выбрать .gguf файл'),
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: conv.messages.length,
              itemBuilder: (context, i) => _bubble(conv.messages[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Enter the prompt:',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  color: const Color(0xFF7C4DFF),
                  onPressed: _isGenerating ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
