/// 应用根:主题与路由
///
/// 浅色与深色是同一套设计的两个主题,跟随系统。
library;

import 'package:flutter/material.dart';

import 'design/theme.dart';
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
    return MaterialApp(
      title: 'Chher',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomePage(),
      routes: {
        '/login': (_) => const LoginPage(),
        '/messages': (_) => const MessagesPage(),
        '/me': (_) => const MePage(),
        '/favorites': (_) => const FavoritesPage(),
        '/settings': (_) => const SettingsPage(),
        '/logs': (_) => const LogPage(),
      },
    );
  }
}
