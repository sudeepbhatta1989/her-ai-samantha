import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/plan_screen.dart';
import 'screens/history_screen.dart';
import 'screens/jarvis_screen.dart';
import 'services/notification_service.dart';

// Global navigator key so NotificationService can route without BuildContext
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global key to the MainShell so notifications can switch tabs
final GlobalKey<MainShellState> mainShellKey = GlobalKey<MainShellState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch any Flutter framework errors that would otherwise white-screen silently
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('[Samantha] Flutter error: ${details.exceptionAsString()}');
    debugPrint(details.stack.toString());
  };

  // Initialize Firebase — wrapped so a config error never blocks app launch
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('[Samantha] Firebase init failed: $e');
  }

  // Initialize FCM — wrapped so it never blocks app launch
  try {
    final notificationService = NotificationService();
    await notificationService.initialize();
  } catch (e) {
    debugPrint('[Samantha] NotificationService init failed: $e');
  }

  runApp(const HerAIApp());
}

class HerAIApp extends StatelessWidget {
  const HerAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Use bundled Sora font directly — avoids google_fonts network fetch on launch
    final baseTheme = ThemeData.dark();

    return MaterialApp(
      title: 'Samantha',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C0C10),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00D4FF),
          secondary: Color(0xFF7C3AED),
        ),
        // Use bundled font — no network required, no crash risk
        textTheme: baseTheme.textTheme.apply(
          fontFamily: 'Sora',
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF13131A),
          indicatorColor: Color(0x2200D4FF),
        ),
      ),
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/home': (context) => MainShell(key: mainShellKey),
      },
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int _tab = 0;
  final _planKey = GlobalKey<PlanScreenState>();

  late final List<Widget> _screens = [
    const HomeScreen(),
    const ChatScreen(),
    PlanScreen(key: _planKey),
    const JarvisScreen(),
    const HistoryScreen(),
  ];

  /// Called by NotificationService to switch to a specific tab
  void switchTab(int index) {
    if (!mounted) return;
    setState(() => _tab = index);
    if (index == 2) _planKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 2) _planKey.currentState?.reload();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_none_rounded),
            selectedIcon: Icon(Icons.mic_rounded),
            label: 'Talk',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: 'Jarvis',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }
}
