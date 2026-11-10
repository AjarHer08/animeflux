# Changelog

## 1.1.4
- Otakudesu: perbaikan error merah di detail/episode ("(dynamic) => dynamic is not a subtype of (String) => bool"): daftar episode kini bertipe Element.
- Adblock player: respons VAST/VMAP diganti VAST kosong (fetch & XHR), video iklan pendek dipercepat sampai selesai saat teks "Iklan ini akan berakhir" muncul, tombol Skip diklik otomatis.
- Akun admin lokal: masuk dengan nama `admin` + kode admin (lihat `kAdminCode` di lib/core/constants.dart). Admin otomatis berstatus VIP.

## 1.1.3
- Komik: tiap sumber (Komikstation, Kiryuu, Komiku) kini punya kategori Semua / Manga / Manhwa / Manhua untuk Terbaru & Populer.
- Komik: perbaikan error "Gagal memuat detail ... (dynamic) => dynamic is not a subtype of (String) => bool" (rantai map/where diganti loop bertipe eksplisit).

## 1.1.2
- Otakudesu: pencarian memakai struktur hasil `ul.chivsrc`; Completed memakai path `/complete-anime/`; parser ongoing/completed dan daftar episode diperbaiki.
- Login: hanya akun di dalam aplikasi. Login situs sumber (Otakudesu/Hidoristream/Lendrive) dihapus.
- Liquid glass: nav bar jadi kapsul kaca melayang dengan blur + kilau sehingga terlihat.
- Hidoristream: Ongoing/Completed memakai /anime/?status=ongoing|completed (paging ?page=N).
- Adblock di mirror/stream: pemblokiran request Android via shouldInterceptRequest (contentBlockers hanya jalan di iOS) + auto-skip tombol "Skip" iklan.

# Perubahan

## 1.1.1
- **Wallpaper kustom tidak tampil**: wallpaper galeri dibaca sebagai asset (`Image.asset`) padahal itu file di perangkat -> sekarang `Image.file`. Scaffold dibuat transparan saat wallpaper aktif dan wallpaper dipasang untuk semua halaman (lewat `MaterialApp.builder`). File disalin ke penyimpanan app supaya tidak hilang saat cache dibersihkan.

## 1.1.0
- **Scroll**: kartu di Beranda tidak lagi ikut "tergeser" sendiri saat halaman digulir (grid di dalam halaman tidak punya scroll sendiri lagi).
- **Mirror Otakudesu dobel**: iframe "Default" tidak lagi muncul bersama daftar mirror; dipakai sebagai cadangan kalau resolve AJAX gagal.
- **Hidoristream tidak terbaca**: parser kartu generik (tanpa bergantung class CSS), gambar lazy-load, fallback WebView untuk halaman JS/Cloudflare, fallback daftar episode & mirror, paginasi Ongoing/Completed.
- **Login/VIP**: login situs sumber lewat WebView (cookie disimpan & dipakai scraper), pesan jelas kalau situs meminta login/VIP, profil akun lokal.
- **Liquid glass**: efek kaca di bar navigasi & app bar, bisa dimatikan di Pengaturan > Tema.
- **Cek pembaruan** lewat GitHub Releases (otomatis maks 1x/12 jam + tombol di Pengaturan > Tentang).
- **Ongoing & Completed**: tombol di Beranda + "Lihat semua".

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
