import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../core/statement_parser.dart';

/// Saca las líneas de texto de un PDF, página por página, sin internet ni IA.
/// Usa PDFium (el mismo motor de Chrome), que lee casi cualquier PDF.
Future<List<String>> pdfToLines(Uint8List bytes) async {
  final doc = await PdfDocument.openData(bytes);
  try {
    final out = <String>[];
    for (final page in doc.pages) {
      // dynamic a propósito: así no depende de si la librería devuelve null o no.
      final dynamic text = await page.loadText();
      final items = <TextItem>[];
      final dynamic frags = text?.fragments;
      if (frags != null) {
        for (final dynamic f in frags) {
          final dynamic b = f.bounds; // coordenadas PDF: y crece hacia arriba
          final left = (b.left as num).toDouble();
          final right = (b.right as num).toDouble();
          final top = (b.top as num).toDouble();
          final bottom = (b.bottom as num).toDouble();
          final y = top > bottom ? top : bottom;
          items.add(TextItem(f.text as String, left, y, right - left));
        }
      }
      out.addAll(linesFromItems(items));
    }
    return out;
  } finally {
    await doc.dispose();
  }
}
