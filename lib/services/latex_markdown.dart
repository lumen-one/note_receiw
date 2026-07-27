import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class LaTeXMarkdown extends StatelessWidget {
  final String data;
  final MarkdownStyleSheet? styleSheet;
  final bool selectable;

  const LaTeXMarkdown({
    super.key,
    required this.data,
    this.styleSheet,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final segments = _splitByBlockMath(data);
    if (segments.length == 1) {
      return MarkdownBody(
        data: _escapeInlineMathDollars(data),
        styleSheet: styleSheet,
        selectable: selectable,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: segments.map((seg) {
        if (seg.isMath) {
          return _buildBlockMath(context, seg.content);
        }
        return MarkdownBody(
          data: _escapeInlineMathDollars(seg.content),
          styleSheet: styleSheet,
          selectable: selectable,
        );
      }).toList(),
    );
  }

  Widget _buildBlockMath(BuildContext context, String latex) {
    final theme = Theme.of(context);
    if (latex.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: ClipRect(
          child: Math.tex(
            latex.trim(),
            mathStyle: MathStyle.display,
            textStyle: TextStyle(
              fontSize: 18,
              color: theme.textTheme.bodyLarge?.color,
            ),
            onErrorFallback: (err) => Text(
              latex.trim(),
              style: TextStyle(
                fontFamily: 'monospace',
                color: theme.colorScheme.error,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment {
  final bool isMath;
  final String content;
  const _Segment({required this.isMath, required this.content});
}

List<_Segment> _splitByBlockMath(String text) {
  final segments = <_Segment>[];
  final regex = RegExp(r'\$\$([\s\S]+?)\$\$');
  int lastEnd = 0;
  for (final match in regex.allMatches(text)) {
    if (match.start > lastEnd) {
      segments.add(_Segment(isMath: false, content: text.substring(lastEnd, match.start)));
    }
    segments.add(_Segment(isMath: true, content: match.group(1)!));
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    segments.add(_Segment(isMath: false, content: text.substring(lastEnd)));
  }
  if (segments.isEmpty) {
    segments.add(_Segment(isMath: false, content: text));
  }
  return segments;
}

String _escapeInlineMathDollars(String text) {
  return text.replaceAllMapped(
    RegExp(r'(?<!\$)\$(.+?)\$(?!\$)'),
    (m) => '`\$${m.group(1)}\$`',
  );
}
