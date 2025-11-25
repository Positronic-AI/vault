import 'package:flutter/material.dart';
import 'camera_screen.dart';
import 'gallery_screen.dart';
import 'settings_screen.dart';
import '../main.dart';

/// Persists selected tab index across Navigator rebuilds
int _persistedTabIndex = 0;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = _persistedTabIndex;

  final List<Widget> _screens = const [
    GalleryScreen(),
    CameraScreen(),
    SettingsScreen(),  // About screen (3rd in the list, now 4th in nav bar)
  ];

  void _handleLockApp() {
    _persistedTabIndex = 0; // Reset to gallery on lock
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: _screens[_selectedIndex == 3 ? 2 : _selectedIndex],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            if (index == 2) {
              // Lock button pressed - don't change selection, just lock
              _handleLockApp();
            } else {
              setState(() {
                _selectedIndex = index;
                _persistedTabIndex = index;
              });
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library),
              label: 'Gallery',
            ),
            NavigationDestination(
              icon: Icon(Icons.camera_alt_outlined),
              selectedIcon: Icon(Icons.camera_alt),
              label: 'Camera',
            ),
            NavigationDestination(
              icon: Icon(Icons.lock_outline),
              selectedIcon: Icon(Icons.lock),
              label: 'Lock',
            ),
            NavigationDestination(
              icon: Icon(Icons.info_outline),
              selectedIcon: Icon(Icons.info),
              label: 'About',
            ),
          ],
        ),
      ),
    );
  }
}
