import 'package:flutter/material.dart';

enum BadgeTone { success, warning, error, neutral }

/// Reusable colored status pill.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, this.tone = BadgeTone.neutral});

  final String label;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (tone) {
      BadgeTone.success => (const Color(0xFF2E9E6B).withValues(alpha: 0.15), const Color(0xFF2E9E6B)),
      BadgeTone.warning => (const Color(0xFFE0A030).withValues(alpha: 0.18), const Color(0xFFB8801A)),
      BadgeTone.error => (scheme.error.withValues(alpha: 0.14), scheme.error),
      BadgeTone.neutral => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12.5)),
      ]),
    );
  }
}
