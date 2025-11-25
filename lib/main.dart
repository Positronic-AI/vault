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

  // Navigator key for accessing state to handle back button
  // Recreated on lock to reset navigation stack
  GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

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
          // Create new navigator key to reset stack on re-auth
          _navigatorKey = GlobalKey<NavigatorState>();
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
    // PopScope intercepts back button; we use maybePop to respect inner PopScopes
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _navigatorKey.currentState?.canPop() == true) {
          // Use maybePop to respect inner PopScope handlers (e.g., unsaved changes dialog)
          _navigatorKey.currentState?.maybePop();
        }
      },
      child: Navigator(
        key: _navigatorKey,
        onGenerateRoute: (_) => MaterialPageRoute(
          builder: (_) => const HomeScreen(),
        ),
      ),
    );
  }
}
