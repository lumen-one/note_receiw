import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../data/database/database.dart';
import '../../data/settings_store.dart';
import '../../services/ai_service.dart';
import '../../services/sm2_engine.dart';
import '../settings/settings_provider.dart';
import 'review_provider.dart';
import 'widgets/chat_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String sessionType;
  final String? initialNoteIds;

  const ChatScreen({
    super.key,
    required this.sessionType,
    this.initialNoteIds,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final List<Map<String, String>> _messages = [];
  bool _loading = false;
  List<NoteFile> _allNotes = [];
  List<NoteFile> _activeNotes = [];
  bool _showSuggestions = false;
  String _mentionQuery = '';
  int _mentionCursorPos = -1;
  final Set<int> _mentionedNoteIds = {};

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    try {
      final db = ref.read(databaseProvider);
      final all = await db.allNotes();
      final active = await db.allActiveNotes();
      setState(() {
        _allNotes = all;
        _activeNotes = active;
      });

      if (widget.initialNoteIds != null && widget.initialNoteIds!.isNotEmpty) {
        final ids = widget.initialNoteIds!
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .where((id) => id != null)
            .cast<int>()
            .toList();
        setState(() {
          _mentionedNoteIds.addAll(ids);
        });
      }
    } catch (e) {
      // Notes will be empty lists, chat still functional
    }
  }

  void _onTextChanged() {
    final text = _controller.text;
    final sel = _controller.selection;
    if (!sel.isValid || sel.baseOffset != sel.extentOffset) {
      setState(() => _showSuggestions = false);
      return;
    }

    final cursorPos = sel.baseOffset;
    final beforeCursor = text.substring(0, cursorPos);
    final atIdx = beforeCursor.lastIndexOf('@');

    if (atIdx >= 0 && (atIdx == 0 || beforeCursor[atIdx - 1] == ' ' || beforeCursor[atIdx - 1] == '\n')) {
      final query = beforeCursor.substring(atIdx + 1);
      if (!query.contains(' ')) {
        setState(() {
          _showSuggestions = true;
          _mentionQuery = query;
          _mentionCursorPos = atIdx;
        });
        return;
      }
    }

    setState(() => _showSuggestions = false);
  }

  List<NoteFile> _filteredNotes() {
    final q = _mentionQuery.toLowerCase();
    final active = _activeNotes
        .where((n) => n.fileName.toLowerCase().contains(q))
        .toList();
    final inactive = _allNotes
        .where((n) => !_activeNotes.any((a) => a.id == n.id))
        .where((n) => n.fileName.toLowerCase().contains(q))
        .toList();
    return [...active, ...inactive];
  }

  void _selectNote(NoteFile note) {
    final text = _controller.text;
    final before = text.substring(0, _mentionCursorPos);
    final after = text.substring(_mentionCursorPos + 1 + _mentionQuery.length);
    _controller.text = '$before@${note.fileName} $after';
    _controller.selection = TextSelection.collapsed(
      offset: _mentionCursorPos + note.fileName.length + 2,
    );
    setState(() {
      _showSuggestions = false;
      _mentionedNoteIds.add(note.id);
    });
  }

  Future<String> _buildContextPrompt() async {
    if (_mentionedNoteIds.isEmpty) {
      return '你是一位和我一起学习的挚友。我们可以自由讨论任何话题，包括笔记中的知识。';
    }

    final vaultPath = ref.read(vaultPathProvider).valueOrNull;
    final notes = _allNotes.where((n) => _mentionedNoteIds.contains(n.id)).toList();
    final contextParts = <String>[];
    for (final note in notes) {
      final filePath = vaultPath != null ? '$vaultPath/${note.filePath}' : '';
      String content = '';
      if (filePath.isNotEmpty) {
        try {
          final file = File(filePath);
          if (await file.exists()) {
            final full = await file.readAsString();
            content = full.length > 2000 ? '${full.substring(0, 2000)}\n\n...(截断)' : full;
          }
        } catch (_) {
          content = '(无法读取文件内容)';
        }
      }
      contextParts.add('- ${note.fileName}（来自 ${note.filePath}）：\n$content');
    }

    return '你是一位和我一起学习的挚友。用户可以 @ 笔记名来引用笔记内容。'
        '当前会话引用的笔记：\n${contextParts.join('\n\n')}'
        '\n\n请基于以上笔记内容进行讨论。';
  }

  Future<void> _send() async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'content': content});
      _loading = true;
    });
    _controller.clear();

    try {
      final aiService = ref.read(aiServiceProvider);
      final systemPrompt = await _buildContextPrompt();
      final fullMessages = [
        {'role': 'system', 'content': systemPrompt},
        ..._messages,
      ];

      final reply = await aiService.continueChat(messages: fullMessages);
      setState(() {
        _messages.add({'role': 'assistant', 'content': reply});
      });
    } catch (e) {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': '抱歉，请求失败：$e',
        });
      });
    } finally {
      setState(() => _loading = false);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _endChat() async {
    if (_mentionedNoteIds.isEmpty) return;

    try {
      final db = ref.read(databaseProvider);
      final activeMentioned = _activeNotes
          .where((n) => _mentionedNoteIds.contains(n.id))
          .toList();

      if (activeMentioned.isEmpty) return;

      final customIntervals = await SettingsStore.getSm2Intervals();
      int updated = 0;
      for (final note in activeMentioned) {
        final existing = await db.recordForNote(note.id);
        final result = Sm2Engine.calculate(
          quality: 3,
          currentInterval: existing?.sm2Interval ?? 1.0,
          currentEaseFactor: existing?.sm2EaseFactor ?? 2.5,
          currentRepetitions: existing?.sm2Repetitions ?? 0,
          customIntervals: customIntervals,
        );
        await db.upsertRecord(ReviewRecordsCompanion.insert(
          noteId: Value(note.id),
          sm2Interval: Value(result.interval),
          sm2EaseFactor: Value(result.easeFactor),
          sm2Repetitions: Value(result.repetitions),
          nextReviewDate: result.nextReviewDate,
          lastReviewDate: Value(DateTime.now()),
          lastScore: const Value(3),
        ));
        updated++;
      }

      ref.invalidate(overdueProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已通过聊天复习 $updated 篇笔记')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('记录复习失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _showSuggestions ? _filteredNotes() : <NoteFile>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sessionType == 'free_chat' ? '自由聊天' : '追问'),
        actions: [
          if (_mentionedNoteIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_mentionedNoteIds.length} 篇笔记',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: '结束聊天并记录复习',
              onPressed: _endChat,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      '开始和你的学习挚友聊天吧\n在输入框中输入 @ 引用笔记',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_loading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length && _loading) {
                        return const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final msg = _messages[index];
                      return ChatBubble(
                        content: msg['content'] ?? '',
                        isUser: msg['role'] == 'user',
                      );
                    },
                  ),
          ),
          if (suggestions.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: suggestions.length,
                separatorBuilder: (_, __) => Divider(height: 1, indent: 16),
                itemBuilder: (context, index) {
                  final note = suggestions[index];
                  final isActive = _activeNotes.any((n) => n.id == note.id);
                  final isAlreadyMentioned = _mentionedNoteIds.contains(note.id);
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isActive ? Icons.description : Icons.description_outlined,
                      size: 20,
                      color: isActive
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(note.fileName, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      isActive
                          ? (isAlreadyMentioned ? '已引用 · 已监控' : '已监控')
                          : '未监控',
                      style: TextStyle(
                        fontSize: 11,
                        color: isActive ? null : Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onTap: () => _selectNote(note),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: _activeNotes.isEmpty
                          ? '暂无监控笔记，@ 无法引用'
                          : '输入消息...（@引用笔记）',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLines: 3,
                    minLines: 1,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _loading ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
