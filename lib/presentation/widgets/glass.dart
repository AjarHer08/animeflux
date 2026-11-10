/// Efek "liquid glass": blur latar + tint translucent + kilau tepi tipis.
/// Dipakai di bar navigasi bawah dan app bar. Bisa dimatikan di Pengaturan.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart' show sharedPreferencesInstance;

const _kGlassKey = 'glass_enabled_v1';

class GlassNotifier extends StateNotifier<bool> {
  GlassNotifier() : super(_load());

  static bool _load() {
    try {
      return sharedPreferencesInstance.getBool(_kGlassKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> set(bool v) async {
    state = v;
    try {
      await sharedPreferencesInstance.setBool(_kGlassKey, v);
    } catch (_) {}
  }
}

final glassEnabledProvider =
    StateNotifierProvider<GlassNotifier, bool>((ref) => GlassNotifier());

/// Lapisan kaca. [top] = true untuk bar di atas layar (garis tepi di bawah).
/// [radius] > 0 membuat kaca berbentuk kapsul melayang (dipakai nav bar).
class GlassLayer extends StatelessWidget {
  final Widget? child;
  final bool top;
  final bool enabled;
  final double radius;
  const GlassLayer({
    super.key,
    this.child,
    this.top = false,
    this.enabled = true,
    this.radius = 0,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final shape = BorderRadius.circular(radius);
    if (!enabled) {
      return DecoratedBox(
        decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: shape),
        child: child,
      );
    }
    final white = Colors.white;
    final floating = radius > 0;
    final decoration = BoxDecoration(
      borderRadius: shape,
      // Kilau diagonal: terang di sudut kiri atas, makin bening ke bawah.
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          white.withOpacity(dark ? 0.20 : 0.55),
          white.withOpacity(dark ? 0.06 : 0.22),
          scheme.primary.withOpacity(dark ? 0.08 : 0.10),
        ],
        stops: const [0.0, 0.55, 1.0],
      ),
      border: floating
          ? Border.all(color: white.withOpacity(dark ? 0.30 : 0.75), width: 1.1)
          : Border(
              top: top ? BorderSide.none : BorderSide(color: white.withOpacity(dark ? 0.22 : 0.6)),
              bottom: top ? BorderSide(color: white.withOpacity(dark ? 0.18 : 0.5)) : BorderSide.none,
            ),
      boxShadow: floating
          ? [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 8))]
          : null,
    );
    final glass = ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(decoration: decoration, child: child),
      ),
    );
    // Bayangan harus di luar ClipRRect supaya tidak terpotong.
    if (!floating) return glass;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: glass,
    );
  }
}

/// NavigationBar kapsul kaca yang melayang di atas konten, jadi konten yang
/// di-scroll terlihat membaur di balik kaca.
class GlassNavigationBar extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;
  final NavigationDestinationLabelBehavior? labelBehavior;

  const GlassNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.labelBehavior,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(glassEnabledProvider);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: GlassLayer(
          enabled: enabled,
          radius: 30,
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              indicatorColor: scheme.primary.withOpacity(0.35),
              height: 66,
            ),
            child: NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: destinations,
              labelBehavior: labelBehavior,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
            ),
          ),
        ),
      ),
    );
  }
}

/// AppBar dengan latar kaca. Parameter sama dengan [AppBar] yang dipakai app.
class GlassAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;

  const GlassAppBar({super.key, this.title, this.actions, this.leading, this.bottom});

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(glassEnabledProvider);
    return AppBar(
      title: title,
      actions: actions,
      leading: leading,
      bottom: bottom,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: GlassLayer(top: true, enabled: enabled),
    );
  }
}
