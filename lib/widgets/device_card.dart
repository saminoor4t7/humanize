import 'package:flutter/material.dart';

import '../core/utilities/fingerprint.dart';
import '../viewmodels/device_viewmodel.dart';
import 'status_badge.dart';

/// A discovered computer with online state and trust controls.
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.view,
    this.selected = false,
    this.onTap,
    this.onToggleTrust,
  });

  final DeviceView view;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onToggleTrust;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = view.device;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.6),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.computer_rounded, color: view.online ? scheme.primary : scheme.outline),
              const SizedBox(width: 10),
              Expanded(
                child: Text(d.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              StatusBadge(
                label: view.online ? 'Online' : 'Offline',
                tone: view.online ? BadgeTone.success : BadgeTone.neutral,
              ),
            ]),
            const SizedBox(height: 10),
            Text('${d.ip}:${d.port}${d.isManual ? ' · added manually' : ''}',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('ID ${Fingerprint.short(d.id)}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()])),
            if (onToggleTrust != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                StatusBadge(
                  label: view.trusted ? 'Trusted' : 'Not trusted',
                  tone: view.trusted ? BadgeTone.success : BadgeTone.warning,
                ),
                const Spacer(),
                TextButton(
                  onPressed: onToggleTrust,
                  child: Text(view.trusted ? 'Remove trust' : 'Trust this device'),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
