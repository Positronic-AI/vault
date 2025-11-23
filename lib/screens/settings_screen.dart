import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/security_service.dart';
import '../services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SecurityService _securityService = SecurityService();
  final StorageService _storageService = StorageService();

  SecurityStatus? _securityStatus;
  int _mediaCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    await _storageService.initialize();

    final status = await _securityService.getSecurityStatus();
    final count = await _storageService.getMediaCount();

    setState(() {
      _securityStatus = status;
      _mediaCount = count;
      _isLoading = false;
    });
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Security Status Section
                _buildSectionHeader('Security Status'),

                if (_securityStatus != null) ...[
                  _buildStatusTile(
                    'Device Security',
                    _securityStatus!.isRooted ? 'Root/Jailbreak detected' : 'Not rooted',
                    _securityStatus!.isRooted,
                    Icons.security,
                  ),
                  _buildStatusTile(
                    'Developer Options',
                    _securityStatus!.isDeveloperMode ? 'Enabled' : 'Disabled',
                    _securityStatus!.isDeveloperMode,
                    Icons.developer_mode,
                  ),
                ],

                const Divider(),

                // Verification Section
                _buildSectionHeader('App Verification'),

                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('App Version'),
                  subtitle: Text(_securityStatus?.appVersion ?? 'Unknown'),
                ),

                if (_securityStatus?.certificateFingerprint != null)
                  ListTile(
                    leading: const Icon(Icons.fingerprint),
                    title: const Text('Certificate Fingerprint (SHA-256)'),
                    subtitle: Text(
                      _securityStatus!.certificateFingerprint!,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () => _copyToClipboard(
                        _securityStatus!.certificateFingerprint!,
                      ),
                    ),
                    isThreeLine: true,
                  ),

                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Verify this fingerprint matches the one published on our official GitHub repository to ensure app authenticity.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),

                const Divider(),

                // Storage Info
                _buildSectionHeader('Storage'),

                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Media Items'),
                  subtitle: Text('$_mediaCount items stored (encrypted)'),
                ),

                const Divider(),

                // About Section
                _buildSectionHeader('About Vault'),

                const ListTile(
                  leading: Icon(Icons.lock_open),
                  title: Text('Open Source'),
                  subtitle: Text('Fully open source and auditable'),
                ),

                const ListTile(
                  leading: Icon(Icons.verified_user),
                  title: Text('End-to-End Encryption'),
                  subtitle: Text('All media encrypted at rest with AES-256'),
                ),

                const ListTile(
                  leading: Icon(Icons.privacy_tip),
                  title: Text('No Cloud Sync'),
                  subtitle: Text('Everything stays on your device'),
                ),

                const Divider(),

                // Limitations Section
                _buildSectionHeader('Security Limitations'),

                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What we CAN protect against:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text('✓ Casual snooping (stolen/lost phone)'),
                      Text('✓ Data recovery from device storage'),
                      Text('✓ Unauthorized app access'),
                      Text('✓ Accidental cloud backups'),
                      SizedBox(height: 16),
                      Text(
                        'What we CANNOT protect against:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text('✗ Compromised OS or firmware'),
                      Text('✗ Keyloggers at system level'),
                      Text('✗ Screen recording malware'),
                      Text('✗ Physical coercion for passwords'),
                      Text('✗ Nation-state level attacks'),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildStatusTile(String title, String status, bool isWarning, IconData icon) {
    return ListTile(
      leading: Icon(
        icon,
        color: isWarning ? Colors.orange : Colors.green,
      ),
      title: Text(title),
      subtitle: Text(status),
      trailing: Icon(
        isWarning ? Icons.warning : Icons.check_circle,
        color: isWarning ? Colors.orange : Colors.green,
      ),
    );
  }
}
