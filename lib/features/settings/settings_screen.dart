import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
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
    final notifyHour = await SettingsStore.getNotifyHour();
    final notifyMinute = await SettingsStore.getNotifyMinute();
    final intervals = await SettingsStore.getSm2Intervals();
    setState(() {
      _vaultPath = vaultPath;
      _reviewCount = reviewCount;
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

  String? _resolvePath(String raw) {
    if (!Platform.isAndroid) return raw;
    // Convert content URI like content://.../tree/primary%3ADocuments%2FObsidian
    // to real path like /storage/emulated/0/Documents/Obsidian
    if (raw.startsWith('content://')) {
      final parts = raw.split('/');
      final last = parts.last;
      final decoded = Uri.decodeComponent(last);
      if (decoded.startsWith('primary%3A') || decoded.startsWith('primary:')) {
        return '/storage/emulated/0/${decoded.replaceAll(RegExp(r'^primary[%]?3[A]?:'), '')}';
      }
    }
    return raw;
  }

  Future<void> _setReviewCount(int count) async {
    await SettingsStore.setReviewCount(count);
    setState(() => _reviewCount = count);
    ref.invalidate(reviewCountProvider);
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
                      if (result != null) {
                        final realPath = _resolvePath(result);
                        if (realPath != null) {
                          await _saveVaultPath(realPath);
                        }
                      }
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
              child: Row(
                children: [
                  const Text('每篇笔记出题数'),
                  const Spacer(),
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
