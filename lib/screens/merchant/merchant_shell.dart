import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'merchant_dashboard_tab.dart';
import 'merchant_catalog_tab.dart';
import 'merchant_analytics_tab.dart';
import 'merchant_profile_tab.dart';

class MerchantShell extends StatefulWidget {
  final String username;
  const MerchantShell({super.key, required this.username});

  @override
  State<MerchantShell> createState() => _MerchantShellState();
}

class _MerchantShellState extends State<MerchantShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      MerchantDashboardTab(username: widget.username),
      const MerchantCatalogTab(),
      const MerchantAnalyticsTab(),
      const MerchantProfileTab(),
    ];

    return PopScope(
      // Only let the system/back-gesture actually pop (and exit the app,
      // since this shell sits directly on AuthGate with no route behind
      // it) while already on the Dashboard tab. From any other tab, back
      // should return to Dashboard first — without this, backing out of
      // e.g. the Catalog tab closes the app entirely, since there's no
      // pushed route for Navigator to pop.
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() => _currentIndex = 0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: tabs,
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() => _currentIndex = index);
          },
          backgroundColor: AppTheme.surface,
          indicatorColor: AppTheme.gold.withValues(alpha: 0.2),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard, color: AppTheme.gold),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.watch_outlined),
              selectedIcon: Icon(Icons.watch, color: AppTheme.gold),
              label: 'Catalog',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart, color: AppTheme.gold),
              label: 'Analytics',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: AppTheme.gold),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}