import 'dart:io';

class VaultEntry {
  final String name;
  final String relativePath;
  final String absolutePath;
  final bool isDirectory;
  final bool hasReviewTag;

  VaultEntry({
    required this.name,
    required this.relativePath,
    required this.absolutePath,
    required this.isDirectory,
    required this.hasReviewTag,
  });
}

class VaultService {
  Future<List<VaultEntry>> scanDirectory(String rootPath) async {
    final entries = <VaultEntry>[];
    final rootDir = Directory(rootPath);

    if (!await rootDir.exists()) return entries;

    await for (final entity in rootDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.md')) {
        var relativePath = entity.path.substring(rootPath.length).replaceAll('\\', '/');
        if (relativePath.startsWith('/')) {
          relativePath = relativePath.substring(1);
        }
        final content = await entity.readAsString();
        final hasReviewTag = content.contains('#review');
        entries.add(VaultEntry(
          name: entity.path.split('/').last,
          relativePath: relativePath,
          absolutePath: entity.path,
          isDirectory: false,
          hasReviewTag: hasReviewTag,
        ));
      }
    }
    return entries;
  }
}
