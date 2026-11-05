import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

import 'package:go_router/go_router.dart';

class MainNavigationScreen extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainNavigationScreen({
    super.key,
    required this.navigationShell,
  });

  /// Allows any widget in the tree to switch the active tab programmatically.
  static final ValueNotifier<int> tabNotifier = ValueNotifier<int>(0);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {

  @override
  void initState() {
    super.initState();
    MainNavigationScreen.tabNotifier.addListener(_onExternalTabChange);
  }

  void _onExternalTabChange() {
    final newIndex = MainNavigationScreen.tabNotifier.value;
    if (newIndex != widget.navigationShell.currentIndex) {
      _onTap(newIndex);
    }
  }

  void _onTap(int index) {
    HapticFeedback.selectionClick();
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  void dispose() {
    MainNavigationScreen.tabNotifier.removeListener(_onExternalTabChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // Required for bottom app bar notch
      body: widget.navigationShell,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.push('/qr');
        },
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.qr_code_scanner, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _BottomNav(
        currentIndex: widget.navigationShell.currentIndex,
        onTap: _onTap,
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(180),
            border: Border(
              top: BorderSide(color: Colors.white.withAlpha(128), width: 0.5),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTab(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
                  _buildTab(1, Icons.business_outlined, Icons.business_rounded, 'Establishments'),
                  const SizedBox(width: 48), // Space for FAB
                  _buildTab(2, Icons.history_outlined, Icons.history_rounded, 'History'),
                  _buildTab(3, Icons.map_outlined, Icons.map_rounded, 'Map'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // [REF: BOTTOM_NAV_TABS]
  Widget _buildTab(int index, IconData icon, IconData activeIcon, String label) {
    final isActive = currentIndex == index;
    const activeColor = AppTheme.secondary; // Slate for active tabs

    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? activeColor.withAlpha(15) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isActive ? activeIcon : icon,
                color: isActive ? activeColor : Colors.grey.shade400,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                color: isActive ? activeColor : Colors.grey.shade500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
