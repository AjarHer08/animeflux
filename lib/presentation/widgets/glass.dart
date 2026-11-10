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
class GlassLayer extends StatelessWidget {
  final Widget? child;
  final bool top;
  final bool enabled;
  const GlassLayer({super.key, this.child, this.top = false, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    if (!enabled) {
      return ColoredBox(color: scheme.surfaceContainer, child: child);
    }
    final edge = Border(
      top: top ? BorderSide.none : BorderSide(color: Colors.white.withOpacity(dark ? 0.14 : 0.55)),
      bottom: top ? BorderSide(color: Colors.white.withOpacity(dark ? 0.10 : 0.45)) : BorderSide.none,
    );
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: edge,
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                scheme.surface.withOpacity(dark ? 0.55 : 0.62),
                scheme.surfaceContainerHigh.withOpacity(dark ? 0.35 : 0.42),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// NavigationBar dengan latar kaca.
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
    return GlassLayer(
      enabled: enabled,
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations,
        labelBehavior: labelBehavior,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
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
