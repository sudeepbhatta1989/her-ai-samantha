// lib/services/identity_service.dart
//
// For a personal app with no login screen.
// Gets (or creates) a stable Firebase UID automatically.
// Drop into app/lib/services/ and call IdentityService.uid anywhere.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IdentityService {
  static final IdentityService _i = IdentityService._();
  static IdentityService get instance => _i;
  IdentityService._();

  static const String _uidKey = 'samantha_personal_uid';

  // ── OPTION A (recommended): hardcoded UID from setup_uid_and_upload.bat
  // After running that bat, it prints "Your Firebase UID: xxxx"
  // Paste it here and you're done forever.
  static const String _hardcodedUid = 'samantha_personal_user'; // ← paste UID here e.g. 'samantha_personal_user'

  String? _cachedUid;

  /// Returns the stable UID for this personal app.
  /// Priority: hardcoded → stored → anonymous sign-in
  Future<String> get uid async {
    if (_cachedUid != null) return _cachedUid!;

    // 1. Use hardcoded UID if set
    if (_hardcodedUid.isNotEmpty) {
      _cachedUid = _hardcodedUid;
      return _hardcodedUid;
    }

    // 2. Return already signed-in user
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) {
      _cachedUid = current.uid;
      return current.uid;
    }

    // 3. Check locally stored UID from previous anonymous sign-in
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_uidKey);
    if (stored != null && stored.isNotEmpty) {
      // Sign in anonymously and verify it matches (or just use stored)
      try {
        final result = await FirebaseAuth.instance.signInAnonymously();
        _cachedUid = result.user!.uid;
        await prefs.setString(_uidKey, _cachedUid!);
        return _cachedUid!;
      } catch (_) {
        _cachedUid = stored;
        return stored;
      }
    }

    // 4. First run: sign in anonymously, store the UID permanently
    final result = await FirebaseAuth.instance.signInAnonymously();
    _cachedUid = result.user!.uid;
    await prefs.setString(_uidKey, _cachedUid!);
    return _cachedUid!;
  }

  /// Synchronous getter — only works after uid has been awaited once
  String get uidSync => _cachedUid ?? _hardcodedUid;
}
