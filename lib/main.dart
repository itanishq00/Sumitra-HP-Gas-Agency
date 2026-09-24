import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'firebase_options.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    runApp(const GasSevaApp());
  } catch (e) {
    runApp(FirebaseErrorApp(error: e.toString()));
  }
}

// ============================================================
// APP
// ============================================================

class GasSevaApp extends StatelessWidget {
  const GasSevaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'Sumitra HP Gas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.red,
        scaffoldBackgroundColor: const Color(0xFFFFD6D6),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: Colors.red,
              width: 2,
            ),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// ============================================================
// FIREBASE ERROR APP
// ============================================================

class FirebaseErrorApp extends StatelessWidget {
  final String error;

  const FirebaseErrorApp({
    super.key,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 70,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Firebase Error',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  error,
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

// ============================================================
// AUTH GATE
// ============================================================

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final user = snapshot.data;

        if (user != null) {
          return PinGate(user: user);
        }

        return const LoginScreen();
      },
    );
  }
}


// ============================================================
// DEVICE PIN SECURITY
// The PIN is stored in the device's secure storage, not Firestore.
// The storage key includes the Firebase UID, so different accounts
// on the same device can have different PINs.
// ============================================================

class PinStorage {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String _pinKey(String uid) => 'sumitra_hp_gas_pin_$uid';
  static String _resetKey(String uid) =>
      'sumitra_hp_gas_pin_reset_$uid';
  static String _biometricKey(String uid) =>
      'sumitra_hp_gas_biometric_$uid';

  static Future<String?> readPin(String uid) {
    return _storage.read(key: _pinKey(uid));
  }

  static Future<void> savePin(String uid, String pin) {
    return _storage.write(
      key: _pinKey(uid),
      value: pin,
    );
  }

  static Future<void> requestPinReset(String uid) {
    return _storage.write(
      key: _resetKey(uid),
      value: 'true',
    );
  }

  static Future<bool> biometricEnabled(String uid) async {
    final value = await _storage.read(key: _biometricKey(uid));
    return value == 'true';
  }

  static Future<void> setBiometricEnabled(
    String uid,
    bool enabled,
  ) {
    return _storage.write(
      key: _biometricKey(uid),
      value: enabled ? 'true' : 'false',
    );
  }

  static Future<bool> consumePinResetRequest(String uid) async {
    final requested = await _storage.read(
      key: _resetKey(uid),
    );

    if (requested == 'true') {
      await _storage.delete(key: _resetKey(uid));
      return true;
    }

    return false;
  }
}

class PinGate extends StatefulWidget {
  final User user;

  const PinGate({
    super.key,
    required this.user,
  });

  @override
  State<PinGate> createState() => _PinGateState();
}

class _PinGateState extends State<PinGate> {
  bool loading = true;
  bool needsSetup = false;
  String? pin;

  @override
  void initState() {
    super.initState();
    _loadSecurityState();
  }

  Future<void> _loadSecurityState() async {
    try {
      final resetRequested =
          await PinStorage.consumePinResetRequest(widget.user.uid);

      if (resetRequested) {
        if (!mounted) return;

        setState(() {
          loading = false;
          needsSetup = true;
          pin = null;
        });
        return;
      }

      final savedPin =
          await PinStorage.readPin(widget.user.uid);

      if (!mounted) return;

      setState(() {
        loading = false;
        pin = savedPin;
        needsSetup = savedPin == null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      showMessage(
        'Security storage open nahi ho pa raha: $e',
      );
    }
  }

  Future<void> _pinCreated(String newPin) async {
    await PinStorage.savePin(
      widget.user.uid,
      newPin,
    );

    // Enable biometric unlock by default when the device supports it.
    try {
      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      final available = supported &&
          (await auth.getAvailableBiometrics()).isNotEmpty;
      await PinStorage.setBiometricEnabled(
        widget.user.uid,
        available,
      );
    } catch (_) {
      await PinStorage.setBiometricEnabled(
        widget.user.uid,
        false,
      );
    }

    if (!mounted) return;

    setState(() {
      pin = newPin;
      needsSetup = false;
    });
  }

  Future<void> _forgotPin() async {
    try {
      await PinStorage.requestPinReset(widget.user.uid);
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (mounted) {
        showMessage(
          'PIN reset start nahi ho paaya: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (needsSetup) {
      return SetPinScreen(
        email: widget.user.email ?? '',
        onPinCreated: _pinCreated,
      );
    }

    return PinUnlockScreen(
      email: widget.user.email ?? '',
      savedPin: pin!,
      onForgotPin: _forgotPin,
    );
  }
}

class SetPinScreen extends StatefulWidget {
  final String email;
  final Future<void> Function(String pin) onPinCreated;

  const SetPinScreen({
    super.key,
    required this.email,
    required this.onPinCreated,
  });

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  final pinController = TextEditingController();
  final confirmController = TextEditingController();

  bool saving = false;
  bool obscurePin = true;
  bool obscureConfirm = true;

  @override
  void dispose() {
    pinController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final pin = pinController.text.trim();
    final confirm = confirmController.text.trim();

    if (pin.length != 4 || !RegExp(r'^\d{4}$').hasMatch(pin)) {
      showMessage('Security PIN exactly 4 digits ka hona chahiye.');
      return;
    }

    if (pin != confirm) {
      showMessage('Dono PIN same hone chahiye.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      saving = true;
    });

    try {
      await widget.onPinCreated(pin);
    } catch (e) {
      if (mounted) {
        showMessage('PIN save nahi ho paaya: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      color: Colors.red,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Set Security PIN',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Is device par app unlock karne ke liye 4-digit PIN set karo.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  if (widget.email.isNotEmpty)
                    Text(
                      widget.email,
                      style: const TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: pinController,
                    enabled: !saving,
                    obscureText: obscurePin,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      labelText: '4-Digit PIN',
                      counterText: '',
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            obscurePin = !obscurePin;
                          });
                        },
                        icon: Icon(
                          obscurePin
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: confirmController,
                    enabled: !saving,
                    obscureText: obscureConfirm,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Confirm PIN',
                      counterText: '',
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            obscureConfirm = !obscureConfirm;
                          });
                        },
                        icon: Icon(
                          obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: saving ? null : save,
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.lock),
                      label: Text(
                        saving ? 'Saving...' : 'Save Security PIN',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PinUnlockScreen extends StatefulWidget {
  final String email;
  final String savedPin;
  final Future<void> Function() onForgotPin;

  const PinUnlockScreen({
    super.key,
    required this.email,
    required this.savedPin,
    required this.onForgotPin,
  });

  @override
  State<PinUnlockScreen> createState() => _PinUnlockScreenState();
}

class _PinUnlockScreenState extends State<PinUnlockScreen> {
  final pinController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool unlocking = false;
  bool obscurePin = true;
  bool biometricAvailable = false;
  bool biometricRunning = false;
  int failedAttempts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareBiometricUnlock();
    });
  }

  @override
  void dispose() {
    pinController.dispose();
    super.dispose();
  }

  Future<void> _prepareBiometricUnlock() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !mounted) return;

    try {
      final enabled = await PinStorage.biometricEnabled(uid);
      if (!enabled) return;

      final supported = await _localAuth.isDeviceSupported();
      final available = supported &&
          (await _localAuth.getAvailableBiometrics()).isNotEmpty;

      if (!mounted) return;
      setState(() {
        biometricAvailable = available;
      });

      if (available) {
        await _unlockWithBiometric(showError: false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        biometricAvailable = false;
      });
    }
  }

  Future<void> _unlockWithBiometric({bool showError = true}) async {
    if (biometricRunning || unlocking) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      biometricRunning = true;
    });

    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Sumitra HP Gas unlock karne ke liye Face ID ya Fingerprint use karein.',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      if (!mounted) return;

