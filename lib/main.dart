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

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  bool _hasPassword = false;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final hasPassword = await _authService.hasPassword();
    setState(() {
      _hasPassword = hasPassword;
      _isLoading = false;
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

    return AuthScreen(
      isFirstTime: !_hasPassword,
      onAuthenticated: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      },
    );
  }
}
