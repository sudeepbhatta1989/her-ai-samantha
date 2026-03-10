import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../main.dart';

// Background handler — must be a top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM-BG] Background message: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _LAMBDA_URL =
      'https://aybg83gr69.execute-api.ap-south-1.amazonaws.com/prod/chat';
  static const String _USER_ID = 'user1';

  static const int _tabHome    = 0;
  static const int _tabTalk    = 1;
  static const int _tabPlan    = 2;
  static const int _tabJarvis  = 3;
  static const int _tabHistory = 4;

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  Future<void> initialize() async {
    // Register background handler first — safe before Firebase is fully ready
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request iOS permission — wrapped so a denial never crashes the app
    try {
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      ).timeout(const Duration(seconds: 10));
      debugPrint('[FCM] Permission: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('[FCM] Permission request failed (non-fatal): $e');
      // App still works — just no notifications until user grants permission
      return;
    }

    // iOS foreground display options
    try {
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('[FCM] setForegroundNotificationPresentationOptions failed: $e');
    }

    // Get FCM token and save it — non-fatal if this fails
    try {
      final token = await _fcm.getToken()
          .timeout(const Duration(seconds: 10));
      if (token != null) {
        debugPrint('[FCM] Token: $token');
        await _saveFcmToken(token);
      }
      _fcm.onTokenRefresh.listen(_saveFcmToken);
    } catch (e) {
      debugPrint('[FCM] Token fetch failed (non-fatal): $e');
    }

    // Message listeners — all non-fatal
    try {
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
      final initial = await _fcm.getInitialMessage()
          .timeout(const Duration(seconds: 5));
      if (initial != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          _handleNotificationTap(initial);
        });
      }
    } catch (e) {
      debugPrint('[FCM] Message listener setup failed (non-fatal): $e');
    }
  }

  Future<void> _saveFcmToken(String token) async {
    try {
      await http.post(
        Uri.parse(_LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: '{"userId":"$_USER_ID","action":"save_fcm_token","token":"$token"}',
      ).timeout(const Duration(seconds: 10));
      debugPrint('[FCM] Token saved');
    } catch (e) {
      debugPrint('[FCM] Token save error (non-fatal): $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    try {
      final title = message.notification?.title ?? 'Samantha';
      final body  = message.notification?.body  ?? '';
      final tab   = message.data['tab'] ?? 'home';
      debugPrint('[FCM] Foreground: $title — $body (tab: $tab)');
      _switchTab(tab);

      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('$title: $body'),
          backgroundColor: const Color(0xFF1A1A2E),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      debugPrint('[FCM] Foreground handler error: $e');
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    try {
      final tab = message.data['tab'] ?? 'home';
      debugPrint('[FCM] Notification tapped, routing to tab: $tab');
      Future.delayed(const Duration(milliseconds: 300), () => _switchTab(tab));
    } catch (e) {
      debugPrint('[FCM] Tap handler error: $e');
    }
  }

  void _switchTab(String tab) {
    final index = {
      'home':    _tabHome,
      'talk':    _tabTalk,
      'plan':    _tabPlan,
      'jarvis':  _tabJarvis,
      'history': _tabHistory,
    }[tab] ?? _tabHome;
    mainShellKey.currentState?.switchTab(index);
  }
}
