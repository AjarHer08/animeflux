/// Akun & Login: profil lokal AnimeFlux + login ke situs sumber.
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/utils/account_service.dart';
import '../../core/utils/session_store.dart';
import '../widgets/glass.dart';
import 'site_login_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final account = AccountService.instance;
    return Scaffold(
      appBar: const GlassAppBar(title: Text('Akun & Login')),
      body: ListenableBuilder(
        listenable: Listenable.merge([account, SessionStore.instance]),
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Akun AnimeFlux',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (!account.isLoggedIn) ...[
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nama'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email (opsional)'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    if (_name.text.trim().isEmpty) return;
                    await account.login(name: _name.text, email: _email.text);
                  },
                  child: const Text('Masuk'),
                ),
                const SizedBox(height: 4),
                Text('Profil disimpan di perangkat ini saja.',
                    style: TextStyle(color: scheme.outline, fontSize: 12)),
              ] else
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(account.name ?? ''),
                    subtitle: Text(
                      [
                        if ((account.email ?? '').isNotEmpty) account.email!,
                        account.isVip ? 'Status: VIP' : 'Status: Gratis',
                      ].join(' • '),
                    ),
                    trailing: TextButton(
                      onPressed: account.logout,
                      child: const Text('Keluar'),
                    ),
                  ),
                ),
              if (account.isLoggedIn && !account.isVip)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'VIP AnimeFlux belum tersedia: butuh server akun yang belum terhubung.',
                    style: TextStyle(color: scheme.outline, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 24),
              Text('Login situs sumber',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Dipakai kalau situs meminta login/VIP untuk membuka episode atau download.',
                style: TextStyle(color: scheme.outline, fontSize: 12),
              ),
              const SizedBox(height: 8),
              for (final s in SourceId.values)
                Card(
                  child: ListTile(
                    leading: Icon(
                      SessionStore.instance.isLoggedIn(s) ? Icons.lock_open : Icons.lock_outline,
                      color: SessionStore.instance.isLoggedIn(s) ? scheme.primary : null,
                    ),
                    title: Text(s.label),
                    subtitle: Text(SessionStore.instance.isLoggedIn(s) ? 'Sesi tersimpan' : 'Belum masuk'),
                    trailing: SessionStore.instance.isLoggedIn(s)
                        ? TextButton(
                            onPressed: () => SessionStore.instance.logout(s),
                            child: const Text('Keluar'),
                          )
                        : FilledButton.tonal(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => SiteLoginScreen(source: s)),
                            ),
                            child: const Text('Masuk'),
                          ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
