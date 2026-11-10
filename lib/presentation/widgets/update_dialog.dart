/// Dialog pembaruan + helper "Cek pembaruan" yang dipakai Settings dan startup.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/update_service.dart';

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Versi ${info.latestVersion} tersedia'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versi kamu: ${info.currentVersion}'),
            if (info.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(info.notes, maxLines: 14, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Nanti')),
        FilledButton.icon(
          icon: const Icon(Icons.download),
          label: const Text('Unduh'),
          onPressed: () {
            launchUrl(Uri.parse(info.downloadUrl), mode: LaunchMode.externalApplication);
            Navigator.pop(ctx);
          },
        ),
      ],
    ),
  );
}

/// Cek manual: selalu beri umpan balik (sudah terbaru / gagal / ada update).
Future<void> checkForUpdateManually(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Memeriksa pembaruan…')));
  try {
    final info = await UpdateService.check();
    messenger.hideCurrentSnackBar();
    if (!context.mounted) return;
    if (info.hasUpdate) {
      await showUpdateDialog(context, info);
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text('Sudah versi terbaru (${info.currentVersion}).'),
      ));
    }
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Gagal cek pembaruan: $e')));
  }
}
