import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'services/player_service.dart';

import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppTheme.isDesktopOs) await _setUpWindow();
  await PlayerService.instance.initialize();
  runApp(const MyApp());
}

Future<void> _setUpWindow() async {
  await windowManager.ensureInitialized();
  final options = WindowOptions(
    size: const Size(1120, 740),
    minimumSize: const Size(900, 600),
    center: true,
    title: 'Playlist MP3',
    // macOS draws its traffic lights over our own sidebar; Windows and Linux
    // keep their native title bars.
    titleBarStyle: Platform.isMacOS
        ? TitleBarStyle.hidden
        : TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Playlist MP3',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}
