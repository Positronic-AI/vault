import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';

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
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App went to background or screen locked
      if (_isAuthenticated) {
        setState(() {
          _requiresAuth = true;
        });
      }
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
    return const HomeScreen();
  }
}
