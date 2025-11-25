import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';

/// Global flag to suppress auto-lock during permission requests
bool suppressAutoLock = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode for security
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const VaultApp());
}

class VaultApp extends StatelessWidget {
  const VaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  bool _hasPassword = false;
  bool _isAuthenticated = false;
  bool _requiresAuth = false;

  // Key increments on lock to force Navigator reset, clearing any open screens
  int _navKey = 0;

  // Privacy screen shown immediately when app goes to background
  bool _showPrivacyScreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAuthStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // Show privacy screen immediately to hide content
      // Don't trigger if already requiring auth (user is on auth screen)
      if (_isAuthenticated && !_requiresAuth && !suppressAutoLock) {
        setState(() {
          _showPrivacyScreen = true;
        });
      }
    }
    if (state == AppLifecycleState.paused) {
      // App went to background - require re-auth unless suppressed
      if (_isAuthenticated && !suppressAutoLock) {
        setState(() {
          _requiresAuth = true;
          _navKey++; // Force Navigator reset to clear any open media viewers
        });
      }
    }
    if (state == AppLifecycleState.resumed) {
      // Clear privacy screen (auth screen will show if needed)
      setState(() {
        _showPrivacyScreen = false;
      });
    }
  }

  Future<void> _checkAuthStatus() async {
    final hasPassword = await _authService.hasPassword();
    setState(() {
      _hasPassword = hasPassword;
      _isLoading = false;
    });
  }

  void _onAuthenticated() {
    setState(() {
      _isAuthenticated = true;
      _requiresAuth = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Privacy screen covers everything immediately when app goes to background
    if (_showPrivacyScreen) {
      return const Scaffold(
        body: Center(
          child: Icon(Icons.lock, size: 64),
        ),
      );
    }

    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Show auth screen if not authenticated or requires re-auth
    if (!_isAuthenticated || _requiresAuth) {
      return AuthScreen(
        isFirstTime: !_hasPassword,
        onAuthenticated: _onAuthenticated,
      );
    }

    // Show home screen when authenticated
    // Use Navigator with key to ensure route stack resets on lock
    return Navigator(
      key: ValueKey(_navKey),
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => const HomeScreen(),
      ),
    );
  }
}
