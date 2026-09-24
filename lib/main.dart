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


class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sumitra HP Gas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.security),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SecurityProfileScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: const Center(
        child: Text('PIN Security Verified - Dashboard'),
      ),
    );
  }
}

class InventoryActivityScreen extends StatelessWidget {
  const InventoryActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory Activity')),
      body: const Center(child: Text('Activity logs')),
    );
  }
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

