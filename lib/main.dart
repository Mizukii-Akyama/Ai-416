import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ai is eblan XD',
      theme: ThemeData.dark(),
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
  final List<String> _messages = [];
  bool _isLoading = false;
  bool _modelLoaded = false;

  Future<void> _pickModel() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() => _isLoading = true);
      try {
        await _controller.loadModel(
          modelPath: result.files.single.path!,
          contextSize: 2048,
          threads: 4,
        );
        setState(() => _modelLoaded = true);
        _messages.add('Модель загружена.');
      } catch (e) {
        _messages.ad'Error loading : $e');
      }
      setState(() => _isLoading = false);
    }
  }

  void _sendMessage() {
    if (!_modelLoaded || _textController.text.isEmpty) return;
    final prompt = _textController.text;
    _textController.clear();
    setState(() {
      _messages.ad('prompt''t');
      _messages.ad();
    });

    _controller.generate(prompt: prompt, maxTokens: 512).listen((token) {
      setState(() {
        _messages[_messages.length - 1] += token;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ai')),
      body: Column(
        children: [
          if (!_modelLoaded)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _pickModel,
                child: Text(_isLoading 'loading...' : 'Выбрать .gguf файл'),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_messages[index]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(hintText 'Enter the promt:'),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
