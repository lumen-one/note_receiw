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

class VaultTreeNode {
  final String name;
  final String relativePath;
  final String absolutePath;
  final bool isDirectory;
  final bool hasReviewTag;
  final List<VaultTreeNode> children;
  final int fileCount;

  VaultTreeNode({
    required this.name,
    required this.relativePath,
    required this.absolutePath,
    required this.isDirectory,
    this.hasReviewTag = false,
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
    return _buildNode(rootDir, rootPath, '');
  }

  Future<VaultTreeNode> _buildNode(Directory dir, String rootPath, String relativeParent) async {
    final name = dir.path.split('/').last;
    final isRoot = relativeParent.isEmpty;
    final relativePath = isRoot ? '' : (relativeParent.isEmpty ? name : '$relativeParent/$name');
    final children = <VaultTreeNode>[];
    int fileCount = 0;

    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final child = await _buildNode(entity, rootPath, relativePath.isEmpty && !isRoot ? relativePath : (relativePath.isEmpty ? '' : relativePath));
        final childRelPath = isRoot ? entity.path.substring(rootPath.length + 1) : '$relativePath/${entity.path.split('/').last}';
        final fixedChild = VaultTreeNode(
          name: child.name,
          relativePath: childRelPath,
          absolutePath: child.absolutePath,
          isDirectory: true,
          children: child.children,
          fileCount: child.fileCount,
        );
        fileCount += child.fileCount;
        children.add(fixedChild);
      } else if (entity is File && entity.path.endsWith('.md')) {
        final content = await entity.readAsString();
        final hasReviewTag = content.contains('#review');
        var fileRelative = entity.path.substring(rootPath.length + 1);
        children.add(VaultTreeNode(
          name: entity.path.split('/').last,
          relativePath: fileRelative,
          absolutePath: entity.path,
          isDirectory: false,
          hasReviewTag: hasReviewTag,
        ));
        fileCount++;
      }
    }

    children.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.compareTo(b.name);
    });

    return VaultTreeNode(
      name: name,
      relativePath: relativePath,
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
      ));
    }
    for (final child in node.children) {
      _flatten(child, result);
    }
  }
}
