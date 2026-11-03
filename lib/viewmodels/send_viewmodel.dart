import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/constants/app_constants.dart';
import '../core/constants/protocol_constants.dart';
import '../core/errors/app_exceptions.dart';
import '../core/utilities/network_info.dart';
import '../models/transfer.dart';
import 'device_viewmodel.dart';
import 'transfer_viewmodel.dart';

/// VIEWMODEL: the Send Files screen (selection, destination, start).
class SendViewModel extends ChangeNotifier {
  SendViewModel(this._transfers, this._devices);

  final TransferViewModel _transfers;
  final DeviceViewModel _devices;

  final List<SendFile> _files = [];
  String? _selectedDeviceId;
  bool _scanning = false;
  String? _notice;

  List<SendFile> get files => List.unmodifiable(_files);
  int get totalBytes => _files.fold(0, (s, f) => s + f.size);
  bool get isScanning => _scanning;
  String? get notice => _notice;

  /// The device chosen in the list (null when using manual IP).
  DeviceView? get selectedDevice {
    for (final d in _devices.devices) {
      if (d.device.id == _selectedDeviceId) return d;
    }
    return null;
  }

  bool get canSend => _files.isNotEmpty && !_scanning;

  void selectDevice(String? id) {
    _selectedDeviceId = id;
    notifyListeners();
  }

  void clearNotice() {
    _notice = null;
    notifyListeners();
  }

  Future<void> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    _scanning = true;
    notifyListeners();
    try {
      for (final pf in result.files) {
        final path = pf.path;
        if (path == null) continue;
        await _addFile(File(path), p.basename(path));
      }
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  /// Adds every file in a folder, preserving the folder structure.
  Future<void> pickFolder() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return;
    _scanning = true;
    _notice = null;
    notifyListeners();
    try {
      final top = p.basename(dirPath);
      var skipped = 0;
      await for (final e in Directory(dirPath).list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        if (_files.length >= ProtocolConstants.maxFilesPerTransfer) {
          _notice = 'Stopped at ${ProtocolConstants.maxFilesPerTransfer} files (the per-transfer limit).';
          break;
        }
        final rel = p.relative(e.path, from: dirPath).replaceAll('\\', '/');
        try {
          await _addFile(e, '$top/$rel');
        } on FileSystemException {
          skipped++;
        }
      }
      if (skipped > 0) {
        _notice = '$skipped file(s) could not be read and were skipped.';
      }
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  Future<void> _addFile(File file, String relPath) async {
    if (_files.any((f) => f.localPath == file.path)) return;
    final stat = await file.stat();
    _files.add(SendFile(
      localPath: file.path,
      relPath: relPath,
      size: stat.size,
      modifiedMs: stat.modified.millisecondsSinceEpoch,
    ));
  }

  void removeAt(int index) {
    if (index < 0 || index >= _files.length) return;
    _files.removeAt(index);
    notifyListeners();
  }

  void clearFiles() {
    _files.clear();
    _notice = null;
    notifyListeners();
  }

  /// Sends to the selected device. Returns an error message or null.
  String? sendToSelected() {
    final d = selectedDevice;
    if (d == null) return 'Choose a device first.';
    if (!d.online) return '${d.device.name} appears to be offline. Refresh the device list.';
    return _start(d.device.ip, d.device.port, d.device.name, d.device.id);
  }

  /// Sends to a typed IP address. Identity is learned on connect and is not
  /// verified in advance (the receiver still has to approve).
  String? sendToAddress(String host, String portText) {
    final h = host.trim();
    final port = int.tryParse(portText.trim());
    if (!NetworkInfo.isValidIPv4(h)) return 'Enter a valid IPv4 address.';
    if (!NetworkInfo.isPrivateOrLoopbackIPv4(h)) {
      return 'Only local-network addresses are allowed.';
    }
    if (port == null || port < 1 || port > 65535) return 'Enter a valid port.';
    return _start(h, port, null, null);
  }

  String? _start(String host, int port, String? name, String? expectedId) {
    if (_files.isEmpty) return 'Add at least one file.';
    try {
      _transfers.send(
        host: host,
        port: port,
        files: List.of(_files),
        peerName: name,
        expectedPeerId: expectedId,
      );
    } on HumanizeException catch (e) {
      return e.message;
    }
    _files.clear();
    _notice = null;
    notifyListeners();
    return null;
  }

  /// Default port shown in the manual-address field.
  static int get defaultPort => AppConstants.defaultPort;
}
