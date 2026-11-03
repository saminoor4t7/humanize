import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utilities/format_utils.dart';
import '../../viewmodels/device_viewmodel.dart';
import '../../viewmodels/send_viewmodel.dart';
import '../../widgets/device_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/transfer_card.dart';
import '../../viewmodels/transfer_viewmodel.dart';

/// VIEW: choose files/folders and a destination, then send.
class SendView extends StatefulWidget {
  const SendView({super.key});

  @override
  State<SendView> createState() => _SendViewState();
}

class _SendViewState extends State<SendView> {
  final _ip = TextEditingController();
  final _port = TextEditingController(text: '${SendViewModel.defaultPort}');
  bool _manual = false;

  @override
  void dispose() {
    _ip.dispose();
    _port.dispose();
    super.dispose();
  }

  void _show(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _send(SendViewModel vm) {
    final error =
        _manual ? vm.sendToAddress(_ip.text, _port.text) : vm.sendToSelected();
    if (error != null) _show(error);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SendViewModel>();
    final devices = context.watch<DeviceViewModel>();
    final transfers = context.watch<TransferViewModel>();
    final scheme = Theme.of(context).colorScheme;
    final outgoing = transfers.outgoing;
    final compact = MediaQuery.sizeOf(context).width < 600;

    return ListView(padding: EdgeInsets.all(compact ? 16 : 32), children: [
      Text('Send Files', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      Text('Choose what to send, then choose a computer.',
          style: TextStyle(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 24),

      // 1. Files
      Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 8,
                children: [
                  Text('1. Files',
                      style: Theme.of(context).textTheme.titleMedium),
                  OutlinedButton.icon(
                    onPressed: vm.isScanning ? null : vm.pickFiles,
                    icon: const Icon(Icons.insert_drive_file_outlined),
                    label: const Text('Add files'),
                  ),
                  OutlinedButton.icon(
                    onPressed: vm.isScanning ? null : vm.pickFolder,
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Add folder'),
                  ),
                ]),
            if (vm.isScanning)
              const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator()),
            if (vm.notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(vm.notice!, style: TextStyle(color: scheme.error)),
              ),
            const SizedBox(height: 12),
            if (vm.files.isEmpty)
              SizedBox(
                height: compact ? 230 : 210,
                child: EmptyState(
                  icon: Icons.upload_file_rounded,
                  title: 'No files selected',
                  message: 'Add files or a whole folder to send.',
                ),
              )
            else ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: vm.files.length,
                  itemBuilder: (_, i) {
                    final f = vm.files[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(f.relPath, overflow: TextOverflow.ellipsis),
                      subtitle: Text(FormatUtils.bytes(f.size)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Remove',
                        onPressed: () => vm.removeAt(i),
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
              Row(children: [
                Text(
                    '${vm.files.length} file${vm.files.length == 1 ? '' : 's'} · ${FormatUtils.bytes(vm.totalBytes)} total',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                    onPressed: vm.clearFiles, child: const Text('Clear all')),
              ]),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 18),

      // 2. Destination
      Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 8,
                children: [
                  Text('2. Destination',
                      style: Theme.of(context).textTheme.titleMedium),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: false, label: Text('Discovered devices')),
                      ButtonSegment(value: true, label: Text('IP address')),
                    ],
                    selected: {_manual},
                    onSelectionChanged: (s) =>
                        setState(() => _manual = s.first),
                  ),
                ]),
            const SizedBox(height: 14),
            if (_manual)
              Row(children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _ip,
                    decoration: const InputDecoration(
                        labelText: 'IP address', hintText: '192.168.1.20'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                      controller: _port,
                      decoration: const InputDecoration(labelText: 'Port')),
                ),
              ])
            else if (devices.devices.isEmpty)
              SizedBox(
                height: compact ? 300 : 240,
                child: EmptyState(
                  icon: Icons.devices_rounded,
                  title: 'No devices found yet',
                  message:
                      'Make sure Humanize is running on the other computer, or use an IP address.',
                ),
              )
            else
              Wrap(spacing: 14, runSpacing: 14, children: [
                for (final d in devices.devices)
                  SizedBox(
                    width: 300,
                    child: DeviceCard(
                      view: d,
                      selected: vm.selectedDevice?.device.id == d.device.id,
                      onTap: () => vm.selectDevice(d.device.id),
                    ),
                  ),
              ]),
          ]),
        ),
      ),
      const SizedBox(height: 18),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: vm.canSend ? () => _send(vm) : null,
          icon: const Icon(Icons.send_rounded),
          label: const Text('Send'),
        ),
      ),

      if (outgoing.isNotEmpty) ...[
        const SizedBox(height: 28),
        Text('Outgoing transfers',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final t in outgoing.take(10)) ...[
          TransferCard(transfer: t, onCancel: () => transfers.cancel(t.id)),
          const SizedBox(height: 12),
        ],
      ],
    ]);
  }
}
