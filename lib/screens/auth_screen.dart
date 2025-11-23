import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  final bool isFirstTime;
  final VoidCallback onAuthenticated;

  const AuthScreen({
    super.key,
    required this.isFirstTime,
    required this.onAuthenticated,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isBiometricAvailable = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _checkBiometric();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _version = 'v${packageInfo.version} (${packageInfo.buildNumber})';
    });
  }

  Future<void> _checkBiometric() async {
    final isAvailable = await _authService.isBiometricAvailable();
    setState(() {
      _isBiometricAvailable = isAvailable;
    });

    // If biometric is available and not first time, try biometric auth automatically
    // Don't show error if auto-attempt fails (user might have just canceled)
    if (isAvailable && !widget.isFirstTime) {
      _authenticateWithBiometric(showError: false);
    }
  }

  Future<void> _authenticateWithBiometric({bool showError = true}) async {
    try {
      // Check what biometrics are available
      final availableBiometrics = await _authService.getAvailableBiometrics();

      if (availableBiometrics.isEmpty && showError) {
        setState(() {
          _errorMessage = 'No biometrics enrolled. Please set up fingerprint or face unlock in your device settings.';
        });
        return;
      }

      final success = await _authService.authenticateWithBiometrics();
      if (success && mounted) {
        widget.onAuthenticated();
      } else if (!success && mounted && showError) {
        setState(() {
          _errorMessage = 'Authentication canceled or failed. Available: ${availableBiometrics.join(", ")}';
        });
      }
    } catch (e) {
      if (mounted && showError) {
        setState(() {
          _errorMessage = 'Biometric error: $e';
        });
      }
    }
  }

  Future<void> _handleSubmit() async {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    final password = _passwordController.text;

    if (password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a password';
        _isLoading = false;
      });
      return;
    }

    if (widget.isFirstTime) {
      // First time setup
      final confirm = _confirmPasswordController.text;

      if (password.length < 6) {
        setState(() {
          _errorMessage = 'Password must be at least 6 characters';
          _isLoading = false;
        });
        return;
      }

      if (password != confirm) {
        setState(() {
          _errorMessage = 'Passwords do not match';
          _isLoading = false;
        });
        return;
      }

      await _authService.setPassword(password);
      widget.onAuthenticated();
    } else {
      // Login
      final isValid = await _authService.verifyPassword(password);

      if (isValid) {
        widget.onAuthenticated();
      } else {
        setState(() {
          _errorMessage = 'Incorrect password';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo/Icon
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/icon.png',
                    width: 120,
                    height: 120,
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  widget.isFirstTime ? 'Create Password' : 'Vault',
                  style: Theme.of(context).textTheme.headlineLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  widget.isFirstTime
                      ? 'Set a strong password to protect your media'
                      : 'Enter your password to unlock',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Password field
                AutofillGroup(
                  onDisposeAction: AutofillContextAction.commit,
                  child: Column(
                    children: [
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        keyboardType: TextInputType.visiblePassword,
                        autofillHints: widget.isFirstTime
                            ? [AutofillHints.newPassword]
                            : [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.key),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        onSubmitted: (_) =>
                            widget.isFirstTime ? null : _handleSubmit(),
                      ),

                      // Confirm password field (only for first time)
                      if (widget.isFirstTime) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirm,
                          keyboardType: TextInputType.visiblePassword,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.key),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureConfirm = !_obscureConfirm;
                                });
                              },
                            ),
                          ),
                          onSubmitted: (_) => _handleSubmit(),
                        ),
                      ],
                    ],
                  ),
                ),

                // Error message
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 24),

                // Submit button
                FilledButton(
                  onPressed: _isLoading ? null : _handleSubmit,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.isFirstTime ? 'Create Vault' : 'Unlock',
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                ),

                // Biometric button (only for login)
                if (!widget.isFirstTime && _isBiometricAvailable) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _authenticateWithBiometric,
                    icon: const Icon(Icons.fingerprint),
                    label: const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('Use Biometric'),
                    ),
                  ),
                ],

                // Version number
                const SizedBox(height: 32),
                if (_version.isNotEmpty)
                  Text(
                    _version,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[400],
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
