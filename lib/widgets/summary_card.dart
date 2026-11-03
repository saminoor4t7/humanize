import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';

/// Reusable dashboard stat tile.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.footer,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppConstants.radiusS),
            ),
            child: Icon(icon, size: 20, color: scheme.primary),
          ),
          const SizedBox(height: 16),
          Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge),
          if (footer != null) ...[const SizedBox(height: 10), footer!],
        ]),
      ),
    );
  }
}
