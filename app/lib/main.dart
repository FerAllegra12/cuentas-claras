import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/supabase_config.dart';
import 'ui/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  if (SupabaseConfig.isSet) {
    await Supabase.initialize(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);
  }
  runApp(const CuentasClarasApp());
}

class CuentasClarasApp extends StatelessWidget {
  const CuentasClarasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cuentas Claras',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F6E56)),
        useMaterial3: true,
      ),
      home: SupabaseConfig.isSet ? const AuthGate() : const _FaltaConfig(),
    );
  }
}

class _FaltaConfig extends StatelessWidget {
  const _FaltaConfig();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Falta conectar con Supabase.\n\nCompilá con SUPABASE_URL y SUPABASE_ANON_KEY (ver docs/ARQUITECTURA.md).',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
