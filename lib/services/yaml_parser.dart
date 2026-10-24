class YamlParser {
  static List<String> extractTagsFromMarkdown(String content) {
    final frontmatter = _extractFrontmatter(content);
    if (frontmatter == null) return [];

    final tags = <String>{};
    final lines = frontmatter.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      if (line == 'tag:' || line.startsWith('tag: ')) {
        final value = line.substring(4).trim();
        if (value.isNotEmpty) tags.add(value);
        continue;
      }

      if (line == 'tags:' || line.startsWith('tags: ')) {
        final inline = line.substring(5).trim();
        if (inline.isNotEmpty && !inline.startsWith('-')) {
          for (final t in inline.split(',')) {
            final tag = t.trim();
            if (tag.isNotEmpty) tags.add(tag);
          }
        }
        for (int j = i + 1; j < lines.length; j++) {
          final next = lines[j].trim();
          if (next.startsWith('- ')) {
            final tag = next.substring(2).trim();
            if (tag.isNotEmpty) tags.add(tag);
          } else if (next.startsWith('#') || next.contains(':')) {
            break;
          } else if (next.isEmpty) {
            continue;
          } else {
            break;
          }
        }
        break;
      }
    }

    return tags.toList();
  }

  static String? _extractFrontmatter(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') return null;

    int end = -1;
    for (int i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        end = i;
        break;
      }
    }
    if (end == -1) return null;

    return lines.sublist(1, end).join('\n');
  }
}
