/// Entry point aplikasi AnimeFlux.
library;

import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/adblock/adblock_engine.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/logger.dart';
import 'presentation/providers/download_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init SharedPreferences & expose via global getter
  final prefs = await SharedPreferences.getInstance();
  initSharedPreferences(prefs);

  // Init media_kit (libmpv backend)
  MediaKit.ensureInitialized();

  // Kegagalan init non-kritis tidak boleh membuat app gagal start.
  try {
    await FlutterDownloader.initialize(debug: false);
  } catch (e) {
    logger.e('FlutterDownloader.initialize gagal: $e');
  }
  try {
    await AdblockEngine.instance.init(prefs);
  } catch (e) {
    logger.e('Adblock init gagal: $e');
  }

  final container = ProviderContainer();
  try {
    setupDownloadCallback(container);
  } catch (e) {
    logger.e('setupDownloadCallback gagal: $e');
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: const AnimeFluxApp(),
  ));
}
