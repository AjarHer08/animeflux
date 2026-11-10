# Perubahan

## Bug yang diperbaiki
- **Tombol download tidak ada**: link download di-parse tapi tidak pernah dimasukkan ke hasil, dan UI tidak punya tombol download. Sekarang `Episode.downloads` terisi, ada ikon download di tiap episode + di player.
- **Mirror error**: decode mirror Otakudesu rusak (kode `Uri.dataFromString` tak berfungsi); header `Accept-Encoding: br` membuat HTML tak terbaca (Dart tak bisa decode brotli); link file-host dianggap video langsung. Sekarang: iframe default + AJAX mirror, resolve bertingkat, fallback WebView ber-adblock.
- **Crash saat start**: `FlutterDownloader.registerCallback` dengan closure → diganti callback top-level + port.
- Download manager: provider null-safe, status/progres nyata, Scaffold + back button, folder dibuat otomatis.
- Player: listener dobel, setState setelah dispose, slider melebihi max, orientasi terkunci, overflow di landscape, ikon play/pause basi.
- Error sumber tidak lagi ditelan (daftar kosong misterius) → tampil pesan + coba lagi.
- Android: hapus `GeneratedPluginRegistrant` yang ikut ter-commit + registrasi plugin ganda, `<uses-sdk>` di manifest, service palsu, `configureondemand`.

## Fitur baru
- Tab **Komik**: Komikstation, Kiryuu, Komiku (terbaru/populer/cari/bookmark/lanjut baca, reader vertikal).
- **Pemblokir iklan** (`lib/core/adblock`), pengaturan di Pengaturan > Ekstensi.
- Fallback WebView headless untuk situs ber-Cloudflare.
- CI: APK per-ABI + universal, release otomatis untuk tag `v*`.
