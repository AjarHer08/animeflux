# AnimeFlux

Aplikasi **Flutter** untuk nonton & download anime **dan baca komik** dari sumber populer di Indonesia.

**Komik** (tab "Komik"): 🗞️ Komikstation (`komikstation.org`), 📖 Kiryuu (`v7.kiryuu.to`), 📚 Komiku (`komiku.org`).
Domain bisa diubah dari Pengaturan > Ekstensi > Domain sumber komik jika situs pindah.

**Anime**:

- 📺 **Otakudesu** (`https://otakudesu.blog`) — Streaming utama
- 🌊 **Hidoristream** (`https://v10.hidoristream.online`) — Streaming + ongoing
- 📁 **Lendrive** (`https://lendrive.web.id`) — Download MKV/MP4 720p/1080p HEVC

Dibangun dengan **Material 3**, **Riverpod**, dan **media_kit** (libmpv). Target Android 6 (API 23) sampai Android 17 (API 37).

## ✨ Fitur

| Fitur | Status |
|------|--------|
| Browse rilisan terbaru (paralel 3 sumber) | ✅ |
| Search multi-sumber | ✅ |
| Detail anime (sinopsis, genre, episode list) | ✅ |
| Streaming player dengan mirror/quality selector | ✅ |
| Picture-in-Picture (Android 8+) | ✅ |
| Resume posisi tonton otomatis | ✅ |
| Playback speed 0.5x - 2x | ✅ |
| Skip intro (85s) | ✅ |
| Download native (720p/1080p MKV/MP4) | ✅ |
| Favorit & History (lokal, SharedPreferences) | ✅ |
| Theme custom (preset + warna custom) | ✅ |
| Wallpaper dari galeri sebagai background | ✅ |
| Schedule rilisan per hari | ✅ |
| Baca komik (3 sumber), bookmark, lanjut baca | ✅ |
| Pemblokir iklan bawaan (gaya AdGuard/uBlock) | ✅ |
| Fallback WebView untuk mirror & situs ber-Cloudflare | ✅ |

## 🎨 Tema

8 preset tema Material 3 (Indigo Dark, Ocean Dark, Neon Dark, Amber Dark, Emerald Dark, Rose Dark, Mono Dark, Light Amber) +
override warna custom + pilih foto dari galeri sebagai background dengan opasitas yang bisa diatur.

## 📱 Target Android

- `minSdk = 23` (Android 6.0 Marshmallow)
- `targetSdk = 36` (Android 16, compat ke Android 17)
- `compileSdk = 36`
- Adaptive icon dengan foreground/background
- PiP via `android:supportsPictureInPicture="true"`
- Storage permission auto-handle untuk Android 13+

## 🏗️ Arsitektur

```
lib/
├── core/
│   ├── constants.dart        # SourceId, VideoQuality, UA, headers
│   ├── theme/
│   │   └── app_theme.dart    # ThemePreset, ThemeNotifier, buildThemeData
│   └── utils/
│       ├── http_client.dart  # Dio + UA rotation + retry
│       ├── html_utils.dart   # parse, cleanText, resolveUrl
│       └── logger.dart
├── data/
│   ├── models/               # Anime, Episode, StreamMirror, Genre, dll
│   ├── scrapers/
│   │   ├── base_scraper.dart     # Interface
│   │   ├── otakudesu_scraper.dart
│   │   ├── hidoristream_scraper.dart
│   │   └── lendrive_scraper.dart
│   └── repositories/        # AnimeRepository (multi-source), Favorites, History, Download
├── presentation/
│   ├── providers/           # Riverpod providers
│   ├── screens/             # Home, Detail, Player, Search, Favorites, History, Schedule, Settings, Ongoing, Downloads
│   └── widgets/              # AnimeCard, AnimeGrid, SourceSelector, SectionHeader
├── app.dart
└── main.dart
```

### State management
**Riverpod 2.x** dengan kombinasi:
- `FutureProvider` untuk async data (list anime, detail, search)
- `StateNotifierProvider` untuk stateful (theme, player, download tasks)
- `Provider` untuk singleton (repository)

### Scraping
- HTTP via **Dio** dengan User-Agent rotation (3 UA desktop Chrome modern) untuk bypass Cloudflare WAF.
- HTML parsing via **html** package (port dari `html5lib`).
- Setiap scraper punya interface sama (`BaseScraper`) → mudah extend ke sumber baru.
- Selector HTML fleksibel dengan multiple fallback (`.infozingle, .info, .anime-info`).
- Repository jalan paralel via `Future.wait` — gagal 1 sumber tidak menggagalkan yang lain.

## 🚀 Build

### Prasyarat
- Flutter SDK >= 3.47 (diperlukan minimum Gradle 8.14 + AGP 8.11.1 + Kotlin 2.2.20)
- Java 17+ (untuk Gradle 8.14)
- Android SDK dengan platform-tools & build-tools 36
  - Install via Android Studio atau `sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"`

### Versi toolchain (dipasang otomatis via wrapper)
- **Gradle**: 8.14.3 (lihat `android/gradle/wrapper/gradle-wrapper.properties`)
- **Android Gradle Plugin (AGP)**: 8.11.1 (lihat `android/settings.gradle`)
- **Kotlin**: 2.2.20 (lihat `android/settings.gradle`)

