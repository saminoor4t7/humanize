import 'package:flutter/foundation.dart';

/// The seven sidebar destinations.
enum AppPage {
  dashboard('Dashboard'),
  send('Send Files'),
  receive('Receive Files'),
  devices('Devices'),
  history('Transfer History'),
  settings('Settings'),
  about('About Humanize');

  const AppPage(this.label);
  final String label;
}

/// VIEWMODEL: which page is showing.
class NavigationViewModel extends ChangeNotifier {
  AppPage _current = AppPage.dashboard;
  AppPage get current => _current;

  void go(AppPage page) {
    if (page == _current) return;
    _current = page;
    notifyListeners();
  }
}
