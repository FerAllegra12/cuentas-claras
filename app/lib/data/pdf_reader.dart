import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../core/statement_parser.dart';

/// Saca las líneas de texto de un PDF, página por página, sin internet ni IA.
List<String> pdfToLines(Uint8List bytes) {
  final doc = PdfDocument(inputBytes: bytes);
  try {
    final extractor = PdfTextExtractor(doc);
    final out = <String>[];
    for (var p = 0; p < doc.pages.count; p++) {
      final items = <TextItem>[];
      for (final line in extractor.extractTextLines(startPageIndex: p, endPageIndex: p)) {
        for (final w in line.wordCollection) {
          // Syncfusion mide la altura desde arriba; el lector espera "hacia arriba", por eso el signo.
          items.add(TextItem(w.text, w.bounds.left, -w.bounds.top, w.bounds.width));
        }
      }
      out.addAll(linesFromItems(items));
    }
    return out;
  } finally {
    doc.dispose();
  }
}
