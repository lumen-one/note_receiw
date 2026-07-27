import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

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
    if (segments.length == 1 && !segments[0].isMath) {
      return MarkdownBody(
        data: data,
        styleSheet: styleSheet,
        selectable: selectable,
        builders: {'mathInline': _InlineMathBuilder()},
        extensionSet: md.ExtensionSet(
          md.ExtensionSet.gitHubFlavored.blockSyntaxes,
          [_InlineMathSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: segments.map((seg) {
        if (seg.isMath) return _buildBlockMath(context, seg.content);
        return MarkdownBody(
          data: seg.content,
          styleSheet: styleSheet,
          selectable: selectable,
          builders: {'mathInline': _InlineMathBuilder()},
          extensionSet: md.ExtensionSet(
            md.ExtensionSet.gitHubFlavored.blockSyntaxes,
            [_InlineMathSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBlockMath(BuildContext context, String latex) {
    final theme = Theme.of(context);
    final body = latex.trim();
    if (body.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Math.tex(
            body,
            mathStyle: MathStyle.display,
            textStyle: TextStyle(fontSize: 18, color: theme.textTheme.bodyLarge?.color),
            onErrorFallback: (err) => _errorFallback(theme, body),
          ),
        ),
      ),
    );
  }

  Widget _errorFallback(ThemeData theme, String tex) {
    return Text(
      tex,
      style: TextStyle(
        fontFamily: 'monospace',
        color: theme.colorScheme.error,
        fontSize: 14,
      ),
    );
  }
}

class _InlineMathSyntax extends md.InlineSyntax {
  _InlineMathSyntax() : super(r'(?<!\$)\$(.+?)\$(?!\$)', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('mathInline', match[1] ?? ''));
    return true;
  }
}

class _InlineMathBuilder extends MarkdownElementBuilder {
  @override
  Widget? build(BuildContext context, md.Element element, List<Widget?> children) {
    final latex = element.textContent;
    if (latex.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Math.tex(
        latex,
        mathStyle: MathStyle.text,
        textStyle: TextStyle(
          fontSize: theme.textTheme.bodyLarge?.fontSize ?? 16,
          color: theme.textTheme.bodyLarge?.color,
        ),
        onErrorFallback: (err) => Text(
          '\$$latex\$',
          style: TextStyle(
            fontFamily: 'monospace',
            color: theme.colorScheme.error,
            fontSize: 14,
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
  if (!text.contains('\$\$')) {
    return [_Segment(isMath: false, content: text)];
  }
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
