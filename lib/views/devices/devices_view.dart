import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../viewmodels/device_viewmodel.dart';
import '../../viewmodels/send_viewmodel.dart';
import '../../widgets/device_card.dart';
import '../../widgets/empty_state.dart';

/// VIEW: discovered devices, refresh, manual add, trust.
class DevicesView extends StatelessWidget {
  const DevicesView({super.key});

  Future<void> _addManual(BuildContext context) async {
    final vm = context.read<DeviceViewModel>();
    final ip = TextEditingController();
    final port = TextEditingController(text: '${SendViewModel.defaultPort}');
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add device by IP address'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: ip,
                  decoration: const InputDecoration(
                      labelText: 'IP address', hintText: '192.168.1.20')),
              const SizedBox(height: 12),
              TextField(
                  controller: port,
                  decoration: const InputDecoration(labelText: 'Port')),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(error!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final e = await vm.addManual(ip.text, port.text);
                if (e == null) {
                  if (ctx.mounted) Navigator.pop(ctx);
                } else {
                  setState(() => error = e);
                }
              },
              child: const Text('Connect and add'),
            ),
          ],
        );
      }),
    );
    ip.dispose();
    port.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DeviceViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final devices = vm.devices;
    final compact = MediaQuery.sizeOf(context).width < 600;

    return ListView(padding: EdgeInsets.all(compact ? 16 : 32), children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Devices', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
            '${vm.onlineCount} online · discovery is only a hint; identity is verified when you connect.',
            style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        Wrap(spacing: 10, children: [
          OutlinedButton.icon(
            onPressed: () => _addManual(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add by IP'),
          ),
          FilledButton.icon(
            onPressed: vm.refresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
        ]),
      ]),
      if (vm.discoveryError != null)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child:
              Text(vm.discoveryError!, style: TextStyle(color: scheme.error)),
        ),
      if (!vm.discoveryRunning && vm.discoveryError == null)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(
              'Discovery is turned off in Settings. You can still add devices by IP.',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      const SizedBox(height: 24),
      if (devices.isEmpty)
        const Card(
          child: SizedBox(
            height: 260,
            child: EmptyState(
              icon: Icons.devices_rounded,
              title: 'No other computers found',
              message:
                  'Open Humanize on another computer on this network, then press Refresh. '
                  'If your network blocks broadcasts, add the computer by IP address.',
            ),
          ),
        )
      else
        Wrap(spacing: 16, runSpacing: 16, children: [
          for (final d in devices)
            SizedBox(
              width: 340,
              child: DeviceCard(
                view: d,
                onToggleTrust: () =>
                    d.trusted ? vm.untrust(d.device.id) : vm.trust(d.device),
              ),
            ),
        ]),
    ]);
  }
}
