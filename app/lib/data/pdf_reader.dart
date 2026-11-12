import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

/// Saca las líneas de texto de un PDF, página por página, sin internet ni IA.
/// Usa PDFium (el motor de Chrome). Por cada letra la librería da su posición,
/// y acá se arman las líneas juntando las letras que están a la misma altura.
Future<List<String>> pdfToLines(Uint8List bytes) async {
  final doc = await PdfDocument.openData(bytes);
  try {
    final out = <String>[];
    for (final page in doc.pages) {
      final raw = await page.loadText();
      if (raw == null) continue;
      final text = raw.fullText;
      final rects = raw.charRects;
      final n = text.length < rects.length ? text.length : rects.length;

      final chars = <_Ch>[];
      for (var i = 0; i < n; i++) {
        final c = text[i];
        if (c == '\n' || c == '\r') continue;
        final r = rects[i];
        chars.add(_Ch(c, r.left, r.right, (r.top + r.bottom) / 2));
      }
      // De arriba hacia abajo (en PDF la y crece hacia arriba), y de izquierda a derecha.
      chars.sort((a, b) {
        final c = b.y.compareTo(a.y);
        return c != 0 ? c : a.left.compareTo(b.left);
      });
      final groups = <List<_Ch>>[];
      double? gy;
      for (final ch in chars) {
        if (gy != null && (gy - ch.y).abs() <= 3) {
          groups.last.add(ch);
        } else {
          groups.add([ch]);
          gy = ch.y;
        }
      }
      for (final g in groups) {
        g.sort((a, b) => a.left.compareTo(b.left));
        final b = StringBuffer();
        _Ch? prev;
        for (final ch in g) {
          if (prev != null && ch.c != ' ' && prev.c != ' ' && ch.left - prev.right > 1.2) b.write(' ');
          b.write(ch.c);
          prev = ch;
        }
        out.add(b.toString());
      }
    }
    return out;
  } finally {
    await doc.dispose();
  }
}

class _Ch {
  _Ch(this.c, this.left, this.right, this.y);
  final String c;
  final double left;
  final double right;
  final double y;
}
