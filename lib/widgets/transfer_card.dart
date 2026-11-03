import 'package:flutter/material.dart';

import '../core/utilities/format_utils.dart';
import '../models/transfer.dart';
import 'status_badge.dart';
import 'transfer_progress.dart';

/// One transfer with live progress, real speed, ETA and a cancel button.
class TransferCard extends StatelessWidget {
  const TransferCard({super.key, required this.transfer, required this.onCancel});

  final Transfer transfer;
  final VoidCallback onCancel;

  BadgeTone _tone() => switch (transfer.state) {
        TransferState.completed => BadgeTone.success,
        TransferState.failed => BadgeTone.error,
        TransferState.rejected => BadgeTone.error,
        TransferState.cancelled => BadgeTone.neutral,
        _ => BadgeTone.warning,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = transfer;
    final eta = t.eta;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(t.isOutgoing ? Icons.north_east_rounded : Icons.south_west_rounded,
                color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '${t.isOutgoing ? 'To' : 'From'} ${t.peerName} (${t.peerIp}) · ${FormatUtils.bytes(t.totalBytes)}',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
                ),
              ]),
            ),
            StatusBadge(label: t.state.label, tone: _tone()),
            if (t.state.isActive)
              IconButton(
                tooltip: 'Cancel',
                onPressed: onCancel,
                icon: const Icon(Icons.close_rounded),
              ),
          ]),
          if (t.state == TransferState.transferring || t.state == TransferState.completed) ...[
            const SizedBox(height: 14),
            TransferProgressBar(value: t.progress),
            const SizedBox(height: 8),
            Row(children: [
              Text('${(t.progress * 100).toStringAsFixed(0)}% · '
                  '${FormatUtils.bytes(t.transferredBytes)} of ${FormatUtils.bytes(t.totalBytes)}',
                  style: const TextStyle(fontSize: 12.5)),
              const Spacer(),
              if (t.state == TransferState.transferring) ...[
                Text(FormatUtils.speed(t.speedBytesPerSecond),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                if (eta != null) Text('  ·  ${FormatUtils.duration(eta)} left',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
              ],
            ]),
            if (t.resumedBytes > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Resumed: ${FormatUtils.bytes(t.resumedBytes)} were already received.',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              ),
            if (t.currentFile != null && t.files.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('File ${t.completedFiles + 1} of ${t.files.length}: ${t.currentFile}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              ),
          ],
          if (t.error != null && !t.state.isActive && t.state != TransferState.completed)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(t.error!, style: TextStyle(color: scheme.error, fontSize: 12.5)),
            ),
        ]),
      ),
    );
  }
}
