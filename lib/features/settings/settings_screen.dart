import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/constants.dart';
import '../../data/secure_storage.dart';
import '../../data/settings_store.dart';
import '../settings/settings_provider.dart';
import 'widgets/prompt_editor.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  String? _vaultPath;
  int _reviewCount = 5;
  int _sessionNoteLimit = AppConstants.defaultSessionNoteLimit;
  int _notifyHour = 20;
  int _notifyMinute = 0;
  List<int> _intervals = [1, 6, 15, 38, 95, 238];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final storage = SecureStorageService();
    final key = await storage.getApiKey();
    _apiKeyController.text = key ?? '';

    final model = await SettingsStore.getModelName();
    _modelController.text = model;

    final vaultPath = await SettingsStore.getVaultPath();
    final reviewCount = await SettingsStore.getReviewCount();
    final sessionNoteLimit = await SettingsStore.getSessionNoteLimit();
    final notifyHour = await SettingsStore.getNotifyHour();
    final notifyMinute = await SettingsStore.getNotifyMinute();
    final intervals = await SettingsStore.getSm2Intervals();
    if (!mounted) return;
    setState(() {
      _vaultPath = vaultPath;
      _reviewCount = reviewCount;
      _sessionNoteLimit = sessionNoteLimit;
      _notifyHour = notifyHour;
      _notifyMinute = notifyMinute;
      _intervals = intervals;
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _saveVaultPath(String path) async {
    await SettingsStore.setVaultPath(path);
    setState(() => _vaultPath = path);
    ref.invalidate(vaultPathProvider);
  }

  /// 把 SAF 的 content:// 目录 URI 还原成真实路径，还原不了就返回 null。
  ///
  /// 旧实现用 `primary[%]?3[A]?:` 去剥前缀，那个正则匹配的是 `primary3:` / `primary3A:`，
  /// 而不是解码后的 `primary:`，所以选完目录会得到 `/storage/emulated/0/primary:Documents/...`
  /// 这种不存在的路径，扫描必然空。
  String? _resolvePath(String raw) {
    if (!Platform.isAndroid) return raw;
    if (!raw.startsWith('content://')) return raw;

    final decoded = Uri.decodeComponent(raw);
    // content://com.android.externalstorage.documents/tree/primary%3ADocuments%2FObsidian
    // 解码后是 .../tree/primary:Documents/Obsidian
    final treeIndex = decoded.indexOf('tree/');
    final docIndex = decoded.indexOf('document/');
    final int start;
    if (treeIndex >= 0) {
      start = treeIndex + 'tree/'.length;
    } else if (docIndex >= 0) {
      start = docIndex + 'document/'.length;
    } else {
      return null;
    }

    var path = decoded.substring(start);
    // 有些机型会再拼一段 /document/primary:Notes/A.md，取最后一段
    final nested = path.indexOf('/document/');
    if (nested >= 0) {
      path = path.substring(nested + '/document/'.length);
    }

    final colon = path.indexOf(':');
    if (colon <= 0) return null;

    final volume = path.substring(0, colon);
    final relative = path.substring(colon + 1);
    final base = volume == 'primary' ? '/storage/emulated/0' : '/storage/$volume';
    return relative.isEmpty ? base : '$base/$relative';
  }

  Future<void> _setReviewCount(int count) async {
    await SettingsStore.setReviewCount(count);
    setState(() => _reviewCount = count);
    ref.invalidate(reviewCountProvider);
  }

  Future<void> _setSessionNoteLimit(int limit) async {
    await SettingsStore.setSessionNoteLimit(limit);
    setState(() => _sessionNoteLimit = limit);
    ref.invalidate(sessionNoteLimitProvider);
  }

  Future<void> _setIntervals(List<int> intervals) async {
    await SettingsStore.setSm2Intervals(intervals);
    setState(() => _intervals = intervals);
    ref.invalidate(sm2IntervalsProvider);
  }

  Future<void> _setNotifyTime(int hour, int minute) async {
    await SettingsStore.setNotifyHour(hour);
    await SettingsStore.setNotifyMinute(minute);
    setState(() {
      _notifyHour = hour;
      _notifyMinute = minute;
    });
    ref.invalidate(notifyHourProvider);
    ref.invalidate(notifyMinuteProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader('AI 配置'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'DeepSeek API Key',
                      hintText: 'sk-...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      final storage = SecureStorageService();
                      await storage.setApiKey(_apiKeyController.text.trim());
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('API Key 已保存')),
                        );
                      }
                    },
                    child: const Text('保存 API Key'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _modelController,
                    decoration: InputDecoration(
                      labelText: '模型名称',
                      hintText: 'deepseek-v4-flash',
                      border: const OutlineInputBorder(),
                      suffixIcon: PopupMenuButton<String>(
                        icon: const Icon(Icons.dashboard),
                        tooltip: '常用模型',
                        onSelected: (value) {
                          _modelController.text = value;
                          SettingsStore.setModelName(value);
                          ref.invalidate(modelNameProvider);
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(value: 'deepseek-v4-flash', child: Text('deepseek-v4-flash')),
                          const PopupMenuItem(value: 'deepseek-pro', child: Text('deepseek-pro')),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        final name = _modelController.text.trim();
                        if (name.isNotEmpty) {
                          await SettingsStore.setModelName(name);
                          ref.invalidate(modelNameProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('模型已切换为 $name')),
                            );
                          }
                        }
                      },
                      child: const Text('切换模型'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _sectionHeader('Obsidian Vault'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _vaultPath ?? '未设置',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final result = await FilePicker.platform.getDirectoryPath();
                      if (result == null) return;
                      if (!context.mounted) return;
                      final realPath = _resolvePath(result);
                      if (realPath == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('这个目录无法直接读取，请换一个文件夹（不要选 Android/data 内的目录）'),
                          ),
                        );
                        return;
                      }
                      await _saveVaultPath(realPath);
                    },
                    icon: const Icon(Icons.folder_open),
                    label: const Text('选择笔记文件夹'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _sectionHeader('Prompt 模板'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.quiz),
                    title: const Text('出题 Prompt'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final prompt = await ref.read(generatePromptProvider.future);
                      if (context.mounted) {
                        final result = await Navigator.of(context).push<String>(
                          MaterialPageRoute(
                            builder: (ctx) => PromptEditorPage(
                              title: '出题 Prompt',
                              initialContent: prompt,
                            ),
                          ),
                        );
                        if (result != null) {
                          final db = ref.read(databaseProvider);
                          await db.upsertPromptTemplate('generate_question', result);
                          ref.invalidate(generatePromptProvider);
                        }
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.rate_review),
                    title: const Text('评价 Prompt'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final prompt = await ref.read(evaluatePromptProvider.future);
                      if (context.mounted) {
                        final result = await Navigator.of(context).push<String>(
                          MaterialPageRoute(
                            builder: (ctx) => PromptEditorPage(
                              title: '评价 Prompt',
                              initialContent: prompt,
                            ),
                          ),
                        );
                        if (result != null) {
                          final db = ref.read(databaseProvider);
                          await db.upsertPromptTemplate('evaluate_answer', result);
                          ref.invalidate(evaluatePromptProvider);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _sectionHeader('通知设置'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ListTile(
                leading: const Icon(Icons.notifications),
                title: const Text('每日提醒时间'),
                subtitle: Text(
                  '$_notifyHour:${_notifyMinute.toString().padLeft(2, '0')}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(hour: _notifyHour, minute: _notifyMinute),
                  );
                  if (time != null) {
                    await _setNotifyTime(time.hour, time.minute);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 24),

          _sectionHeader('复习设置'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('每篇笔记出题数')),
                      IconButton(
                        onPressed: _reviewCount > 1
                            ? () => _setReviewCount(_reviewCount - 1)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Text(
                        '$_reviewCount',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      IconButton(
                        onPressed: _reviewCount < 10
                            ? () => _setReviewCount(_reviewCount + 1)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('每次复习笔记数'),
                            SizedBox(height: 2),
                            Text(
                              '一次只处理这么多篇，剩余的留到下次',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _sessionNoteLimit > 1
                            ? () => _setSessionNoteLimit(_sessionNoteLimit - 1)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Text(
                        '$_sessionNoteLimit',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      IconButton(
                        onPressed: _sessionNoteLimit <
                                AppConstants.maxSessionNoteLimit
                            ? () => _setSessionNoteLimit(_sessionNoteLimit + 1)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _sectionHeader('遗忘曲线间隔'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._intervals.asMap().entries.map((entry) {
                    final i = entry.key;
                    final val = entry.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text('第${i + 1}次: ', style: const TextStyle(fontSize: 14)),
                          GestureDetector(
                            onTap: () async {
                              final controller = TextEditingController(text: '$val');
                              final result = await showDialog<int>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text('第${i + 1}次间隔（天）'),
                                  content: TextField(
                                    controller: controller,
                                    keyboardType: TextInputType.number,
                                    autofocus: true,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      hintText: '输入天数',
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () {
                                        final n = int.tryParse(controller.text);
                                        if (n != null && n > 0) {
                                          Navigator.of(ctx).pop(n);
                                        }
                                      },
                                      child: const Text('确定'),
                                    ),
                                  ],
                                ),
                              );
                              controller.dispose();
                              if (result != null && result > 0) {
                                final copy = List<int>.from(_intervals);
                                copy[i] = result;
                                _setIntervals(copy);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Theme.of(context).colorScheme.outline),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('$val', style: const TextStyle(fontSize: 14)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('天'),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, size: 20),
                            onPressed: _intervals.length > 1
                                ? () => _setIntervals(List<int>.from(_intervals)..removeAt(i))
                                : null,
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _setIntervals([..._intervals, _intervals.last]),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加间隔'),
                  ),
                  TextButton(
                    onPressed: () => _setIntervals([1, 6, 15, 38, 95, 238]),
                    child: const Text('恢复默认'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
