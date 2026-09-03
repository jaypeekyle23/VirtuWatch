import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'customer_home_tab.dart';
import 'customer_catalog_tab.dart';
import 'customer_profile_tab.dart';

class CustomerShell extends StatefulWidget {
  final String username;
  const CustomerShell({super.key, required this.username});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      CustomerHomeTab(username: widget.username),
      const CustomerCatalogTab(),
      const CustomerProfileTab(),
    ];

    return Scaffold(
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
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: AppTheme.gold),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.watch_outlined),
            selectedIcon: Icon(Icons.watch, color: AppTheme.gold),
            label: 'Catalog',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppTheme.gold),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}