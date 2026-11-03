import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utilities/format_utils.dart';
import '../../models/transfer_record.dart';
import '../../viewmodels/history_viewmodel.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_badge.dart';

/// VIEW: searchable, filterable history with a confirmed "clear".
class HistoryView extends StatelessWidget {
  const HistoryView({super.key});

  BadgeTone _tone(TransferStatus s) => switch (s) {
        TransferStatus.completed => BadgeTone.success,
        TransferStatus.cancelled => BadgeTone.neutral,
        _ => BadgeTone.error,
      };

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HistoryViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final records = vm.records;
    final compact = MediaQuery.sizeOf(context).width < 700;

    return Padding(
      padding: EdgeInsets.all(compact ? 16 : 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 8, children: [
          Text('Transfer History',
              style: Theme.of(context).textTheme.headlineSmall),
          OutlinedButton.icon(
            onPressed: vm.allRecords.isEmpty
                ? null
                : () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Clear transfer history?',
                      message:
                          'This removes the list of past transfers. Files you already received are not deleted.',
                      confirmLabel: 'Clear history',
                      destructive: true,
                    );
                    if (ok) await vm.clear();
                  },
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Clear history'),
          ),
        ]),
        const SizedBox(height: 18),
        if (compact) ...[
          TextField(
            onChanged: vm.setQuery,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search file, computer, IP or error',
            ),
          ),
          Wrap(spacing: 12, runSpacing: 4, children: [
            DropdownButton<DirectionFilter>(
              value: vm.directionFilter,
              onChanged: (v) => vm.setDirection(v ?? DirectionFilter.all),
              items: const [
                DropdownMenuItem(
                    value: DirectionFilter.all, child: Text('Sent & received')),
                DropdownMenuItem(
                    value: DirectionFilter.sent, child: Text('Sent')),
                DropdownMenuItem(
                    value: DirectionFilter.received, child: Text('Received')),
              ],
            ),
            const SizedBox(width: 12),
            DropdownButton<TransferStatus?>(
              value: vm.statusFilter,
              onChanged: vm.setStatus,
              items: [
                const DropdownMenuItem(value: null, child: Text('Any status')),
                for (final s in TransferStatus.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
            ),
          ]),
        ] else
          Row(children: [
            Expanded(
              child: TextField(
                onChanged: vm.setQuery,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search file, computer, IP or error',
                ),
              ),
            ),
            const SizedBox(width: 12),
            DropdownButton<DirectionFilter>(
              value: vm.directionFilter,
              onChanged: (v) => vm.setDirection(v ?? DirectionFilter.all),
              items: const [
                DropdownMenuItem(
                    value: DirectionFilter.all, child: Text('Sent & received')),
                DropdownMenuItem(
                    value: DirectionFilter.sent, child: Text('Sent')),
                DropdownMenuItem(
                    value: DirectionFilter.received, child: Text('Received')),
              ],
            ),
            const SizedBox(width: 12),
            DropdownButton<TransferStatus?>(
              value: vm.statusFilter,
              onChanged: vm.setStatus,
              items: [
                const DropdownMenuItem(value: null, child: Text('Any status')),
                for (final s in TransferStatus.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
            ),
          ]),
        const SizedBox(height: 18),
        Expanded(
          child: Card(
            child: records.isEmpty
                ? EmptyState(
                    icon: Icons.history_rounded,
                    title: vm.allRecords.isEmpty
                        ? 'No transfers yet'
                        : 'No matches',
                    message: vm.allRecords.isEmpty
                        ? 'Completed, failed and cancelled transfers are listed here.'
                        : 'Try a different search or filter.',
                  )
                : ListView.separated(
                    itemCount: records.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = records[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        child: Row(children: [
                          Icon(
                              r.isOutgoing
                                  ? Icons.north_east_rounded
                                  : Icons.south_west_rounded,
                              color: scheme.primary),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.fileName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  Text(
                                    '${r.isOutgoing ? 'To' : 'From'} ${r.peerName} (${r.peerIp}) · ${FormatUtils.bytes(r.sizeBytes)} · ${FormatUtils.dateTime(r.finishedAt)}',
                                    style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 12.5),
                                  ),
                                  Text(
                                    'Took ${FormatUtils.duration(r.duration)} · avg ${r.averageMbPerSecond.toStringAsFixed(1)} MB/s',
                                    style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 12.5),
                                  ),
                                  if (r.error != null)
                                    Text(r.error!,
                                        style: TextStyle(
                                            color: scheme.error,
                                            fontSize: 12.5)),
                                ]),
                          ),
                          StatusBadge(
                              label: r.status.label, tone: _tone(r.status)),
                        ]),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}
