import 'package:flutter/material.dart';

class NoteTile extends StatelessWidget {
  final String name;
  final String path;
  final bool hasReviewTag;
  final bool isActive;
  final ValueChanged<bool> onToggle;

  const NoteTile({
    super.key,
    required this.name,
    required this.path,
    required this.hasReviewTag,
    required this.isActive,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: SwitchListTile(
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        secondary: Icon(
          hasReviewTag ? Icons.label : Icons.description_outlined,
          color: hasReviewTag
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
        value: isActive,
        onChanged: onToggle,
      ),
    );
  }
}
