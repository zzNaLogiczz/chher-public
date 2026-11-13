/// 应用根:主题与路由
///
/// 浅色与深色是同一套设计的两个主题,按外观偏好切换。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design/motion.dart';
import 'design/theme.dart';
import 'design/system_ui.dart';
import 'design/reading.dart';
import 'di.dart';
import 'pages/favorites_page.dart';
import 'pages/home_page.dart';
import 'pages/log_page.dart';
import 'pages/login_page.dart';
import 'pages/me_page.dart';
import 'pages/messages_page.dart';
import 'pages/settings_page.dart';

class ChhApp extends StatelessWidget {
  const ChhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ReadingScope(
      controller: readingPrefs,
      child: ListenableBuilder(
        listenable: appearance,
        builder: (context, _) => MaterialApp(
          title: 'Chher',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light, appearance.style),
          darkTheme: buildAppTheme(Brightness.dark, appearance.style),
          themeMode: appearance.mode.themeMode,
          themeAnimationDuration: AppMotion.revealDuration,
          themeAnimationCurve: AppMotion.revealCurve,
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: AppSystemUi.forBrightness(Theme.of(context).brightness),
            child: child!,
          ),
          home: const HomePage(),
          routes: {
            '/login': (_) => const LoginPage(),
            '/messages': (_) => const MessagesPage(),
            '/me': (_) => const MeFallbackPage(),
            '/favorites': (_) => const FavoritesPage(),
            '/settings': (_) => const SettingsPage(),
            '/logs': (_) => const LogPage(),
          },
        ),
      ),
    );
  }
}
