import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;

    status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) return false;

    return false;
  }

  static Future<void> showPermissionSettingsDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要存储权限'),
        content: const Text(
          'NoteReview 需要「管理所有文件」权限才能读取您的 Obsidian 笔记。\n\n'
          '请在系统设置中授予权限：\n'
          '设置 → 应用管理 → NoteReview → 权限 → 文件和媒体 → 允许管理所有文件',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              openAppSettings();
              Navigator.of(ctx).pop();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}
