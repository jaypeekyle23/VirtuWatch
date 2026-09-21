import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'customer_home_tab.dart';
import 'customer_catalog_tab.dart';
import 'customer_profile_tab.dart';
import 'ar_try_on_screen.dart';
import 'recommended_for_you_screen.dart';

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
    // Only the four tabs below are kept alive via IndexedStack — none of
    // them own a camera, so preserving their state (scroll position etc.)
    // in the background is fine.
    //
    // AR Try-On (index 2) is deliberately NOT in this list. It opens a
    // real camera + MediaPipe hand-tracking pipeline in initState(), so
    // it must only exist in the widget tree while it's the active tab —
    // otherwise it starts the camera the moment Home loads and keeps it
    // running the whole time you're using the app. It's built fresh
    // below only when _currentIndex == 2, and fully removed (which runs
    // its dispose(), stopping the camera) the moment you switch away.
    final persistentTabs = [
      CustomerHomeTab(username: widget.username),
      const CustomerCatalogTab(),
      const RecommendedForYouScreen(),
      const CustomerProfileTab(),
    ];
    // Map the 5-tab _currentIndex onto the 4-tab persistentTabs list,
    // skipping index 2 (AR Try-On).
    final persistentIndex =
        _currentIndex < 2 ? _currentIndex : _currentIndex - 1;

    return Scaffold(
      body: _currentIndex == 2
          ? const ArTryOnScreen()
          : IndexedStack(
              index: persistentIndex,
              children: persistentTabs,
            ),
      bottomNavigationBar: Container(
        color: AppTheme.surface,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.surface,
                    border: Border(
                      top: BorderSide(color: Color(0x1AFFFFFF)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _navItem(
                          icon: Icons.home_outlined,
                          selectedIcon: Icons.home,
                          label: 'Home',
                          index: 0,
                        ),
                      ),
                      Expanded(
                        child: _navItem(
                          icon: Icons.watch_outlined,
                          selectedIcon: Icons.watch,
                          label: 'Catalog',
                          index: 1,
                        ),
                      ),
                      const Expanded(child: SizedBox()),
                      Expanded(
                        child: _navItem(
                          icon: Icons.auto_awesome_outlined,
                          selectedIcon: Icons.auto_awesome,
                          label: 'For You',
                          index: 3,
                        ),
                      ),
                      Expanded(
                        child: _navItem(
                          icon: Icons.person_outline,
                          selectedIcon: Icons.person,
                          label: 'Profile',
                          index: 4,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: -16,
                  child: GestureDetector(
                    onTap: () => setState(() => _currentIndex = 2),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.gold,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.surface, width: 3),
                      ),
                      child: Icon(
                        Icons.view_in_ar,
                        color: const Color(0xFF0E1A2B),
                        size: _currentIndex == 2 ? 28 : 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required int index,
  }) {
    final isSelected = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              color: isSelected ? AppTheme.gold : AppTheme.textSecondary,
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppTheme.gold : AppTheme.textSecondary,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}