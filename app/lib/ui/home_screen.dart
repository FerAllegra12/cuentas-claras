import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cargar_screen.dart';

/// Pantalla provisoria: confirma que el login y la base andan.
/// Las pestañas reales (Inicio, Cargar, Gastos, Grupos, Contactos) se arman sobre esto.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<String> _nombre() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser!.id;
    final row = await client.from('profiles').select('display_name').eq('id', uid).single();
    return row['display_name'] as String;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuentas Claras'),
        actions: [
          IconButton(
            tooltip: 'Salir',
            icon: const Icon(Icons.logout),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: FutureBuilder<String>(
          future: _nombre(),
          builder: (context, snap) {
            if (snap.hasError) return Text('Error leyendo tu perfil: ${snap.error}');
            if (!snap.hasData) return const CircularProgressIndicator();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Hola, ${snap.data}.', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Cargar resumen'),
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => const CargarScreen())),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
