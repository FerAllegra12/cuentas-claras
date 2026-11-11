/// Hilo de cuotas que sigue mes a mes aunque falten resúmenes.
library;

/// Suma n meses a un "YYYY-MM".
String addMonths(String ym, int n) {
  final p = ym.split('-');
  final t = int.parse(p[0]) * 12 + (int.parse(p[1]) - 1) + n;
  return '${t ~/ 12}-${((t % 12) + 1).toString().padLeft(2, '0')}';
}

/// Meses entre a y b (b - a).
int monthDiff(String a, String b) {
  final x = a.split('-');
  final y = b.split('-');
  return (int.parse(y[0]) * 12 + int.parse(y[1])) - (int.parse(x[0]) * 12 + int.parse(x[1]));
}

/// Un dato conocido del hilo: viene de un resumen real o de una corrección manual del usuario.
class CuotaPoint {
  final String month; // mes en que se paga, "YYYY-MM"
  final int cuota;
  final int total;
  final int amountCents;
  const CuotaPoint(this.month, this.cuota, this.total, this.amountCents);
}

/// Qué cuota toca en [month], a partir de la última conocida ([last]) y de las
/// correcciones del usuario ([anchors]). La última corrección anterior o igual al mes manda.
/// Devuelve null si el mes es anterior al dato o si el plan de cuotas ya terminó.
CuotaPoint? projectCuota(CuotaPoint last, String month, {List<CuotaPoint> anchors = const []}) {
  var base = last;
  final ordenadas = [...anchors]..sort((a, b) => a.month.compareTo(b.month));
  for (final a in ordenadas) {
    if (a.month.compareTo(month) <= 0 && a.month.compareTo(base.month) > 0) base = a;
  }
  final diff = monthDiff(base.month, month);
  if (diff < 0) return null;
  final n = base.cuota + diff;
  if (n > base.total) return null;
  return CuotaPoint(month, n, base.total, base.amountCents);
}
