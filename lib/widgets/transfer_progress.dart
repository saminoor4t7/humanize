import 'package:flutter/material.dart';

/// Rounded animated progress bar.
class TransferProgressBar extends StatelessWidget {
  const TransferProgressBar({super.key, required this.value, this.height = 10});

  /// 0..1
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.centerLeft,
        child: LayoutBuilder(
          builder: (context, c) => AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: c.maxWidth * value.clamp(0.0, 1.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
              borderRadius: BorderRadius.circular(height),
            ),
          ),
        ),
      ),
    );
  }
}
