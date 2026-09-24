import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'admin_dashboard_tab.dart';
import 'admin_watch_management_tab.dart';
import 'admin_account_management_screen.dart';
import 'admin_profile_tab.dart';

class AdminShell extends StatefulWidget {
  final String username;
  const AdminShell({super.key, required this.username});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      AdminDashboardTab(username: widget.username),
      const AdminWatchManagementTab(),
      const AdminAccountManagementScreen(),
      const AdminProfileTab(),
    ];

    return PopScope(
      // Only let the system/back-gesture actually pop (and exit the app,
      // since this shell sits directly on AuthGate with no route behind
      // it) while already on the Dashboard tab. From any other tab, back
      // should return to Dashboard first — without this, backing out of
      // e.g. the Watches tab closes the app entirely, since there's no
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
              label: 'Watches',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people, color: AppTheme.gold),
              label: 'Accounts',
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