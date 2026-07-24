import 'package:flutter/material.dart';

class PromptEditorPage extends StatefulWidget {
  final String title;
  final String initialContent;

  const PromptEditorPage({
    super.key,
    required this.title,
    required this.initialContent,
  });

  @override
  State<PromptEditorPage> createState() => _PromptEditorPageState();
}

class _PromptEditorPageState extends State<PromptEditorPage> {
  late final TextEditingController _controller;
  bool _modified = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _controller.addListener(() {
      if (!_modified && _controller.text != widget.initialContent) {
        setState(() => _modified = true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _modified
                ? () => Navigator.of(context).pop(_controller.text)
                : null,
            child: const Text('保存'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _controller,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '在此编辑 Prompt 模板...\n可使用 {note_content}, {question}, {user_answer} 等占位符',
          ),
        ),
      ),
    );
  }
}
