import 'package:flutter/material.dart';
import 'camera_screen.dart';
import 'gallery_screen.dart';
import 'settings_screen.dart';
import '../main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    GalleryScreen(),
    CameraScreen(),
    SettingsScreen(),  // About screen (3rd in the list, now 4th in nav bar)
  ];

  void _handleLockApp() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          if (index == 2) {
            // Lock button pressed (now 3rd position, index 2)
            _handleLockApp();
          } else if (index == 3) {
            // About button pressed (4th position, index 3) - maps to screen index 2
            setState(() {
              _selectedIndex = 2;
            });
          } else {
            setState(() {
              _selectedIndex = index;
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
    );
  }
}