      if (authenticated) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const MainScreen(),
          ),
        );
        return;
      }
    } on LocalAuthException catch (e) {
      if (showError && mounted) {
        showMessage('Biometric unlock available nahi hai: ${e.code.name}');
      }
    } catch (e) {
      if (showError && mounted) {
        showMessage('Biometric unlock failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          biometricRunning = false;
        });
      }
    }
  }

  Future<void> unlock() async {
    final entered = pinController.text.trim();

    if (entered.length != 4) {
      showMessage('4-digit Security PIN enter karo.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      unlocking = true;
    });

    await Future<void>.delayed(
      const Duration(milliseconds: 150),
    );

    if (!mounted) return;

    if (entered == widget.savedPin) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const MainScreen(),
        ),
      );
      return;
    }

    setState(() {
      unlocking = false;
      failedAttempts++;
      pinController.clear();
    });

    if (failedAttempts >= 5) {
      showMessage(
        'PIN 5 baar galat hua. Gmail/password se dobara login karke PIN reset karo.',
      );

      await PinStorage.requestPinReset(
        FirebaseAuth.instance.currentUser?.uid ?? '',
      );

      await FirebaseAuth.instance.signOut();
      return;
    }

    showMessage(
      'Security PIN galat hai. ${5 - failedAttempts} attempts remaining.',
    );
  }

  Future<void> forgotPin() async {
    FocusManager.instance.primaryFocus?.unfocus();

    await widget.onForgotPin();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock,
                      color: Colors.red,
                      size: 46,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Enter Security PIN',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (widget.email.isNotEmpty)
                    Text(
                      widget.email,
                      style: const TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: pinController,
                    enabled: !unlocking,
                    obscureText: obscurePin,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      letterSpacing: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Security PIN',
                      counterText: '',
                      suffixIcon: IconButton(
                        onPressed: unlocking
                            ? null
                            : () {
                                setState(() {
                                  obscurePin = !obscurePin;
                                });
                              },
                        icon: Icon(
                          obscurePin
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => unlock(),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: unlocking ? null : unlock,
                      icon: unlocking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.lock_open),
                      label: Text(
                        unlocking ? 'Checking...' : 'Unlock',
                      ),
                    ),
                  ),
                  if (biometricAvailable) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: (unlocking || biometricRunning)
                            ? null
                            : () => _unlockWithBiometric(),
                        icon: biometricRunning
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.fingerprint),
                        label: Text(
                          biometricRunning
                              ? 'Authenticating...'
                              : 'Use Face ID / Fingerprint',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: (unlocking || biometricRunning) ? null : forgotPin,
                    child: const Text('Forgot PIN?'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SecurityProfileScreen extends StatefulWidget {
  const SecurityProfileScreen({super.key});

  @override
  State<SecurityProfileScreen> createState() => _SecurityProfileScreenState();
}

class _SecurityProfileScreenState extends State<SecurityProfileScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _securityLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final supported = await _localAuth.isDeviceSupported();
      final available = supported &&
          (await _localAuth.getAvailableBiometrics()).isNotEmpty;
      final enabled = await PinStorage.biometricEnabled(user.uid);
      if (!mounted) return;
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled && available;
        _securityLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _biometricAvailable = false;
        _biometricEnabled = false;
        _securityLoading = false;
      });
    }
  }

  Future<void> _setBiometric(bool enabled) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (enabled) {
      try {
        final authenticated = await _localAuth.authenticate(
          localizedReason: 'Biometric unlock enable karne ke liye authenticate karein.',
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        );
        if (!authenticated) return;
      } on LocalAuthException catch (e) {
        if (mounted) showMessage('Biometric setup failed: ${e.code.name}');
        return;
      } catch (e) {
        if (mounted) showMessage('Biometric setup failed: $e');
        return;
      }
    }

    await PinStorage.setBiometricEnabled(user.uid, enabled);
    if (!mounted) return;
    setState(() {
      _biometricEnabled = enabled;
    });
  }

  Future<void> _forgotPin(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset Security PIN?'),
          content: const Text(
            'Aap logout ho jaoge. Next login par Gmail/password verify karke naya 4-digit PIN set kar sakoge.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reset PIN'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await PinStorage.requestPinReset(user.uid);
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _changePin(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();

    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool saving = false;

    try {
      await showDialog(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogBuilderContext, setDialogState) {
              Future<void> save() async {
                final current = currentController.text.trim();
                final newPin = newController.text.trim();
                final confirm = confirmController.text.trim();

                final savedPin =
                    await PinStorage.readPin(user.uid);

                if (savedPin == null) {
                  showMessage('Current PIN available nahi hai.');
                  return;
                }

                if (current != savedPin) {
                  showMessage('Current PIN galat hai.');
                  return;
                }

                if (!RegExp(r'^\d{4}$').hasMatch(newPin)) {
                  showMessage('New PIN exactly 4 digits ka hona chahiye.');
                  return;
                }

                if (newPin != confirm) {
                  showMessage('New PIN aur confirm PIN same hone chahiye.');
                  return;
                }

                FocusScope.of(dialogBuilderContext).unfocus();

                setDialogState(() {
                  saving = true;
                });

                try {
                  await PinStorage.savePin(
                    user.uid,
                    newPin,
                  );

                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }

                  if (context.mounted) {
                    showMessage('Security PIN successfully changed.');
                  }
                } catch (e) {
                  setDialogState(() {
                    saving = false;
                  });

                  showMessage('PIN change failed: $e');
                }
              }

              Widget pinField({
                required String label,
                required TextEditingController controller,
                required bool obscure,
                required VoidCallback toggle,
              }) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: controller,
                    enabled: !saving,
                    obscureText: obscure,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      labelText: label,
                      counterText: '',
                      suffixIcon: IconButton(
                        onPressed: saving ? null : toggle,
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                );
              }

              return AlertDialog(
                title: const Text('Change Security PIN'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      pinField(
                        label: 'Current PIN',
                        controller: currentController,
                        obscure: obscureCurrent,
                        toggle: () {
                          setDialogState(() {
                            obscureCurrent = !obscureCurrent;
                          });
                        },
                      ),
                      pinField(
                        label: 'New 4-Digit PIN',
                        controller: newController,
                        obscure: obscureNew,
                        toggle: () {
                          setDialogState(() {
                            obscureNew = !obscureNew;
                          });
                        },
                      ),
                      pinField(
                        label: 'Confirm New PIN',
                        controller: confirmController,
                        obscure: obscureConfirm,
                        toggle: () {
                          setDialogState(() {
                            obscureConfirm = !obscureConfirm;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: saving
                        ? null
                        : () {
                            FocusScope.of(dialogBuilderContext).unfocus();
                            Navigator.pop(dialogContext);
                          },
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      currentController.dispose();
      newController.dispose();
      confirmController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Profile & Security',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.person),
              ),
              title: Text(
                user?.email ?? 'User',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text('Signed in account'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(
                    Icons.security,
                    color: Colors.red,
                  ),
                  title: Text(
                    'Device Security',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Your 4-digit PIN is stored securely on this device.',
                  ),
                ),
                const Divider(height: 1),
                if (_securityLoading)
                  const ListTile(
                    leading: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    title: Text('Checking biometric support...'),
                  )
                else if (_biometricAvailable)
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint, color: Colors.red),
                    title: const Text('Biometric Unlock'),
                    subtitle: const Text('Face ID / Fingerprint se PIN ke bina unlock karo.'),
                    value: _biometricEnabled,
                    onChanged: _setBiometric,
                  )
                else
                  const ListTile(
                    leading: Icon(Icons.fingerprint, color: Colors.grey),
                    title: Text('Biometric Unlock'),
                    subtitle: Text('Is device par Face ID / Fingerprint available nahi hai.'),
                  ),
                ListTile(
                  leading: const Icon(Icons.password),
                  title: const Text('Change Security PIN'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _changePin(context),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.lock_reset,
                    color: Colors.red,
                  ),
                  title: const Text('Forgot / Reset PIN'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _forgotPin(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.red),
              title: const Text('Inventory Activity History'),
              subtitle: const Text('Kis staff ne kab aur kya stock change kiya.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const InventoryActivityScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: Colors.red.shade50,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.red,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'PIN device-specific hai. Same Gmail account kisi doosre phone par login karega to us device par alag PIN set kiya ja sakta hai.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// LOGIN
// ============================================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;
  bool obscurePassword = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      showMessage(
        'Email aur password dono enter karo.',
      );
      return;
    }

    // Close the keyboard before we start an async operation and
    // potentially rebuild/replace this screen (AuthGate swap).
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      loading = true;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      String message = 'Login failed.';

      if (e.code == 'invalid-credential') {
        message = 'Email ya password galat hai.';
      } else if (e.code == 'user-not-found') {
        message = 'Ye email registered nahi hai.';
      } else if (e.code == 'wrong-password') {
        message = 'Password galat hai.';
      } else if (e.code == 'invalid-email') {
        message = 'Email format galat hai.';
      } else if (e.code == 'user-disabled') {
        message = 'Ye account disabled hai.';
      }

      if (mounted) {
        showMessage( message);
      }
    } catch (e) {
      if (mounted) {
        showMessage(
          'Login error: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 430,
              ),
              child: Column(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.local_gas_station,
                      color: Colors.red,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Sumitra HP Gas',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Gas Agency Management System',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    onSubmitted: (_) => login(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: loading ? null : login,
                      child: loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Login',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BLUE + RED SECTION BACKGROUND
// Existing colored cards/priority sections remain unchanged.
// ============================================================

class BlueRedSectionBackground extends StatelessWidget {
  final Widget child;

  const BlueRedSectionBackground({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFEAEA),
            Color(0xFFFFD6D6),
            Color(0xFFFFBDBD),
          ],
        ),
      ),
      child: child,
    );
  }
}

// ============================================================
// INVENTORY ACTIVITY / AUDIT LOG
// Every manual inventory change is recorded with the signed-in
// Firebase account and matching staff profile (when available).
// ============================================================

Future<Map<String, dynamic>> _currentActorInfo() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return {
      'changedByUid': 'system',
      'changedByName': 'System',
      'changedByEmail': '',
    };
  }

  String name = user.email?.split('@').first ?? 'Staff';
  try {
    final staffQuery = await FirebaseFirestore.instance
        .collection('staff')
        .where('email', isEqualTo: user.email)
        .limit(1)
        .get();
    if (staffQuery.docs.isNotEmpty) {
      final staffData = staffQuery.docs.first.data();
      final staffName = (staffData['name'] ?? '').toString().trim();
      if (staffName.isNotEmpty) name = staffName;
    }
  } catch (_) {
    // Email is still enough to identify the signed-in account.
  }

  return {
    'changedByUid': user.uid,
    'changedByName': name,
    'changedByEmail': user.email ?? '',
  };
}

Future<void> logInventoryActivity({
  required String action,
  required String section,
  required String item,
  required Map<String, dynamic> changes,
  String source = 'manual',
  Map<String, dynamic>? actorOverride,
}) async {
  try {
    final actor = actorOverride ?? await _currentActorInfo();
    await FirebaseFirestore.instance.collection('inventoryActivity').add({
      'action': action,
      'section': section,
      'item': item,
      'changes': changes,
      ...actor,
      'source': source,
      'changedAt': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    debugPrint('Inventory activity log failed: $e');
  }
}

class InventoryActivityScreen extends StatelessWidget {
  final String? filterItem;

  const InventoryActivityScreen({super.key, this.filterItem});

  String _time(dynamic value) {
    if (value is Timestamp) return formatDateTime(value.toDate());
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('inventoryActivity')
        .orderBy('changedAt', descending: true)
        .limit(100)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          filterItem == null ? 'Inventory Activity' : '$filterItem Activity',
        ),
      ),
      body: BlueRedSectionBackground(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Activity load nahi ho pa rahi.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = (snapshot.data?.docs ?? []).where((doc) {
              if (filterItem == null) return true;
              return (doc.data()['item'] ?? '') == filterItem;
            }).toList();

            if (docs.isEmpty) {
              return const Center(
                child: Text('Abhi koi activity nahi hai.'),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data();
                final changes = Map<String, dynamic>.from(
                  data['changes'] is Map ? data['changes'] as Map : {},
                );
                final email = (data['changedByEmail'] ?? '').toString();
                final item = (data['item'] ?? 'Inventory').toString();
                final time = _time(data['changedAt']);

                final changeText = changes.entries.map((entry) {
                  return '${entry.key}: ${entry.value}';
                }).join('\n');

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _ActivityDetailRow(
                          label: 'Updated by',
                          value: email.isEmpty ? 'Unknown' : email,
                        ),
                        _ActivityDetailRow(
                          label: 'Date & Time',
                          value: time,
                        ),
                        _ActivityDetailRow(
                          label: 'Change',
                          value: changeText.isEmpty ? 'Stock updated' : changeText,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ActivityDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _ActivityDetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// UPCOMING STOCK RECEIPT CONFIRMATION
// On/after the scheduled arrival date, the first app open of that
// day asks what was actually received. Only the confirmed quantities
// are moved into current inventory. Partial receipt is supported.
// ============================================================

Future<void> checkAndPromptForUpcomingStockReceipt(
  BuildContext context,
) async {
  final firestore = FirebaseFirestore.instance;
  final ref = firestore.collection('inventory').doc('upcomingStock');

  try {
    final snapshot = await ref.get();
    if (!snapshot.exists || !context.mounted) return;

    final data = snapshot.data();
    if (data == null) return;

    final arrivalTimestamp = data['arrivalDate'] as Timestamp?;
    if (arrivalTimestamp == null) return;

    final arrivalDate = arrivalTimestamp.toDate();
    final now = DateTime.now();
    final arrivalDay = DateTime(
      arrivalDate.year,
      arrivalDate.month,
      arrivalDate.day,
    );
    final today = DateTime(now.year, now.month, now.day);

    // Do nothing until the scheduled date arrives.
    if (arrivalDay.isAfter(today)) return;

    // Show the prompt only once per calendar day. If the stock has not
    // arrived, it can be asked again on the next day.
    final promptedTimestamp = data['receiptPromptedOn'] as Timestamp?;
    if (promptedTimestamp != null) {
      final promptedDay = promptedTimestamp.toDate();
      final promptedDate = DateTime(
        promptedDay.year,
        promptedDay.month,
        promptedDay.day,
      );
      if (promptedDate == today) return;
    }

    await showUpcomingStockReceiptDialog(
      context,
      upcomingData: data,
      upcomingRef: ref,
      arrivalDay: arrivalDay,
    );
  } catch (e) {
    debugPrint('Upcoming stock receipt check failed: $e');
  }
}

Future<void> showUpcomingStockReceiptDialog(
  BuildContext parentContext, {
  required Map<String, dynamic> upcomingData,
  required DocumentReference<Map<String, dynamic>> upcomingRef,
  required DateTime arrivalDay,
}) async {
  const itemLabels = <String, String>{
    'cylinder14': '14kg Cylinder',
    'cylinder19': '19kg Cylinder',
    'cylinder5': '5kg Cylinder',
    'apron': 'Apron',
    'stove': 'Stove',
    'lighter': 'Lighter',
  };

  int ordered(String key) => intValue(number(upcomingData[key]));

  final orderedQuantities = <String, int>{
    for (final key in itemLabels.keys) key: ordered(key),
  };

  final receivedControllers = <String, TextEditingController>{
    for (final key in itemLabels.keys)
      key: TextEditingController(
        text: orderedQuantities[key]!.toString(),
      ),
  };

  final selected = <String, bool>{
    for (final key in itemLabels.keys) key: orderedQuantities[key]! > 0,
  };

  bool receivedConfirmed = false;
  bool saving = false;

  try {
    await showDialog(
      context: parentContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogBuilderContext, setDialogState) {
            Future<void> markNotReceived() async {
              if (saving) return;

              setDialogState(() {
                saving = true;
              });

              try {
                await upcomingRef.set({
                  'receiptPromptedOn': Timestamp.fromDate(
                    DateTime.now(),
                  ),
                  'lastReceiptCheck': 'not_received',
                  'lastReceiptCheckedAt': FieldValue.serverTimestamp(),
                  'lastReceiptCheckedBy':
                      FirebaseAuth.instance.currentUser?.email ?? '',
                }, SetOptions(merge: true));

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              } catch (e) {
                setDialogState(() {
                  saving = false;
                });
                if (dialogContext.mounted) {
                  showMessage('Save failed: $e');
                }
              }
            }

            Future<void> confirmReceived() async {
              if (saving) return;

              final received = <String, int>{};

              for (final key in itemLabels.keys) {
                if (!selected[key]!) {
                  received[key] = 0;
                  continue;
                }

                final value = intValue(
                  receivedControllers[key]!.text,
                );

                if (value < 0 || value > orderedQuantities[key]!) {
                  showMessage(
                    '${itemLabels[key]} received quantity ordered quantity se zyada nahi ho sakti.',
                  );
                  return;
                }

                received[key] = value;
              }

              final totalReceived = received.values.fold<int>(
                0,
                (sum, value) => sum + value,
              );

              if (totalReceived <= 0) {
                showMessage('Kam se kam ek received quantity select karo.');
                return;
              }

              FocusScope.of(dialogBuilderContext).unfocus();

              setDialogState(() {
                saving = true;
              });

              try {
                await FirebaseFirestore.instance.runTransaction(
                  (transaction) async {
                    final latestUpcoming =
                        await transaction.get(upcomingRef);

                    if (!latestUpcoming.exists) {
                      throw Exception(
                        'Upcoming stock record already processed.',
                      );
                    }

                    final latestData =
                        latestUpcoming.data() ?? <String, dynamic>{};

                    int latestValue(String key) =>
                        intValue(number(latestData[key]));

                    final remaining = <String, int>{};
                    for (final key in itemLabels.keys) {
                      remaining[key] =
                          (latestValue(key) - received[key]!).clamp(0, 999999999).toInt();
                    }

                    final cylinderRef = firestoreRef('cylinder');
                    final apronRef = firestoreRef('apron');
                    final stoveRef = firestoreRef('stove');
                    final lighterRef = firestoreRef('lighter');

                    final cylinderSnapshot =
                        await transaction.get(cylinderRef);
                    final apronSnapshot = await transaction.get(apronRef);
                    final stoveSnapshot = await transaction.get(stoveRef);
                    final lighterSnapshot = await transaction.get(lighterRef);

                    final cylinderData =
                        cylinderSnapshot.data() ?? <String, dynamic>{};
                    final apronData =
                        apronSnapshot.data() ?? <String, dynamic>{};
                    final stoveData =
                        stoveSnapshot.data() ?? <String, dynamic>{};
                    final lighterData =
                        lighterSnapshot.data() ?? <String, dynamic>{};

                    int current(dynamic raw) => intValue(number(raw));

                    transaction.set(
                      cylinderRef,
                      {
                        'stockLeft14':
                            current(cylinderData['stockLeft14']) +
                                received['cylinder14']!,
                        'stockLeft19':
                            current(cylinderData['stockLeft19']) +
                                received['cylinder19']!,
                        'stockLeft5':
                            current(cylinderData['stockLeft5']) +
                                received['cylinder5']!,
                        'empty14':
                            current(cylinderData['empty14']) +
                                received['cylinder14']!,
                        'empty19':
                            current(cylinderData['empty19']) +
                                received['cylinder19']!,
                        'empty5':
                            current(cylinderData['empty5']) +
                                received['cylinder5']!,
                        'updatedAt': FieldValue.serverTimestamp(),
                      },
                      SetOptions(merge: true),
                    );

                    transaction.set(
                      apronRef,
                      {
                        'stockLeft':
                            current(apronData['stockLeft']) +
                                received['apron']!,
                        'updatedAt': FieldValue.serverTimestamp(),
                      },
                      SetOptions(merge: true),
                    );

                    transaction.set(
                      stoveRef,
                      {
                        'stockLeft':
                            current(stoveData['stockLeft']) +
                                received['stove']!,
                        'updatedAt': FieldValue.serverTimestamp(),
                      },
                      SetOptions(merge: true),
                    );

                    transaction.set(
                      lighterRef,
                      {
                        'stockLeft':
                            current(lighterData['stockLeft']) +
                                received['lighter']!,
                        'updatedAt': FieldValue.serverTimestamp(),
                      },
                      SetOptions(merge: true),
                    );

                    final historyRef =
                        FirebaseFirestore.instance.collection('stockArrivals').doc();

                    transaction.set(historyRef, {
                      'date': Timestamp.fromDate(arrivalDay),
                      'cylinder14': received['cylinder14'],
                      'cylinder19': received['cylinder19'],
                      'cylinder5': received['cylinder5'],
                      'apron': received['apron'],
                      'stove': received['stove'],
                      'lighter': received['lighter'],
                      'orderedCylinder14': orderedQuantities['cylinder14'],
                      'orderedCylinder19': orderedQuantities['cylinder19'],
                      'orderedCylinder5': orderedQuantities['cylinder5'],
                      'orderedApron': orderedQuantities['apron'],
                      'orderedStove': orderedQuantities['stove'],
                      'orderedLighter': orderedQuantities['lighter'],
                      'createdAt': FieldValue.serverTimestamp(),
                      'source': 'upcomingStock',
                      'automatic': false,
                      'receivedBy':
                          FirebaseAuth.instance.currentUser?.email ?? '',
                      'receiptConfirmed': true,
                    });

                    final allReceived = remaining.values.every(
                      (value) => value == 0,
                    );

                    if (allReceived) {
                      transaction.delete(upcomingRef);
                    } else {
                      transaction.set(
                        upcomingRef,
                        {
                          'cylinder14': remaining['cylinder14'],
                          'cylinder19': remaining['cylinder19'],
                          'cylinder5': remaining['cylinder5'],
                          'apron': remaining['apron'],
                          'stove': remaining['stove'],
                          'lighter': remaining['lighter'],
                          'receiptPromptedOn': Timestamp.fromDate(
                            DateTime.now(),
                          ),
                          'lastReceiptCheck': 'partial',
                          'lastReceiptCheckedAt':
                              FieldValue.serverTimestamp(),
                          'lastReceiptCheckedBy':
                              FirebaseAuth.instance.currentUser?.email ?? '',
                          'updatedAt': FieldValue.serverTimestamp(),
                        },
                        SetOptions(merge: true),
                      );
                    }
                  },
                );

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                if (parentContext.mounted) {
                  showMessage(
                    'Received stock inventory mein update ho gaya.',
                  );
                }
              } catch (e) {
                setDialogState(() {
                  saving = false;
                });
                if (dialogContext.mounted) {
                  showMessage('Stock receive save failed: $e');
                }
              }
            }

            return AlertDialog(
              title: const Text('Stock Receive Confirmation'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aaj ${formatDate(arrivalDay)} ka stock scheduled hai.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Kya ordered stock receive hua hai? Inventory mein sirf wahi quantity add hogi jo aap yahan confirm karoge.',
                    ),
                    const SizedBox(height: 16),
                    if (!receivedConfirmed) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: saving
                              ? null
                              : () {
                                  setDialogState(() {
                                    receivedConfirmed = true;
                                  });
                                },
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Haan, stock receive hua'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: saving ? null : markNotReceived,
                          icon: const Icon(Icons.schedule),
                          label: const Text('Nahi, abhi receive nahi hua'),
                        ),
                      ),
                    ] else ...[
                      const Text(
                        'Jo items receive hue hain unhe tick karo. Quantity kam receive hui ho to actual quantity enter karo.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      for (final key in itemLabels.keys)
                        if (orderedQuantities[key]! > 0)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: selected[key],
                                    onChanged: saving
                                        ? null
                                        : (value) {
                                            setDialogState(() {
                                              selected[key] = value ?? false;
                                            });
                                          },
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${itemLabels[key]}\nOrdered: ${orderedQuantities[key]}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 90,
                                    child: TextField(
                                      controller: receivedControllers[key],
                                      enabled: !saving && selected[key]!,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      decoration: const InputDecoration(
                                        labelText: 'Received',
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (receivedConfirmed)
                  TextButton(
                    onPressed: saving
                        ? null
                        : () {
                            setDialogState(() {
                              receivedConfirmed = false;
                            });
                          },
                    child: const Text('Back'),
                  ),
                if (receivedConfirmed)
                  FilledButton.icon(
                    onPressed: saving ? null : confirmReceived,
                    icon: const Icon(Icons.inventory_2),
                    label: const Text('Confirm & Update Inventory'),
                  ),
              ],
            );
          },
        );
      },
    );
  } finally {
    for (final controller in receivedControllers.values) {
      controller.dispose();
    }
  }
}

DocumentReference<Map<String, dynamic>> firestoreRef(String productId) {
  return FirebaseFirestore.instance
      .collection('inventory')
      .doc(productId);
}

// ============================================================
// MAIN SCREEN - EXACTLY 5 TABS
// ============================================================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;

  @override
  void initState() {
    super.initState();

    // On the first app open of the arrival date, ask the user
    // what portion of the ordered stock was actually received.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      checkAndPromptForUpcomingStockReceipt(context);
    });
  }

  final List<String> titles = const [
    'Dashboard',
    'Inventory',
    'Customers',
    'Staff',
    'Issues',
  ];

  final List<Widget> pages = const [
    DashboardScreen(),
    InventoryScreen(),
    CustomersScreen(),
    StaffScreen(),
    IssuesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          titles[selectedIndex],
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Inventory Activity',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const InventoryActivityScreen(),
                ),
              );
            },
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            tooltip: 'Profile & Security',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SecurityProfileScreen(),
                ),
              );
            },
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: BlueRedSectionBackground(
        child: IndexedStack(
          index: selectedIndex,
          children: pages,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventory',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Customers',
          ),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge),
            label: 'Staff',
          ),
          NavigationDestination(
            icon: Icon(Icons.report_problem_outlined),
            selectedIcon: Icon(Icons.report_problem),
            label: 'Issues',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DASHBOARD
// ============================================================

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Inventory',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('inventory')
                .doc('cylinder')
                .snapshots(),
            builder: (context, snapshot) {
              return DashboardInventoryCard(
                icon: Icons.local_fire_department,
                title: 'Cylinder',
                color: const Color(0xFF64B5F6),
                value: snapshot.hasData && snapshot.data!.exists
                    ? 'View Stock'
                    : 'No data',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CylinderDetailScreen(),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 10),
          DashboardInventoryCard(
            icon: Icons.checkroom,
            title: 'Apron',
            color: const Color(0xFF64B5F6),
            value: 'View Stock',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProductDetailScreen(
                    productId: 'apron',
                    productName: 'Apron',
                    icon: Icons.checkroom,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          DashboardInventoryCard(
            icon: Icons.soup_kitchen_outlined,
            title: 'Stove',
            color: const Color(0xFF64B5F6),
            value: 'View Stock',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProductDetailScreen(
                    productId: 'stove',
                    productName: 'Stove',
                    icon: Icons.soup_kitchen_outlined,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          DashboardInventoryCard(
            icon: Icons.local_fire_department_outlined,
            title: 'Lighter',
            color: const Color(0xFF64B5F6),
            value: 'View Stock',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProductDetailScreen(
                    productId: 'lighter',
                    productName: 'Lighter',
                    icon: Icons.local_fire_department_outlined,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Upcoming Stock',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const UpcomingStockCard(),
          const SizedBox(height: 24),
          const Text(
            'Stock Arrival History',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const StockArrivalHistory(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class DashboardInventoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final String value;
  final VoidCallback onTap;

  const DashboardInventoryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// UPCOMING STOCK CARD
// ============================================================

class UpcomingStockCard extends StatelessWidget {
  const UpcomingStockCard({super.key});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('inventory')
        .doc('upcomingStock');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        final data = snapshot.data?.data();

        if (data == null) {
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  showUpcomingStockDialog(context);
                });
              },
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(
                      Icons.local_shipping_outlined,
                      size: 34,
                      color: Colors.red,
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'No upcoming stock added.\nTap to add.',
                      ),
                    ),
                    Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          );
        }

        final Timestamp? timestamp =
            data['arrivalDate'] as Timestamp?;

        final date = timestamp?.toDate();

        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                showUpcomingStockDialog(context);
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.local_shipping_outlined,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Next Stock Arrival',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              date == null
                                  ? 'Date not set'
                                  : formatDate(date),
                              style: const TextStyle(
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.edit_outlined),
                    ],
                  ),
                  const Divider(height: 28),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SmallStockChip(
                        label: '14kg',
                        value: number(data['cylinder14']),
                      ),
                      SmallStockChip(
                        label: '19kg',
                        value: number(data['cylinder19']),
                      ),
                      SmallStockChip(
                        label: '5kg',
                        value: number(data['cylinder5']),
                      ),
                      SmallStockChip(
                        label: 'Apron',
                        value: number(data['apron']),
                      ),
                      SmallStockChip(
                        label: 'Stove',
                        value: number(data['stove']),
                      ),
                      SmallStockChip(
                        label: 'Lighter',
                        value: number(data['lighter']),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class SmallStockChip extends StatelessWidget {
  final String label;
  final String value;

  const SmallStockChip({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ============================================================
// STOCK ARRIVAL HISTORY
// ============================================================

class StockArrivalHistory extends StatefulWidget {
  const StockArrivalHistory({super.key});

  @override
  State<StockArrivalHistory> createState() => _StockArrivalHistoryState();
}

class _StockArrivalHistoryState extends State<StockArrivalHistory> {
  late int selectedYear;
  late int selectedMonth;

  static const List<String> monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedYear = now.year;
    selectedMonth = now.month;
  }

  void changeYear(int amount) {
    setState(() {
      selectedYear += amount;
    });
  }

  @override
  Widget build(BuildContext context) {
    final oneYearAgo = DateTime.now().subtract(
      const Duration(days: 365),
    );

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('stockArrivals')
          .where(
            'date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(oneYearAgo),
          )
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'Stock history load nahi ho pa rahi.\n${snapshot.error}',
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final selectedDocs = docs.where((doc) {
          final timestamp = doc.data()['date'] as Timestamp?;
          if (timestamp == null) return false;
          final date = timestamp.toDate();
          return date.year == selectedYear && date.month == selectedMonth;
        }).toList();

        int totalFor(String field) {
          return selectedDocs.fold<int>(
            0,
            (sum, doc) => sum + intValue(number(doc.data()[field])),
          );
        }

        final totals = <String, int>{
          '14kg': totalFor('cylinder14'),
          '19kg': totalFor('cylinder19'),
          '5kg': totalFor('cylinder5'),
          'Apron': totalFor('apron'),
          'Stove': totalFor('stove'),
          'Lighter': totalFor('lighter'),
        };

        return Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () {
                  showStockArrivalDialog(context);
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Stock Arrival'),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous year',
                          onPressed: () => changeYear(-1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Text(
                            '$selectedYear',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next year',
                          onPressed: () => changeYear(1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 12,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.65,
                      ),
                      itemBuilder: (context, index) {
                        final month = index + 1;
                        final hasArrival = docs.any((doc) {
                          final timestamp = doc.data()['date'] as Timestamp?;
                          if (timestamp == null) return false;
                          final date = timestamp.toDate();
                          return date.year == selectedYear &&
                              date.month == month;
                        });
                        final selected = month == selectedMonth;

                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            setState(() {
                              selectedMonth = month;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF64B5F6)
                                  : hasArrival
                                      ? const Color(0xFFEAF4FF)
                                      : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFF1976D2)
                                    : hasArrival
                                        ? const Color(0xFF90CAF9)
                                        : Colors.grey.shade300,
                                width: selected ? 2 : 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              monthNames[index].substring(0, 3),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${monthNames[selectedMonth - 1]} $selectedYear',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (selectedDocs.isEmpty)
                      const Text(
                        'Is month mein koi stock arrival record nahi hai.',
                      )
                    else ...[
                      const Text(
                        'Total stock received this month',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in totals.entries)
                            if (entry.value > 0)
                              SmallStockChip(
                                label: entry.key,
                                value: '${entry.value}',
                              ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ...selectedDocs.map(
                        (doc) => StockArrivalTile(doc: doc),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class StockArrivalTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  const StockArrivalTile({
    super.key,
    required this.doc,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final Timestamp? timestamp = data['date'] as Timestamp?;
    final date = timestamp?.toDate();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.local_shipping,
                  color: Colors.red,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    date == null
                        ? 'Date not set'
                        : formatDate(date),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    final confirm = await showDeleteConfirmation(
                      context,
                      'Delete this stock arrival record?',
                    );

                    if (confirm == true) {
                      try {
                        await doc.reference.delete();

                        if (context.mounted) {
                          showMessage(
                            'Stock arrival deleted.',
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showMessage(
                            'Delete failed: $e',
                          );
                        }
                      }
                    }
                  },
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SmallStockChip(
                  label: '14kg',
                  value: number(data['cylinder14']),
                ),
                SmallStockChip(
                  label: '19kg',
                  value: number(data['cylinder19']),
                ),
                SmallStockChip(
                  label: '5kg',
                  value: number(data['cylinder5']),
                ),
                SmallStockChip(
                  label: 'Apron',
                  value: number(data['apron']),
                ),
                SmallStockChip(
                  label: 'Stove',
                  value: number(data['stove']),
                ),
                SmallStockChip(
                  label: 'Lighter',
                  value: number(data['lighter']),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// INVENTORY
// ============================================================

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InventoryMenuCard(
          title: 'Cylinder',
          subtitle: '14kg, 19kg, 5kg',
          icon: Icons.local_fire_department,
          color: Colors.red,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CylinderDetailScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        InventoryMenuCard(
          title: 'Apron',
          subtitle: 'Stock, Issued, Damaged, Incoming',
          icon: Icons.checkroom,
          color: Colors.blue,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProductDetailScreen(
                  productId: 'apron',
                  productName: 'Apron',
                  icon: Icons.checkroom,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        InventoryMenuCard(
          title: 'Stove',
          subtitle: 'Stock, Issued, Damaged, Incoming',
          icon: Icons.soup_kitchen_outlined,
          color: Colors.orange,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProductDetailScreen(
                  productId: 'stove',
                  productName: 'Stove',
                  icon: Icons.soup_kitchen_outlined,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        InventoryMenuCard(
          title: 'Lighter',
          subtitle: 'Stock, Issued, Damaged, Incoming',
          icon: Icons.local_fire_department_outlined,
          color: Colors.deepPurple,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProductDetailScreen(
                  productId: 'lighter',
                  productName: 'Lighter',
                  icon: Icons.local_fire_department_outlined,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class InventoryMenuCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const InventoryMenuCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CYLINDER DETAIL
// ============================================================

class CylinderDetailScreen extends StatelessWidget {
  const CylinderDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('inventory').doc('cylinder');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cylinder'),
        actions: [
          IconButton(
            tooltip: 'All Inventory Activity',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InventoryActivityScreen()),
            ),
          ),
        ],
      ),
      body: BlueRedSectionBackground(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: ref.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data?.data() ?? {};
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final size in ['14', '19', '5']) ...[
                  StockSectionCard(
                    title: '$size kg Cylinder Stock',
                    trailing: IconButton(
                      tooltip: '$size kg Activity',
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InventoryActivityScreen(
                            filterItem: '$size kg Cylinder',
                          ),
                        ),
                      ),
                    ),
                    children: [
                      StockRow(label: 'Total Stock Left', value: number(data['stockLeft$size'])),
                      StockRow(label: 'Filled Cylinder', value: number(data['filled$size'])),
                      StockRow(label: 'Empty Cylinder', value: number(data['empty$size'])),
                      StockRow(label: 'Damaged Cylinder', value: number(data['damaged$size'])),
                      StockRow(label: 'Undelivered Cylinder', value: number(data['undelivered$size'])),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Stock Rule', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('For every cylinder size: Total Stock Left = Filled + Empty + Damaged + Undelivered.'),
                        const SizedBox(height: 6),
                        Text('Changing any value automatically adjusts the connected value.', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                FilledButton.icon(
                  onPressed: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!context.mounted) return;
                      showCylinderEditDialog(context, data);
                    });
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit Cylinder Stock'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class StockSectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  const StockSectionCard({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class StockRow extends StatelessWidget {
  final String label;
  final String value;

  const StockRow({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(label),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PRODUCT DETAIL - APRON/STOVE/LIGHTER
// ============================================================

class ProductDetailScreen extends StatelessWidget {
  final String productId;
  final String productName;
  final IconData icon;

  const ProductDetailScreen({
    super.key,
    required this.productId,
    required this.productName,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('inventory')
        .doc(productId);

    return Scaffold(
      appBar: AppBar(
        title: Text(productName),
        actions: [
          IconButton(
            tooltip: 'Activity',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InventoryActivityScreen()),
            ),
          ),
        ],
      ),
      body: BlueRedSectionBackground(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: ref.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final data = snapshot.data?.data() ?? {};

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          icon,
                          color: Colors.red,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        productName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              StockSectionCard(
                title: 'Stock Details',
                children: [
                  StockRow(
                    label: 'Total Stock Left',
                    value: number(data['stockLeft']),
                  ),
                  StockRow(
                    label: 'Issued',
                    value: number(data['issued']),
                  ),
                  StockRow(
                    label: 'Damaged',
                    value: number(data['damaged']),
                  ),
                  StockRow(
                    label: 'Incoming',
                    value: number(data['incoming']),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    showProductEditDialog(
                      context,
                      productId,
                      productName,
                      data,
                    );
                  });
                },
                icon: const Icon(Icons.edit),
                label: Text('Edit $productName Stock'),
              ),
            ],
          );
        },
      ),
      ),
    );
  }
}

// ============================================================
// CUSTOMERS
// ============================================================

class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final collection =
        FirebaseFirestore.instance.collection('customers');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () {
                showCustomerDialog(context);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Customer'),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: collection
                .orderBy('name')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Customers load nahi ho pa rahe.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              if (snapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return const EmptyState(
                  icon: Icons.people_outline,
                  title: 'No Customers',
                  message: 'Abhi koi customer add nahi kiya gaya.',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  20,
                ),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();

                  return CustomerTile(
                    doc: doc,
                    data: data,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class CustomerTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Map<String, dynamic> data;

  const CustomerTile({
    super.key,
    required this.doc,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final active = data['active'] == true;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            ((data['name'] ?? 'C').toString().isEmpty)
                ? 'C'
                : data['name']
                    .toString()
                    .substring(0, 1)
                    .toUpperCase(),
          ),
        ),
        title: Text(
          data['name'] ?? 'Unnamed',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${data['phone'] ?? ''}\n'
            '${data['address'] ?? ''}\n'
            '${active ? 'Active' : 'Inactive'}',
          ),
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            // Wait for the popup-menu route to finish deactivating
            // before opening another route.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;

              if (value == 'edit') {
                showCustomerDialog(
                  context,
                  doc: doc,
                  existingData: data,
                );
              } else if (value == 'delete') {
                deleteCustomer(
                  context,
                  doc.reference,
                );
              }
            });
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'edit',
              child: Text('Edit'),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text('Remove'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// STAFF
// ============================================================

class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final collection =
        FirebaseFirestore.instance.collection('staff');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () {
                showStaffDialog(context);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Staff'),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: collection
                .orderBy('name')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Staff load nahi ho pa raha.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              if (snapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return const EmptyState(
                  icon: Icons.badge_outlined,
                  title: 'No Staff',
                  message: 'Abhi koi staff member add nahi kiya gaya.',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  20,
                ),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];

                  return StaffTile(
                    doc: doc,
                    data: doc.data(),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class StaffTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Map<String, dynamic> data;

  const StaffTile({
    super.key,
    required this.doc,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final active = data['active'] == true;

    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.person),
        ),
        title: Text(
          data['name'] ?? 'Unnamed',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            'Staff ID: ${data['staffId'] ?? ''}\n'
            'Phone: ${data['phone'] ?? ''}\n'
            'Role: ${data['role'] ?? ''}\n'
            'Joining: ${data['joiningDate'] ?? ''}\n'
            '${active ? 'Active' : 'Inactive'}',
          ),
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            // Wait for the popup-menu route to finish deactivating
            // before opening another route.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;

              if (value == 'edit') {
                showStaffDialog(
                  context,
                  doc: doc,
                  existingData: data,
                );
              } else if (value == 'delete') {
                deleteStaff(
                  context,
                  doc.reference,
                );
              }
            });
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'edit',
              child: Text('Edit'),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text('Remove'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ISSUES
// ============================================================


// Stubs for remaining modules
class IssuesScreen extends StatelessWidget {
  const IssuesScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('Issues Module'));
}
Future<void> showCylinderEditDialog(
  BuildContext parentContext,
  Map<String, dynamic> data,
) async {
  final fields = <String, TextEditingController>{};
  for (final size in ['14', '19', '5']) {
    for (final field in ['stockLeft', 'filled', 'empty', 'damaged', 'undelivered']) {
      fields['$field$size'] = TextEditingController(text: number(data['$field$size']));
    }
  }

  bool syncing = false;

  void setValue(TextEditingController c, int value) {
    final safe = value < 0 ? 0 : value;
    final text = safe.toString();
    c.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  void recalculate(String size, String changed) {
    if (syncing) return;
    syncing = true;
    try {
      final totalC = fields['stockLeft$size']!;
      final filledC = fields['filled$size']!;
      final emptyC = fields['empty$size']!;
      final damagedC = fields['damaged$size']!;
      final undeliveredC = fields['undelivered$size']!;
      final total = intValue(totalC.text);
      final filled = intValue(filledC.text);
      final empty = intValue(emptyC.text);
      final damaged = intValue(damagedC.text);
      final undelivered = intValue(undeliveredC.text);

      if (changed == 'empty$size') {
        setValue(totalC, filled + empty + damaged + undelivered);
      } else {
        setValue(emptyC, total - filled - damaged - undelivered);
      }
    } finally {
      syncing = false;
    }
  }

  final listenerPairs = <({TextEditingController controller, VoidCallback listener})>[];
  for (final size in ['14', '19', '5']) {
    for (final field in ['stockLeft', 'filled', 'empty', 'damaged', 'undelivered']) {
      final controller = fields['$field$size']!;
      void listener() => recalculate(size, '$field$size');
      controller.addListener(listener);
      listenerPairs.add((controller: controller, listener: listener));
    }
  }

  try {
    await showDialog(
      context: parentContext,
      builder: (dialogContext) {
        bool saving = false;
        return StatefulBuilder(
          builder: (dialogBuilderContext, setDialogState) {
            Future<void> handleSave() async {
              if (saving) return;
              FocusScope.of(dialogBuilderContext).unfocus();

              for (final size in ['14', '19', '5']) {
                final total = intValue(fields['stockLeft$size']!.text);
                final filled = intValue(fields['filled$size']!.text);
                final empty = intValue(fields['empty$size']!.text);
                final damaged = intValue(fields['damaged$size']!.text);
                final undelivered = intValue(fields['undelivered$size']!.text);
                if (total < 0 || filled < 0 || empty < 0 || damaged < 0 || undelivered < 0) {
                  showMessage('Cylinder values cannot be negative.');
                  return;
                }
                if (total != filled + empty + damaged + undelivered) {
                  showMessage('$size kg stock is not balanced. Total must equal Filled + Empty + Damaged + Undelivered.');
                  return;
                }
              }

              setDialogState(() => saving = true);
              try {
                final update = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
                final activityBySize = <String, Map<String, dynamic>>{};
                for (final size in ['14', '19', '5']) {
                  final changesForSize = <String, dynamic>{};
                  for (final field in ['stockLeft', 'filled', 'empty', 'damaged', 'undelivered']) {
                    final oldValue = intValue(number(data['$field$size']));
                    final newValue = intValue(fields['$field$size']!.text);
                    update['$field$size'] = newValue;
                    if (oldValue != newValue) {
                      final label = switch (field) {
                        'stockLeft' => 'Total Stock Left',
                        'filled' => 'Filled Cylinder',
                        'empty' => 'Empty Cylinder',
                        'damaged' => 'Damaged Cylinder',
                        'undelivered' => 'Undelivered Cylinder',
                        _ => field,
                      };
                      changesForSize[label] = '$oldValue → $newValue';
                    }
                  }
                  if (changesForSize.isNotEmpty) {
                    activityBySize['$size kg Cylinder'] = changesForSize;
                  }
                }
                await FirebaseFirestore.instance.collection('inventory').doc('cylinder').set(update, SetOptions(merge: true));
                for (final entry in activityBySize.entries) {
                  await logInventoryActivity(
                    action: 'Stock Updated',
                    section: 'Cylinder',
                    item: entry.key,
                    changes: entry.value,
                  );
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (parentContext.mounted) showMessage('Cylinder stock saved successfully.');
              } catch (e) {
                setDialogState(() => saving = false);
                if (dialogContext.mounted) showMessage('Save failed: $e');
              }
            }

            return AlertDialog(
              title: const Text('Edit Cylinder Stock'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const Text('All cylinder values are connected. Edit any field and the related value will update automatically.'),
                      const SizedBox(height: 14),
                      for (final size in ['14', '19', '5']) ...[
                        SectionLabel(text: '$size kg Cylinder'),
                        NumberField(label: 'Total Stock Left', controller: fields['stockLeft$size']!, enabled: !saving),
                        NumberField(label: 'Filled Cylinder', controller: fields['filled$size']!, enabled: !saving),
                        NumberField(label: 'Empty Cylinder', controller: fields['empty$size']!, enabled: !saving),
                        NumberField(label: 'Damaged Cylinder', controller: fields['damaged$size']!, enabled: !saving),
                        NumberField(label: 'Undelivered Cylinder', controller: fields['undelivered$size']!, enabled: !saving),
                        if (size != '5') const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () { FocusScope.of(dialogBuilderContext).unfocus(); Navigator.pop(dialogContext); },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving ? null : handleSave,
                  child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    for (final pair in listenerPairs) pair.controller.removeListener(pair.listener);
    for (final controller in fields.values) controller.dispose();
  }
}

// ============================================================
// DIALOG: PRODUCT EDIT
// ============================================================

Future<void> showProductEditDialog(
  BuildContext parentContext,
  String productId,
  String productName,
  Map<String, dynamic> data,
) async {
  final stockLeftController = TextEditingController(
    text: number(data['stockLeft']),
  );
  final issuedController = TextEditingController(
    text: number(data['issued']),
  );
  final damagedController = TextEditingController(
    text: number(data['damaged']),
  );
  final incomingController = TextEditingController(
    text: number(data['incoming']),
  );

  try {
    await showDialog(
      context: parentContext,
      builder: (dialogContext) {
        bool saving = false;

        return StatefulBuilder(
          builder: (dialogBuilderContext, setDialogState) {
            Future<void> handleSave() async {
              if (saving) return;

              FocusScope.of(dialogBuilderContext).unfocus();

              setDialogState(() {
                saving = true;
              });

              try {
                final oldStock = intValue(number(data['stockLeft']));
                final oldIssued = intValue(number(data['issued']));
                final oldDamaged = intValue(number(data['damaged']));
                final oldIncoming = intValue(number(data['incoming']));
                final newStock = intValue(stockLeftController.text);
                final newIssued = intValue(issuedController.text);
                final newDamaged = intValue(damagedController.text);
                final newIncoming = intValue(incomingController.text);

                await FirebaseFirestore.instance
                    .collection('inventory')
                    .doc(productId)
                    .set({
                  'stockLeft': newStock,
                  'issued': newIssued,
                  'damaged': newDamaged,
                  'incoming': newIncoming,
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));

                final activityChanges = <String, dynamic>{};
                if (oldStock != newStock) activityChanges['Total Stock Left'] = '$oldStock → $newStock';
                if (oldIssued != newIssued) activityChanges['Issued'] = '$oldIssued → $newIssued';
                if (oldDamaged != newDamaged) activityChanges['Damaged'] = '$oldDamaged → $newDamaged';
                if (oldIncoming != newIncoming) activityChanges['Incoming'] = '$oldIncoming → $newIncoming';
                if (activityChanges.isNotEmpty) {
                  await logInventoryActivity(
                    action: 'Stock Updated',
                    section: 'Inventory',
                    item: productName,
                    changes: activityChanges,
                  );
                }

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                if (parentContext.mounted) {
                  showMessage(
                    '$productName stock saved successfully.',
                  );
                }
              } catch (e) {
                setDialogState(() {
                  saving = false;
                });
                if (dialogContext.mounted) {
                  showMessage(
                    'Save failed: $e',
                  );
                }
              }
            }

            return AlertDialog(
              title: Text('Edit $productName'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NumberField(
                      label: 'Total Stock Left',
                      controller: stockLeftController,
                      enabled: !saving,
                    ),
                    NumberField(
                      label: 'Issued',
                      controller: issuedController,
                      enabled: !saving,
                    ),
                    NumberField(
                      label: 'Damaged',
                      controller: damagedController,
                      enabled: !saving,
                    ),
                    NumberField(
                      label: 'Incoming',
                      controller: incomingController,
                      enabled: !saving,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          FocusScope.of(dialogBuilderContext).unfocus();
                          Navigator.pop(dialogContext);
                        },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving ? null : handleSave,
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    stockLeftController.dispose();
    issuedController.dispose();
    damagedController.dispose();
    incomingController.dispose();
  }
}

// ============================================================
// DIALOG: UPCOMING STOCK
// ============================================================

Future<void> showUpcomingStockDialog(
  BuildContext parentContext,
) async {
  final ref = FirebaseFirestore.instance
      .collection('inventory')
      .doc('upcomingStock');

  DocumentSnapshot<Map<String, dynamic>> snapshot;

  try {
    snapshot = await ref.get();
  } catch (e) {
    if (parentContext.mounted) {
      showMessage(
        'Upcoming stock load failed: $e',
      );
    }
    return;
  }

  final data = snapshot.data() ?? {};

  DateTime selectedDate =
      (data['arrivalDate'] as Timestamp?)?.toDate() ??
          DateTime.now();

  final controllers = <String, TextEditingController>{
    'cylinder14': TextEditingController(
      text: number(data['cylinder14']),
    ),
    'cylinder19': TextEditingController(
      text: number(data['cylinder19']),
    ),
    'cylinder5': TextEditingController(
      text: number(data['cylinder5']),
    ),
    'apron': TextEditingController(
      text: number(data['apron']),
    ),
    'stove': TextEditingController(
      text: number(data['stove']),
    ),
    'lighter': TextEditingController(
      text: number(data['lighter']),
    ),
  };

  try {
    await showDialog(
      context: parentContext,
      builder: (dialogContext) {
        bool saving = false;

        return StatefulBuilder(
          builder: (dialogBuilderContext, setDialogState) {
            Future<void> handleSave() async {
              if (saving) return;

              FocusScope.of(dialogBuilderContext).unfocus();

              setDialogState(() {
                saving = true;
              });

              try {
                await ref.set({
                  'arrivalDate':
                      Timestamp.fromDate(selectedDate),
                  'cylinder14':
                      intValue(
                    controllers['cylinder14']!.text,
                  ),
                  'cylinder19':
                      intValue(
                    controllers['cylinder19']!.text,
                  ),
                  'cylinder5':
                      intValue(
                    controllers['cylinder5']!.text,
                  ),
                  'apron':
                      intValue(
                    controllers['apron']!.text,
                  ),
                  'stove':
                      intValue(
                    controllers['stove']!.text,
                  ),
                  'lighter':
                      intValue(
                    controllers['lighter']!.text,
                  ),
                  'updatedAt':
                      FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                if (parentContext.mounted) {
                  showMessage(
                    'Upcoming stock saved successfully.',
                  );
                }
              } catch (e) {
                setDialogState(() {
                  saving = false;
                });
                if (dialogContext.mounted) {
                  showMessage(
                    'Save failed: $e',
                  );
                }
              }
            }

            return AlertDialog(
              title: const Text('Upcoming Stock'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.calendar_month,
                      ),
                      title: const Text(
                        'Next Stock Arrival',
                      ),
                      subtitle: Text(
                        formatDate(selectedDate),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                      ),
                      onTap: saving
                          ? null
                          : () async {
                              // Clear focus before opening a nested
                              // route (the date picker) too.
                              FocusScope.of(dialogBuilderContext)
                                  .unfocus();

                              final picked =
                                  await showDatePicker(
                                context: dialogBuilderContext,
                                initialDate: selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );

                              if (picked != null) {
                                setDialogState(() {
                                  selectedDate = picked;
                                });
                              }
                            },
                    ),
                    const Divider(),
                    NumberField(
                      label: '14kg Cylinder',
                      controller: controllers['cylinder14']!,
                      enabled: !saving,
                    ),
                    NumberField(
                      label: '19kg Cylinder',
                      controller: controllers['cylinder19']!,
                      enabled: !saving,
                    ),
                    NumberField(
                      label: '5kg Cylinder',
                      controller: controllers['cylinder5']!,
                      enabled: !saving,
                    ),
                    NumberField(
                      label: 'Apron',
                      controller: controllers['apron']!,
                      enabled: !saving,
                    ),
                    NumberField(
                      label: 'Stove',
                      controller: controllers['stove']!,
                      enabled: !saving,
                    ),
                    NumberField(
                      label: 'Lighter',
                      controller: controllers['lighter']!,
                      enabled: !saving,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          FocusScope.of(dialogBuilderContext).unfocus();
                          Navigator.pop(dialogContext);
                        },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving ? null : handleSave,
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }
}

// ============================================================
// DIALOG: STOCK ARRIVAL
// ============================================================

Future<void> showStockArrivalDialog(
  BuildContext parentContext,
) async {
  DateTime selectedDate = DateTime.now();

  final controllers = <String, TextEditingController>{
    'cylinder14': TextEditingController(),
    'cylinder19': TextEditingController(),
    'cylinder5': TextEditingController(),
    'apron': TextEditingController(),
    'stove': TextEditingController(),
    'lighter': TextEditingController(),
  };

  try {
    await showDialog(
      context: parentContext,
      builder: (dialogContext) {
        bool saving = false;

        return StatefulBuilder(
          builder: (dialogBuilderContext, setDialogState) {
            Future<void> handleSave() async {
              if (saving) return;

              FocusScope.of(dialogBuilderContext).unfocus();

              setDialogState(() {
                saving = true;
              });

              try {
                await FirebaseFirestore.instance
                    .collection('stockArrivals')
                    .add({
                  'date':
                      Timestamp.fromDate(selectedDate),
                  'cylinder14':
                      intValue(
                    controllers['cylinder14']!.text,
                  ),
                  'cylinder19':
                      intValue(
                    controllers['cylinder19']!.text,
                  ),
                  'cylinder5':
                      intValue(
                    controllers['cylinder5']!.text,
                  ),
                  'apron':
                      intValue(
                    controllers['apron']!.text,
                  ),
                  'stove':
                      intValue(
                    controllers['stove']!.text,
                  ),
                  'lighter':
                      intValue(
                    controllers['lighter']!.text,
                  ),
                  'createdAt':
                      FieldValue.serverTimestamp(),
                });

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                if (parentContext.mounted) {
                  showMessage(
                    'Stock arrival saved successfully.',
                  );
                }
              } catch (e) {
                setDialogState(() {
                  saving = false;
                });
                if (dialogContext.mounted) {
                  showMessage(
                    'Save failed: $e',
                  );
                }
              }
            }

            return AlertDialog(
              title: const Text('Add Stock Arrival'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.calendar_month,
                      ),
                      title: const Text('Arrival Date'),
                      subtitle: Text(
                        formatDate(selectedDate),
                      ),
                      onTap: saving
                          ? null
                          : () async {
                              FocusScope.of(dialogBuilderContext)
                                  .unfocus();

                              final picked =
                                  await showDatePicker(
                                context: dialogBuilderContext,
                                initialDate: selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );

                              if (picked != null) {
                                setDialogState(() {
                                  selectedDate = picked;
                                });
                              }
                            },
                    ),
                    const Divider(),
                    NumberField(
                      label: '14kg Cylinder',
                      controller: controllers['cylinder14']!,
                      enabled: !saving,
                    ),
                    NumberField(
                      label: '19kg Cylinder',
                      controller: controllers['cylinder19']!,
                      enabled: !saving,
                    ),
                    NumberField(
                      label: '5kg Cylinder',
                      controller: controllers['cylinder5']!,
                      enabled: !saving,
                    ),
                    NumberField(
                      label: 'Apron',
                      controller: controllers['apron']!,
                      enabled: !saving,
                    ),
                    NumberField(
                      label: 'Stove',
                      controller: controllers['stove']!,
                      enabled: !saving,
                    ),
                    NumberField(
                      label: 'Lighter',
                      controller: controllers['lighter']!,
                      enabled: !saving,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          FocusScope.of(dialogBuilderContext).unfocus();
                          Navigator.pop(dialogContext);
                        },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving ? null : handleSave,
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }
}

// ============================================================
// DIALOG: CUSTOMER
// ============================================================

Future<void> showCustomerDialog(
  BuildContext parentContext, {
  QueryDocumentSnapshot<Map<String, dynamic>>? doc,
  Map<String, dynamic>? existingData,
}) async {
  final data = existingData ?? {};

  final nameController = TextEditingController(
    text: data['name'] ?? '',
  );
  final phoneController = TextEditingController(
    text: data['phone'] ?? '',
  );
  final addressController = TextEditingController(
    text: data['address'] ?? '',
  );

  bool active = data['active'] == true;

  try {
    await showDialog(
      context: parentContext,
      builder: (dialogContext) {
        bool saving = false;

        return StatefulBuilder(
          builder: (dialogBuilderContext, setDialogState) {
            Future<void> handleSave() async {
              if (saving) return;

              if (nameController.text.trim().isEmpty) {
                showMessage(
                  'Customer name required hai.',
                );
                return;
              }

              FocusScope.of(dialogBuilderContext).unfocus();

              setDialogState(() {
                saving = true;
              });

              try {
                final customerData = {
                  'name': nameController.text.trim(),
                  'phone': phoneController.text.trim(),
                  'address':
                      addressController.text.trim(),
                  'active': active,
                  'updatedAt':
                      FieldValue.serverTimestamp(),
                };

                if (doc == null) {
                  customerData['createdAt'] =
                      FieldValue.serverTimestamp();

                  await FirebaseFirestore.instance
                      .collection('customers')
                      .add(customerData);
                } else {
                  await doc.reference.update(
                    customerData,
                  );
                }

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                if (parentContext.mounted) {
                  showMessage(
                    doc == null
                        ? 'Customer added successfully.'
                        : 'Customer updated successfully.',
                  );
                }
              } catch (e) {
                setDialogState(() {
                  saving = false;
                });
                if (dialogContext.mounted) {
                  showMessage(
                    'Save failed: $e',
                  );
                }
              }
            }

            return AlertDialog(
              title: Text(
                doc == null
                    ? 'Add Customer'
                    : 'Edit Customer',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      enabled: !saving,
                      textCapitalization:
                          TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Customer Name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      enabled: !saving,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      enabled: !saving,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      value: active,
                      onChanged: saving
                          ? null
                          : (value) {
                              setDialogState(() {
                                active = value;
                              });
                            },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          FocusScope.of(dialogBuilderContext).unfocus();
                          Navigator.pop(dialogContext);
                        },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving ? null : handleSave,
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
  }
}

// ============================================================
// DIALOG: STAFF
// ============================================================

Future<void> showStaffDialog(
  BuildContext parentContext, {
  QueryDocumentSnapshot<Map<String, dynamic>>? doc,
  Map<String, dynamic>? existingData,
}) async {
  final data = existingData ?? {};

  final staffIdController = TextEditingController(
    text: data['staffId'] ?? '',
  );
  final nameController = TextEditingController(
    text: data['name'] ?? '',
  );
  final phoneController = TextEditingController(
    text: data['phone'] ?? '',
  );
  final emailController = TextEditingController(
    text: data['email'] ?? '',
  );
  final roleController = TextEditingController(
    text: data['role'] ?? '',
  );
  final joiningDateController = TextEditingController(
    text: data['joiningDate'] ?? '',
  );
  final notesController = TextEditingController(
    text: data['notes'] ?? '',
  );

  bool active = data['active'] == true;

  try {
    await showDialog(
      context: parentContext,
      builder: (dialogContext) {
        bool saving = false;

        return StatefulBuilder(
          builder: (dialogBuilderContext, setDialogState) {
            Future<void> handleSave() async {
              if (saving) return;

              if (nameController.text.trim().isEmpty) {
                showMessage(
                  'Staff name required hai.',
                );
                return;
              }

              FocusScope.of(dialogBuilderContext).unfocus();

              setDialogState(() {
                saving = true;
              });

              try {
                final staffData = {
                  'staffId':
                      staffIdController.text.trim(),
                  'name': nameController.text.trim(),
                  'phone':
                      phoneController.text.trim(),
                  'email':
                      emailController.text.trim(),
                  'role':
                      roleController.text.trim(),
                  'joiningDate':
                      joiningDateController.text.trim(),
                  'active': active,
                  'notes':
                      notesController.text.trim(),
                  'updatedAt':
                      FieldValue.serverTimestamp(),
                };

                if (doc == null) {
                  staffData['createdAt'] =
                      FieldValue.serverTimestamp();

                  await FirebaseFirestore.instance
                      .collection('staff')
                      .add(staffData);
                } else {
                  await doc.reference.update(
                    staffData,
                  );
                }

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                if (parentContext.mounted) {
                  showMessage(
                    doc == null
                        ? 'Staff added successfully.'
                        : 'Staff updated successfully.',
                  );
                }
              } catch (e) {
                setDialogState(() {
                  saving = false;
                });
                if (dialogContext.mounted) {
                  showMessage(
                    'Save failed: $e',
                  );
                }
              }
            }

            return AlertDialog(
              title: Text(
                doc == null ? 'Add Staff' : 'Edit Staff',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: staffIdController,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Staff ID',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      enabled: !saving,
                      textCapitalization:
                          TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      enabled: !saving,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      enabled: !saving,
                      keyboardType:
                          TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: roleController,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Role / Designation',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: joiningDateController,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Joining Date',
                        hintText: 'DD/MM/YYYY',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      enabled: !saving,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      value: active,
                      onChanged: saving
                          ? null
                          : (value) {
                              setDialogState(() {
                                active = value;
                              });
                            },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          FocusScope.of(dialogBuilderContext).unfocus();
                          Navigator.pop(dialogContext);
                        },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving ? null : handleSave,
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    staffIdController.dispose();
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    roleController.dispose();
    joiningDateController.dispose();
    notesController.dispose();
  }
}

// ============================================================
// DIALOG: COMPLAINT
// ============================================================

Future<void> deleteCustomer(
  BuildContext parentContext,
  DocumentReference<Map<String, dynamic>> reference,
) async {
  final confirm = await showDeleteConfirmation(
    parentContext,
    'Remove this customer?',
  );

  if (confirm != true) return;

  try {
    await reference.delete();

    if (parentContext.mounted) {
      showMessage(
        'Customer removed.',
      );
    }
  } catch (e) {
    if (parentContext.mounted) {
      showMessage(
        'Remove failed: $e',
      );
    }
  }
}

// ============================================================
// DELETE STAFF
// ============================================================

Future<void> deleteStaff(
  BuildContext parentContext,
  DocumentReference<Map<String, dynamic>> reference,
) async {
  final confirm = await showDeleteConfirmation(
    parentContext,
    'Remove this staff member?',
  );

  if (confirm != true) return;

  try {
    await reference.delete();

    if (parentContext.mounted) {
      showMessage(
        'Staff removed.',
      );
    }
  } catch (e) {
    if (parentContext.mounted) {
      showMessage(
        'Remove failed: $e',
      );
    }
  }
}

// ============================================================
// COMMON WIDGETS
// ============================================================

class NumberField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool enabled;

  const NumberField({
    super.key,
    required this.label,
    required this.controller,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel({
    super.key,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(
          bottom: 8,
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 60,
              color: Colors.grey,
            ),
            const SizedBox(height: 15),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// HELPERS
// ============================================================

String number(dynamic value) {
  if (value == null) return '0';

  if (value is num) {
    return value.toInt().toString();
  }

  final parsed = int.tryParse(value.toString());

  return parsed?.toString() ?? '0';
}

int intValue(String value) {
  return int.tryParse(value.trim()) ?? 0;
}

String formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString();

  return '$day/$month/$year';
}

String formatDateTime(DateTime date) {
  final datePart = formatDate(date);
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$datePart $hour:$minute';
}

void showMessage(String message) {
  final messenger = scaffoldMessengerKey.currentState;
  if (messenger == null) return;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

Future<bool?> showDeleteConfirmation(
  BuildContext context,
  String message,
) {
  bool closing = false;

  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Confirm'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              if (closing) return;
              closing = true;
              Navigator.pop(
                dialogContext,
                false,
              );
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () {
              if (closing) return;
              closing = true;
              Navigator.pop(
                dialogContext,
                true,
              );
            },
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
}
