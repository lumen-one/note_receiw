import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../settings/settings_provider.dart';
import 'home_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overdueAsync = ref.watch(overdueProvider);
    final vaultPathAsync = ref.watch(vaultPathProvider);
    final overdueCount = overdueAsync.valueOrNull?.count ?? 0;
    final hasVaultPath = vaultPathAsync.valueOrNull != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NoteReview'),
        actions: [
          if (hasVaultPath)
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: '管理笔记',
              onPressed: () => context.push('/vault-browser'),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    _buildStatCircle(
                      context,
                      value: overdueCount,
                      label: '待复习',
                      color: overdueCount > 0
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            !hasVaultPath
                                ? '尚未设置笔记路径'
                                : overdueCount > 0
                                    ? '有笔记需要复习'
                                    : '暂无待复习笔记',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            !hasVaultPath
                                ? '点击下方设置按钮选择 Obsidian 笔记文件夹'
                                : overdueCount > 0
                                    ? '点击复习标签开始'
                                    : '去管理笔记中添加笔记',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (!hasVaultPath)
              FilledButton.icon(
                onPressed: () => context.go('/settings'),
                icon: const Icon(Icons.settings),
                label: const Text('去设置笔记路径'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            if (hasVaultPath) ...[
              FilledButton.icon(
                onPressed: () => context.push('/vault-browser'),
                icon: const Icon(Icons.folder_open),
                label: const Text('管理笔记'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => context.go('/review'),
                icon: const Icon(Icons.quiz_outlined),
                label: const Text('开始复习'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatCircle(
    BuildContext context, {
    required int value,
    required String label,
    required Color color,
  }) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withAlpha(25),
        border: Border.all(color: color, width: 3),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$value',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}
