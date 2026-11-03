import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utilities/fingerprint.dart';
import '../../services/security_service.dart';

class AboutView extends StatelessWidget {
  const AboutView({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final id = context.read<SecurityService>().identity.id;
    return ListView(padding: const EdgeInsets.all(32), children: [
      Text('About Humanize', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(AppConstants.appName, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Version ${AppConstants.appVersion}', style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            const Text(
              'Humanize sends files directly between computers on the same local network. '
              'No cloud, no internet. Every connection is encrypted with TLS and every '
              'computer proves its identity before anything is accepted. Received files are '
              'verified with SHA-256 and are never opened or run automatically.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 20),
            Text('This computer\'s device ID', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            SelectableText(Fingerprint.short(id),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text('Compare this with the ID shown on the other computer before trusting it.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
          ]),
        ),
      ),
    ]);
  }
}
