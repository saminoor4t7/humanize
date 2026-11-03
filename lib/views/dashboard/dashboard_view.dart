import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utilities/format_utils.dart';
import '../../models/transfer_record.dart';
import '../../viewmodels/dashboard_viewmodel.dart';
import '../../viewmodels/navigation_viewmodel.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/summary_card.dart';

/// VIEW: renders DashboardViewModel. Contains no business logic.
class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardViewModel>();
    final nav = context.read<NavigationViewModel>();
    final scheme = Theme.of(context).colorScheme;

    final networkBadge = vm.loadingNetwork
        ? const StatusBadge(label: 'Checking…')
        : vm.isOnLan
            ? const StatusBadge(
                label: 'Connected to LAN', tone: BadgeTone.success)
            : const StatusBadge(
                label: 'No LAN detected', tone: BadgeTone.warning);
    final serviceBadge = vm.isListening
        ? StatusBadge(
            label: 'Receiving on port ${vm.listeningPort}',
            tone: BadgeTone.success)
        : const StatusBadge(label: 'Receiver stopped', tone: BadgeTone.error);

    final compact = MediaQuery.sizeOf(context).width < 600;
    return ListView(padding: EdgeInsets.all(compact ? 16 : 32), children: [
      Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Dashboard', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('Overview of this computer and your transfers',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ]),
        ),
        IconButton.outlined(
          tooltip: 'Re-check network',
          onPressed: vm.refreshNetwork,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ]),
      if (vm.serverError != null)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(vm.serverError!, style: TextStyle(color: scheme.error)),
        ),
      const SizedBox(height: 24),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 640 ? 2 : 1);
        final w = (c.maxWidth - (cols - 1) * 16) / cols;
        Widget tile(Widget child) => SizedBox(width: w, child: child);
        return Wrap(spacing: 16, runSpacing: 16, children: [
          tile(SummaryCard(
              icon: Icons.computer_rounded,
              label: 'This computer',
              value: vm.deviceName,
              footer: serviceBadge)),
          tile(SummaryCard(
              icon: Icons.lan_rounded,
              label: 'Local IP address',
              value: vm.localIp ?? '—',
              footer: networkBadge)),
          tile(SummaryCard(
              icon: Icons.devices_rounded,
              label: 'Devices online',
              value: '${vm.discoveredDevices}')),
          tile(SummaryCard(
              icon: Icons.sync_rounded,
              label: 'Active transfers',
              value: '${vm.activeTransfers}')),
          tile(SummaryCard(
              icon: Icons.check_circle_outline_rounded,
              label: 'Completed transfers',
              value: '${vm.completedTransfers}')),
          tile(SummaryCard(
              icon: Icons.data_usage_rounded,
              label: 'Total transferred',
              value: FormatUtils.bytes(vm.totalBytesTransferred))),
        ]);
      }),
      const SizedBox(height: 24),
      Wrap(spacing: 12, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: () => nav.go(AppPage.send),
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Send files'),
        ),
        OutlinedButton.icon(
          onPressed: () => nav.go(AppPage.receive),
          icon: const Icon(Icons.download_rounded),
          label: const Text('Receive files'),
        ),
      ]),
      const SizedBox(height: 28),
      Text('Recent transfers', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      Card(
        child: vm.recentTransfers.isEmpty
            ? const SizedBox(
                height: 220,
                child: EmptyState(
                  icon: Icons.inbox_rounded,
                  title: 'No transfers yet',
                  message: 'Files you send or receive will appear here.',
                ),
              )
            : Column(children: [
                for (final r in vm.recentTransfers) _RecentRow(record: r)
              ]),
      ),
    ]);
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.record});
  final TransferRecord record;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(record.isOutgoing
          ? Icons.north_east_rounded
          : Icons.south_west_rounded),
      title: Text(record.fileName, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          '${record.isOutgoing ? "To" : "From"} ${record.peerName} · ${FormatUtils.bytes(record.sizeBytes)}'),
      trailing: StatusBadge(
        label: record.status.label,
        tone: record.status == TransferStatus.completed
            ? BadgeTone.success
            : BadgeTone.error,
      ),
    );
  }
}
