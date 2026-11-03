import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../viewmodels/navigation_viewmodel.dart';

/// Sidebar: logo + app name + the seven destinations.
/// Stateless: receives selection and a callback (the View layer stays dumb).
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.selected,
    required this.onSelect,
    this.pendingRequests = 0,
  });

  final AppPage selected;
  final ValueChanged<AppPage> onSelect;

  /// Shown as a badge on "Receive Files".
  final int pendingRequests;

  static const _icons = <AppPage, IconData>{
    AppPage.dashboard: Icons.dashboard_rounded,
    AppPage.send: Icons.upload_file_rounded,
    AppPage.receive: Icons.download_rounded,
    AppPage.devices: Icons.devices_rounded,
    AppPage.history: Icons.history_rounded,
    AppPage.settings: Icons.settings_rounded,
    AppPage.about: Icons.info_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: AppConstants.sidebarWidth,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
            right: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.6))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient:
                    LinearGradient(colors: [scheme.primary, scheme.tertiary]),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.swap_horiz_rounded, color: scheme.onPrimary),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppConstants.appName,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontSize: 20)),
              Text('LAN transfer',
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ]),
          ]),
          const SizedBox(height: 28),
          for (final page in AppPage.values) ...[
            _NavItem(
              icon: _icons[page]!,
              label: page.label,
              selected: page == selected,
              badge: page == AppPage.receive ? pendingRequests : 0,
              onTap: () => onSelect(page),
            ),
            const SizedBox(height: 4),
          ],
        ]),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppConstants.radiusM),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(AppConstants.radiusM),
          ),
          child: Row(children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: fg,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500)),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: scheme.error,
                    borderRadius: BorderRadius.circular(99)),
                child: Text('$badge',
                    style: TextStyle(
                        color: scheme.onError,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
      ),
    );
  }
}
