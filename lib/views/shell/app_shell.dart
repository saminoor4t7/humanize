import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/file_transfer_service.dart';
import '../../viewmodels/navigation_viewmodel.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../viewmodels/transfer_viewmodel.dart';
import '../../widgets/app_sidebar.dart';
import '../about/about_view.dart';
import '../dashboard/dashboard_view.dart';
import '../devices/devices_view.dart';
import '../history/history_view.dart';
import '../receive/receive_view.dart';
import '../send/send_view.dart';
import '../settings/settings_view.dart';

/// VIEW: sidebar + content, plus in-app notifications for service events.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  StreamSubscription<ServiceEvent>? _sub;

  @override
  void initState() {
    super.initState();
    final transfers = context.read<TransferViewModel>();
    _sub = transfers.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onEvent(ServiceEvent e) {
    if (!mounted) return;
    if (!context.read<SettingsViewModel>().settings.notificationsEnabled &&
        e.kind != ServiceEventKind.error) {
      return;
    }
    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      width: MediaQuery.sizeOf(context).width >= 492 ? 460 : null,
      backgroundColor:
          e.kind == ServiceEventKind.error ? scheme.errorContainer : null,
      content: Text(e.message,
          style: e.kind == ServiceEventKind.error
              ? TextStyle(color: scheme.onErrorContainer)
              : null),
      action: e.kind == ServiceEventKind.incomingRequest
          ? SnackBarAction(
              label: 'Review',
              onPressed: () =>
                  context.read<NavigationViewModel>().go(AppPage.receive))
          : null,
    ));
    // An incoming request should never be missed.
    if (e.kind == ServiceEventKind.incomingRequest) {
      context.read<NavigationViewModel>().go(AppPage.receive);
    }
  }

  Widget _page(AppPage page) => switch (page) {
        AppPage.dashboard => const DashboardView(),
        AppPage.send => const SendView(),
        AppPage.receive => const ReceiveView(),
        AppPage.devices => const DevicesView(),
        AppPage.history => const HistoryView(),
        AppPage.settings => const SettingsView(),
        AppPage.about => const AboutView(),
      };

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationViewModel>();
    final pending =
        context.select<TransferViewModel, int>((v) => v.pendingRequests.length);
    final compact = MediaQuery.sizeOf(context).width < 800;
    return Scaffold(
      appBar: compact ? AppBar(title: Text(nav.current.label)) : null,
      drawer: compact
          ? Drawer(
              child: SafeArea(
                child: AppSidebar(
                  selected: nav.current,
                  pendingRequests: pending,
                  onSelect: (page) {
                    nav.go(page);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            )
          : null,
      body: Row(children: [
        if (!compact)
          AppSidebar(
              selected: nav.current,
              onSelect: nav.go,
              pendingRequests: pending),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(
                key: ValueKey(nav.current), child: _page(nav.current)),
          ),
        ),
      ]),
    );
  }
}
