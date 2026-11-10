/// Akun & Login: profil lokal AnimeFlux (login hanya di dalam aplikasi;
/// situs sumber tidak punya login).
library;

import 'package:flutter/material.dart';

import '../../core/utils/account_service.dart';
import '../widgets/glass.dart';

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
        listenable: account,
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
            ],
          );
        },
      ),
    );
  }
}
