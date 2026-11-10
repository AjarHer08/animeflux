/// Root widget AnimeFlux — tema + router sederhana.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/main_shell.dart';

class AnimeFluxApp extends ConsumerWidget {
  const AnimeFluxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: buildThemeData(theme),
      builder: (context, child) =>
          ThemedBackground(child: child ?? const SizedBox.shrink()),
      home: const MainShell(),
    );
  }
}
