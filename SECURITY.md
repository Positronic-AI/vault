# Security

## App Integrity Verification

Vault allows you to independently verify that the app you downloaded has not been tampered with. This ensures the app you're running is the authentic version from this repository.

### How to Verify

1. **Open the App** and navigate to the "About" screen (rightmost tab)
2. **Find the Certificate Fingerprint** - It's displayed under "App Verification"
3. **Copy the fingerprint** using the copy button
4. **Compare it** with the official fingerprint published below

If the fingerprints match, you can be confident the app is authentic and hasn't been modified.

### Official Release Certificate Fingerprints

#### Current Release (Debug - Development Only)
```
SHA-256: 4B:28:CF:1D:05:7D:4F:E8:02:E3:49:1C:97:C2:19:B9:FA:3E:DC:D2:1D:48:98:A8:A8:81:AC:9F:8F:88:BB:62
```

**Note:** This is the debug signing certificate. Production releases will use a separate release certificate that will be published here before the first release.

## Security Features

- **AES-256-CBC Encryption** - All photos and videos are encrypted at rest
- **Hardware-backed Keys** - Encryption keys stored in Android KeyStore
- **Biometric Authentication** - Fingerprint/face authentication required
- **No Cloud Sync** - Everything stays on your device
- **Root Detection** - Warns if device is rooted/jailbroken
- **Developer Mode Detection** - Warns if USB debugging is enabled
- **Open Source** - All code is available for audit

## Security Limitations

### What We CAN Protect Against:
- ✓ Casual snooping (stolen/lost phone)
- ✓ Data recovery from device storage
- ✓ Unauthorized app access
- ✓ Accidental cloud backups

### What We CANNOT Protect Against:
- ✗ Compromised OS or firmware
- ✗ Keyloggers at system level
- ✗ Screen recording malware
- ✗ Physical coercion for passwords
- ✗ Nation-state level attacks

## Reporting Security Issues

If you discover a security vulnerability, please report it by:
1. **DO NOT** open a public issue
2. Email details to: help@lit.ai
3. Include steps to reproduce and impact assessment

We take security seriously and will respond to valid reports promptly.

## Threat Model

Vault is designed to protect against:
- **Opportunistic attackers** who find/steal your phone
- **Data recovery attempts** from lost/sold devices
- **Unauthorized physical access** to your device
- **Malicious apps** trying to access your media

Vault is NOT designed to protect against:
- **Targeted attacks** by sophisticated adversaries
- **Compromised devices** with root-level malware
- **State-level actors** with advanced capabilities

If you need protection against advanced threats, consider additional security measures beyond this app.
