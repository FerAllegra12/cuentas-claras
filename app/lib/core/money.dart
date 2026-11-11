/// Plata siempre en centavos (int). Nunca double.
library;

/// Formato argentino: 1234567 -> "$ 12.345,67".
String formatArs(int cents) {
  final neg = cents < 0;
  final abs = cents.abs();
  final entero = (abs ~/ 100).toString();
  final dec = (abs % 100).toString().padLeft(2, '0');
  final conPuntos = entero.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  return '${neg ? '-' : ''}\$ $conPuntos,$dec';
}

/// Lee "12.345,67", "12345,67" o "12345.67" y devuelve centavos. Null si no es válido.
int? parseCents(String input) {
  var s = input.trim().replaceAll(RegExp(r'[^\d,.\-]'), '');
  if (s.isEmpty) return null;
  // "1.234" o "12.345.678" (solo puntos de mil, sin coma) son pesos enteros, no decimales
  if (RegExp(r'^-?\d{1,3}(\.\d{3})+$').hasMatch(s)) s = s.replaceAll('.', '');
  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  if (lastComma > lastDot) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (lastDot > lastComma && lastComma >= 0) {
    s = s.replaceAll(',', '');
  } else if (lastComma >= 0) {
    s = s.replaceAll(',', '.');
  }
  final v = double.tryParse(s);
  if (v == null) return null;
  return (v * 100).round();
}

/// Reparto en partes iguales. El centavo sobrante va a los primeros de la lista
/// (igual que en el prototipo y en la base de datos).
List<int> splitCents(int total, int partes) {
  if (partes <= 0) throw ArgumentError('partes debe ser > 0');
  final base = total ~/ partes;
  final resto = total - base * partes;
  return List<int>.generate(partes, (i) => base + (i < resto ? 1 : 0));
}
