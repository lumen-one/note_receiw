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
    return MarkdownBody(
      data: data,
      styleSheet: styleSheet,
      selectable: selectable,
      builders: {
        'mathBlock': _MathBlockBuilder(),
        'mathInline': _MathInlineBuilder(),
      },
      extensionSet: md.ExtensionSet(
        md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        [
          _BlockMathSyntax(),
          _InlineMathSyntax(),
          ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
        ],
      ),
    );
  }
}

class _BlockMathSyntax extends md.InlineSyntax {
  _BlockMathSyntax() : super(r'\$\$([\s\S]+?)\$\$', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('mathBlock', (match[1] ?? '').trim()));
    return true;
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

class _MathBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? build(BuildContext context, md.Element element, List<Widget?> children) {
    final latex = element.textContent;
    if (latex.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: ClipRect(
          child: SelectableMath.tex(
            latex,
            mathStyle: MathStyle.display,
            textStyle: TextStyle(
              fontSize: 18,
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
            onErrorFallback: (err) => Text(
              latex,
              style: TextStyle(
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.error,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MathInlineBuilder extends MarkdownElementBuilder {
  @override
  Widget? build(BuildContext context, md.Element element, List<Widget?> children) {
    final latex = element.textContent;
    if (latex.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SelectableMath.tex(
        latex,
        mathStyle: MathStyle.text,
        textStyle: TextStyle(
          fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
        onErrorFallback: (err) => Text(
          '\$$latex\$',
          style: TextStyle(
            fontFamily: 'monospace',
            color: Theme.of(context).colorScheme.error,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
