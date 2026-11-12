import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/statement_parser.dart';
import '../data/pdf_reader.dart';

/// Elegís el PDF del resumen, la app lo lee y te muestra qué entendió.
/// Todavía no guarda nada: primero verificamos que la lectura sea correcta.
class CargarScreen extends StatefulWidget {
  const CargarScreen({super.key});

  @override
  State<CargarScreen> createState() => _CargarScreenState();
}

class _CargarScreenState extends State<CargarScreen> {
  StatementResult? _res;
  String? _archivo;
  String? _error;
  bool _leyendo = false;

  Future<void> _elegir() async {
    setState(() {
      _error = null;
      _leyendo = true;
    });
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (pick == null || pick.files.isEmpty) {
        setState(() => _leyendo = false);
        return;
      }
      final f = pick.files.first;
      final bytes = f.bytes;
      if (bytes == null) throw 'No pude abrir el archivo.';
      final lines = pdfToLines(bytes);
      final res = parseStatement(lines);
      setState(() {
        _res = res;
        _archivo = f.name;
        _leyendo = false;
      });
    } catch (e) {
      setState(() {
        _error = 'No pude leer ese PDF: $e';
        _leyendo = false;
      });
    }
  }

  String _plata(int cents, String cur) => cur == 'USD' ? 'US\$ ${formatArs(cents).replaceAll('\$', '').trim()}' : formatArs(cents);

  @override
  Widget build(BuildContext context) {
    final r = _res;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Cargar resumen')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            icon: const Icon(Icons.upload_file),
            label: Text(_leyendo ? 'Leyendo…' : 'Elegir PDF del resumen'),
            onPressed: _leyendo ? null : _elegir,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: cs.error)),
          ],
          if (r != null) ...[
            const SizedBox(height: 16),
            Text(_archivo ?? '', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(r.label, style: Theme.of(context).textTheme.titleLarge),
            if (r.closeISO != null) Text('Cierre ${r.closeISO} · Vencimiento ${r.dueISO}'),
            const SizedBox(height: 12),
            Card(
              color: r.ok ? cs.primaryContainer : cs.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: r.ok
                    ? Text('✓ La suma cierra con el total del resumen (${formatArs(r.sumArs)}).')
                    : Text(['No cierra, no se puede cargar así:', ...r.problems].join('\n')),
              ),
            ),
            const SizedBox(height: 12),
            Text('${r.lines.length} consumos', style: Theme.of(context).textTheme.titleMedium),
            for (final l in r.lines)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(l.desc),
                subtitle: Text('${l.date}${l.cuota != null ? ' · Cuota ${l.cuota} de ${l.total}' : ''}'),
                trailing: Text(_plata(l.amountCents, l.currency)),
              ),
            if (r.refunds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${r.refunds.length} ajustes y reembolsos', style: Theme.of(context).textTheme.titleMedium),
              for (final l in r.refunds)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.desc),
                  subtitle: Text(l.date),
                  trailing: Text(_plata(l.amountCents, l.currency)),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
