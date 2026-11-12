import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  final _pass2 = TextEditingController();
  bool _ver = false;
  bool _registro = false;
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _name.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_registro && _pass.text != _pass2.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    if (_registro && _pass.text.length < 6) {
      setState(() => _error = 'La contraseña tiene que tener al menos 6 caracteres.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
    });
    final auth = Supabase.instance.client.auth;
    try {
      if (_registro) {
        await auth.signUp(
          email: _email.text.trim(),
          password: _pass.text,
          data: {'name': _name.text.trim()},
        );
      } else {
        await auth.signInWithPassword(email: _email.text.trim(), password: _pass.text);
      }
    } on AuthException catch (e) {
      final m = e.message;
      setState(() => _error = (m.contains('host lookup') || m.contains('SocketException'))
          ? 'No pudimos conectar. Revisá tu conexión.'
          : m);
    } catch (_) {
      setState(() => _error = 'No pudimos conectar. Revisá tu conexión.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Cuentas Claras', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 24),
                  if (_registro) ...[
                    TextField(controller: _name, decoration: const InputDecoration(labelText: 'Tu nombre')),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Mail'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: !_ver,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      suffixIcon: IconButton(
                        icon: Icon(_ver ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _ver = !_ver),
                      ),
                    ),
                  ),
                  if (_registro) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass2,
                      obscureText: !_ver,
                      decoration: const InputDecoration(labelText: 'Repetir contraseña'),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _cargando ? null : _enviar,
                    child: Text(_registro ? 'Crear cuenta' : 'Entrar'),
                  ),
                  TextButton(
                    onPressed: _cargando ? null : () => setState(() => _registro = !_registro),
                    child: Text(_registro ? 'Ya tengo cuenta' : 'Crear una cuenta'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
