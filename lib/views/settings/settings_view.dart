import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utilities/fingerprint.dart';
import '../../viewmodels/device_viewmodel.dart';
import '../../viewmodels/settings_viewmodel.dart';

/// VIEW: settings form bound to SettingsViewModel (validation lives there).
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _port;
  late final TextEditingController _dir;
  late final TextEditingController _concurrent;
  late final TextEditingController _maxSize;
  late final TextEditingController _chunk;
  late bool _startup, _discovery, _notify, _autoAccept;
  late ThemeMode _theme;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsViewModel>().settings;
    _name = TextEditingController(text: s.deviceName);
    _port = TextEditingController(text: '${s.port}');
    _dir = TextEditingController(text: s.downloadDir);
    _concurrent = TextEditingController(text: '${s.maxConcurrentTransfers}');
    _maxSize = TextEditingController(text: '${s.maxFileSizeMb}');
    _chunk = TextEditingController(text: '${s.chunkSizeKb}');
    _startup = s.launchAtStartup;
    _discovery = s.discoveryEnabled;
    _notify = s.notificationsEnabled;
    _autoAccept = s.autoAcceptTrusted;
    _theme = s.themeMode;
  }

  @override
  void dispose() {
    for (final c in [_name, _port, _dir, _concurrent, _maxSize, _chunk]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _browse() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) setState(() => _dir.text = dir);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final vm = context.read<SettingsViewModel>();
    final next = vm.settings.copyWith(
      deviceName: _name.text.trim(),
      port: int.parse(_port.text.trim()),
      downloadDir: _dir.text.trim(),
      themeMode: _theme,
      launchAtStartup: _startup,
      maxConcurrentTransfers: int.parse(_concurrent.text.trim()),
      maxFileSizeMb: int.parse(_maxSize.text.trim()),
      chunkSizeKb: int.parse(_chunk.text.trim()),
      discoveryEnabled: _discovery,
      notificationsEnabled: _notify,
      autoAcceptTrusted: _autoAccept,
    );
    final error = await vm.save(next);
    if (!mounted) return;
    if (error != null) {
      setState(() => _startup = vm.settings.launchAtStartup);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Settings saved.')),
    );
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              ...children,
            ]),
          ),
        ),
      );

  Widget _field(
          String label, TextEditingController c, FormFieldValidator<String> v,
          {String? helper, Widget? suffix}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: c,
          validator: v,
          decoration: InputDecoration(
              labelText: label, helperText: helper, suffixIcon: suffix),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final devices = context.watch<DeviceViewModel>();
    final vm = context.read<SettingsViewModel>();
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Form(
      key: _formKey,
      child: ListView(padding: EdgeInsets.all(compact ? 16 : 32), children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 24),
        _section('This computer', [
          _field('Computer display name', _name,
              SettingsViewModel.validateDeviceName),
          _field('Default download folder', _dir,
              SettingsViewModel.validateDownloadDir,
              suffix: IconButton(
                  icon: const Icon(Icons.folder_open_rounded),
                  onPressed: _browse,
                  tooltip: 'Browse')),
        ]),
        _section('Network', [
          _field('Receiving port (TCP)', _port, SettingsViewModel.validatePort,
              helper:
                  'Changing this restarts the receiving service. Allow it through your firewall.'),
          if (vm.startupSupported)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Device discovery'),
              subtitle: const Text(
                  'Announce this computer and find others (UDP broadcast).'),
              value: _discovery,
              onChanged: (v) => setState(() => _discovery = v),
            ),
        ]),
        _section('Transfers', [
          _field('Maximum concurrent transfers', _concurrent,
              SettingsViewModel.validateConcurrent),
          _field('Maximum accepted file size (MB)', _maxSize,
              SettingsViewModel.validateMaxFileSizeMb),
          _field(
              'Chunk size (KB)', _chunk, SettingsViewModel.validateChunkSizeKb,
              helper:
                  'Size of each network block. 256 KB works well on most LANs.'),
        ]),
        _section('Trusted devices', [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
                'Accept transfers from trusted devices without asking'),
            subtitle: const Text(
                'Off by default. Only devices you trust below are affected.'),
            value: _autoAccept,
            onChanged: (v) => setState(() => _autoAccept = v),
          ),
          if (devices.trustedDevices.isEmpty)
            const Text(
                'No trusted devices. Trust a device from the Devices page.')
          else
            for (final t in devices.trustedDevices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.verified_user_rounded),
                title: Text(t.name),
                subtitle: Text('ID ${Fingerprint.short(t.id)}'),
                trailing: TextButton(
                  onPressed: () => devices.untrust(t.id),
                  child: const Text('Remove'),
                ),
              ),
        ]),
        _section('Appearance & behavior', [
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto_rounded)),
              ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_rounded)),
              ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_rounded)),
            ],
            selected: {_theme},
            onSelectionChanged: (s) => setState(() => _theme = s.first),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Launch at Windows startup'),
            subtitle: const Text(
                'Adds Humanize to your user startup list (no admin rights needed).'),
            value: _startup,
            onChanged: (v) => setState(() => _startup = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Notifications'),
            subtitle: const Text(
                'Show messages for incoming requests and finished transfers.'),
            value: _notify,
            onChanged: (v) => setState(() => _notify = v),
          ),
        ]),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save settings'),
          ),
        ),
      ]),
    );
  }
}
