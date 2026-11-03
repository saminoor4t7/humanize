import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utilities/fingerprint.dart';
import '../../core/utilities/format_utils.dart';
import '../../models/transfer_request.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../viewmodels/transfer_viewmodel.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/transfer_card.dart';

/// VIEW: incoming requests (approve/reject), live receives, download folder.
class ReceiveView extends StatelessWidget {
  const ReceiveView({super.key});

  Future<void> _pickDir(BuildContext context) async {
    final settingsVm = context.read<SettingsViewModel>();
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    await settingsVm.update(settingsVm.settings.copyWith(downloadDir: dir));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TransferViewModel>();
    final settings = context.watch<SettingsViewModel>().settings;
    final scheme = Theme.of(context).colorScheme;
    final incoming = vm.incoming;
    final compact = MediaQuery.sizeOf(context).width < 600;

    return ListView(padding: EdgeInsets.all(compact ? 16 : 32), children: [
      Text('Receive Files', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      Text('Nothing is saved until you accept it.',
          style: TextStyle(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 8,
                children: [
                  Text('Receiving service',
                      style: Theme.of(context).textTheme.titleMedium),
                  vm.isListening
                      ? StatusBadge(
                          label: 'Listening on port ${vm.listeningPort}',
                          tone: BadgeTone.success)
                      : const StatusBadge(
                          label: 'Not listening', tone: BadgeTone.error),
                ]),
            if (vm.serverError != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(vm.serverError!,
                    style: TextStyle(color: scheme.error)),
              ),
            const SizedBox(height: 14),
            Row(children: [
              const Icon(Icons.folder_rounded),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(settings.downloadDir,
                      overflow: TextOverflow.ellipsis)),
              if (!compact)
                OutlinedButton(
                    onPressed: () => _pickDir(context),
                    child: const Text('Change folder')),
            ]),
            if (compact)
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                    onPressed: () => _pickDir(context),
                    child: const Text('Change folder')),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 22),
      if (vm.pendingRequests.isNotEmpty) ...[
        Text('Incoming requests',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final r in vm.pendingRequests) ...[
          _RequestCard(
              request: r,
              onAccept: () => vm.accept(r.id),
              onReject: () => vm.reject(r.id)),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 10),
      ],
      Text('Receiving', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      if (incoming.isEmpty)
        Card(
          child: SizedBox(
            height: compact ? 240 : 220,
            child: const EmptyState(
              icon: Icons.download_rounded,
              title: 'Waiting for files',
              message: 'Incoming transfers will appear here for your approval.',
            ),
          ),
        )
      else
        for (final t in incoming.take(15)) ...[
          TransferCard(transfer: t, onCancel: () => vm.cancel(t.id)),
          const SizedBox(height: 12),
        ],
    ]);
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard(
      {required this.request, required this.onAccept, required this.onReject});

  final TransferRequest request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = request;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.primary, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 8, children: [
            const Icon(Icons.mark_email_unread_rounded),
            Text('${r.peerName} wants to send you files',
                style: Theme.of(context).textTheme.titleMedium),
            StatusBadge(
              label: r.trusted ? 'Trusted device' : 'Unknown device',
              tone: r.trusted ? BadgeTone.success : BadgeTone.warning,
            ),
          ]),
          const SizedBox(height: 8),
          Text(
              '${r.peerIp} · ID ${Fingerprint.short(r.peerId)} · ${r.files.length} file${r.files.length == 1 ? '' : 's'} · ${FormatUtils.bytes(r.totalBytes)}',
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          for (final f in r.files.take(5))
            Text('• ${f.relPath}  (${FormatUtils.bytes(f.size)})',
                overflow: TextOverflow.ellipsis),
          if (r.files.length > 5) Text('…and ${r.files.length - 5} more'),
          const SizedBox(height: 16),
          Row(children: [
            FilledButton.icon(
                onPressed: onAccept,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Accept')),
            const SizedBox(width: 10),
            OutlinedButton.icon(
                onPressed: onReject,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Reject')),
          ]),
        ]),
      ),
    );
  }
}
