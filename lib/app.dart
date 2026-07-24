import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/theme.dart';
import 'features/home/home_screen.dart';
import 'features/review/review_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/vault/vault_browser_screen.dart';
import 'features/review/review_session_screen.dart';
import 'features/review/chat_screen.dart';
import 'features/home/home_provider.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/review',
          builder: (context, state) => const ReviewScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/vault-browser',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const VaultBrowserScreen(),
    ),
    GoRoute(
      path: '/review/start',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const ReviewSessionScreen(),
    ),
    GoRoute(
      path: '/review/chat',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final notes = state.uri.queryParameters['notes'];
        return ChatScreen(
          sessionType: 'free_chat',
          initialNoteIds: notes,
        );
      },
    ),
  ],
);

class NoteReviewApp extends StatelessWidget {
  const NoteReviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NoteReview',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(checkOverdueOnResumeProvider)();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(checkOverdueOnResumeProvider)();
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    int currentIndex;
    if (location.startsWith('/review')) {
      currentIndex = 1;
    } else if (location.startsWith('/settings')) {
      currentIndex = 2;
    } else {
      currentIndex = 0;
    }

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/');
            case 1:
              context.go('/review');
            case 2:
              context.go('/settings');
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz),
            label: '复习',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