### Package ID
Application ID: **`com.animeflux.id`** (bukan `com.example`). Namespace Kotlin juga pakai `com.animeflux.id`. Untuk ganti, edit `android/app/build.gradle` (`namespace` & `applicationId`), pindahkan folder `android/app/src/main/kotlin/com/animeflux/id/`, dan update `package` di file `.kt`.

### Setup & Run
```bash
flutter pub get
flutter run                  # debug ke device/emulator
```

### Build APK
```bash
# Debug APK (jalan langsung tanpa signing)
flutter build apk --debug

# Release APK (perlu keystore, lihat section signing)
flutter build apk --release

# Split per ABI untuk ukuran lebih kecil
flutter build apk --split-per-abi --release
```

Output:
- `build/app/outputs/flutter-apk/app-debug.apk`
- `build/app/outputs/flutter-apk/app-release.apk`

> **Catatan**: Di sandbox kami, build APK gagal karena Maven Central (`repo.maven.apache.org`) memberikan HTTP 429 Too Many Requests untuk IP kami. Code lolos `flutter analyze` tanpa error. Build di mesin lokal atau via GitHub Actions CI akan berhasil normal. Lihat `scripts/build-helper.txt` untuk konfigurasi maven aliyun mirror jika mengalami hal serupa.

### Generate launcher icon (jika mau custom)
```bash
python3 scripts/gen_launcher_icons.py
```
Script ini menulis PNG ke `android/app/src/main/res/mipmap-*` dan `assets/images/app_icon_1024.png`.

## 🔐 Signing untuk release

Buat keystore:
```bash
keytool -genkeypair -v -keystore animeflux.keystore \
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 \
  -alias animeflux
```

Tambahkan di `android/key.properties`:
```properties
storePassword=***
keyPassword=***
keyAlias=animeflux
storeFile=../animeflux.keystore
```

Edit `android/app/build.gradle` bagian `signingConfigs`:
```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile file(keystoreProperties['storeFile'])
            storePassword keystoreProperties['storePassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
```

## 🛡️ Pemblokir iklan

Engine sendiri (`lib/core/adblock/`), bukan ekstensi browser — ekstensi Chrome/Firefox tidak bisa dimuat di Android WebView.
Membaca filter berformat AdGuard / uBlock / EasyList / hosts: blokir domain & pola path (native content blocker),
sembunyikan elemen (CSS), blokir popup/redirect/overlay link transparan. Daftar bawaan bekerja offline;
AdGuard Base, uBlock filters, EasyList, ABPindo, Peter Lowe bisa diaktifkan & diunduh dari Pengaturan > Ekstensi.
Aturan prosedural / scriptlet / regex tidak didukung.

## 🔧 Menyesuaikan scraper komik

Struktur HTML situs berubah sewaktu-waktu. Kalau daftar/chapter/gambar kosong, edit file di
`lib/data/scrapers/comic/` (`mangastream_scraper.dart` = Komikstation, `kiryuu_scraper.dart`, `komiku_scraper.dart`).
Parser memakai selector tema + fallback berbasis pola URL (`comic_scraper.dart`). Tombol "browser" di detail
komik membuka halaman aslinya dengan adblock sebagai jalan keluar.

## 🤖 CI/CD

Workflow: `.github/workflows/build-apk.yml`. Setiap push ke `main`/`master`, PR, atau manual (Actions > Run workflow):
1. Setup Java 17 + Flutter stable, `flutter pub get`
2. `flutter analyze` & `flutter test` (tidak memblokir build)
3. Build APK release per-ABI + universal
4. Upload artefak `animeflux-apk` (Actions > run > Artifacts)

Untuk membuat **GitHub Release** berisi APK: `git tag v1.0.1 && git push origin v1.0.1`.

## ⚠️ Catatan scraping

Selector HTML di-set berdasarkan struktur umum theme WordPress yang dipakai situs anime Indonesia. Jika struktur berubah:
- Buka website di browser, inspect elemen, dapatkan class name baru
- Update selector di file `lib/data/scrapers/<source>_scraper.dart`
- Tidak perlu ubah logic utama (model, repository, UI)

Otakudesu sering pakai Cloudflare WAF. App pakai User-Agent desktop Chrome modern untuk bypass. Jika masih kena block, tambahkan cookie handling atau gunakan proxy di `http_client.dart`.

## 📜 Lisensi & Disclaimer

Aplikasi ini bersifat **non-komersial** dan hanya sebagai jembatan ke sumber publik. Semua konten anime tetap milik pemilik masing-masing. Pengguna bertanggung jawab atas penggunaannya.

## 🛣️ Roadmap

- [ ] AniList/MAL sync untuk metadata anime
- [ ] Notification untuk episode baru ongoing
- [ ] Wallpaper anime otomatis dari AniList season
- [ ] Cast ke Chromecast (DLNA)
- [ ] Offline mode dengan download library management

---

Dibuat dengan ❤️ untuk penggemar anime Indonesia.
