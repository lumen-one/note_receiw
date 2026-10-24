import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/constants.dart';

/// 笔记读取结果。[truncated] 为 true 表示内容被截断后才送进 prompt。
class NoteContent {
  final String text;
  final bool truncated;
  final bool found;

  const NoteContent({
    required this.text,
    this.truncated = false,
    this.found = true,
  });

  const NoteContent.missing()
      : text = '',
        truncated = false,
        found = false;

  bool get isEmpty => text.trim().isEmpty;
}

/// 统一入口：把 vault 相对路径读成可送进 prompt 的文本。
///
/// 之前出题路径直接 `readAsString()` 整篇塞进 prompt，聊天路径截 2000 字，
/// 两条路各写一份，长笔记会撑爆上下文且没有任何提示。这里收成一处。
class NoteContentLoader {
  static Future<NoteContent> load(
    String? vaultPath,
    String relativePath, {
    int maxChars = AppConstants.maxNoteCharsForPrompt,
  }) async {
    if (vaultPath == null || vaultPath.isEmpty) {
      return const NoteContent.missing();
    }
    try {
      final file = File(p.join(vaultPath, relativePath));
      if (!await file.exists()) return const NoteContent.missing();

      final raw = await file.readAsString();
      if (raw.length <= maxChars) {
        return NoteContent(text: raw);
      }
      return NoteContent(
        text: '${raw.substring(0, maxChars)}\n\n'
            '...(笔记过长，已省略后 ${raw.length - maxChars} 字)',
        truncated: true,
      );
    } catch (_) {
      return const NoteContent.missing();
    }
  }
}
