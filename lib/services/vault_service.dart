import 'dart:convert';
import 'dart:io';
import 'yaml_parser.dart';

class VaultEntry {
  final String name;
  final String relativePath;
  final String absolutePath;
  final bool isDirectory;
  final bool hasReviewTag;
  final List<String> tags;

  VaultEntry({
    required this.name,
    required this.relativePath,
    required this.absolutePath,
    required this.isDirectory,
    required this.hasReviewTag,
    this.tags = const [],
  });
}

class VaultTreeNode {
  final String name;
  final String relativePath;
  final String absolutePath;
  final bool isDirectory;
  final bool hasReviewTag;
  final List<String> tags;
  final List<VaultTreeNode> children;
  final int fileCount;

  VaultTreeNode({
    required this.name,
    required this.relativePath,
    required this.absolutePath,
    required this.isDirectory,
    this.hasReviewTag = false,
    this.tags = const [],
    this.children = const [],
    this.fileCount = 0,
  });
}

class VaultService {
  Future<List<VaultEntry>> scanDirectory(String rootPath) async {
    final tree = await scanTree(rootPath);
    return flattenTree(tree);
  }

  Future<VaultTreeNode> scanTree(String rootPath) async {
    final rootDir = Directory(rootPath);
    if (!await rootDir.exists()) {
      return VaultTreeNode(
        name: '',
        relativePath: '',
        absolutePath: rootPath,
        isDirectory: true,
        children: [],
        fileCount: 0,
      );
    }
    return _buildNode(rootDir, rootPath);
  }

  Future<VaultTreeNode> _buildNode(Directory dir, String rootPath) async {
    final children = <VaultTreeNode>[];
    int fileCount = 0;

    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final child = await _buildNode(entity, rootPath);
        fileCount += child.fileCount;
        children.add(child);
      } else if (entity is File && entity.path.endsWith('.md')) {
        bool hasReviewTag = false;
        List<String> tags = [];
        try {
          final content = await entity.readAsString();
          final lines = content.split('\n').take(30).toList();
          hasReviewTag = lines.any((line) => line.contains('#review'));
          tags = YamlParser.extractTagsFromMarkdown(content);
        } catch (_) {
          // If file can't be read, skip detection
        }
        final fileRelative = entity.path.substring(rootPath.length + 1);
        children.add(VaultTreeNode(
          name: entity.path.split('/').last,
          relativePath: fileRelative,
          absolutePath: entity.path,
          isDirectory: false,
          hasReviewTag: hasReviewTag,
          tags: tags,
        ));
        fileCount++;
      }
    }

    children.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.compareTo(b.name);
    });

    final relPath = dir.path == rootPath ? '' : dir.path.substring(rootPath.length + 1);
    return VaultTreeNode(
      name: dir.path.split('/').last,
      relativePath: relPath,
      absolutePath: dir.path,
      isDirectory: true,
      children: children,
      fileCount: fileCount,
    );
  }

  List<VaultEntry> flattenTree(VaultTreeNode node) {
    final result = <VaultEntry>[];
    _flatten(node, result);
    return result;
  }

  void _flatten(VaultTreeNode node, List<VaultEntry> result) {
    if (!node.isDirectory) {
      result.add(VaultEntry(
        name: node.name,
        relativePath: node.relativePath,
        absolutePath: node.absolutePath,
        isDirectory: false,
        hasReviewTag: node.hasReviewTag,
        tags: node.tags,
      ));
    }
    for (final child in node.children) {
      _flatten(child, result);
    }
  }
}
