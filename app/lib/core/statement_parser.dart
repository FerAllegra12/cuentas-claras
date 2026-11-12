/// Lectura de resúmenes de tarjeta (Galicia Visa, Galicia Mastercard, Mercado Pago).
/// Port de core.js del prototipo. Funciones puras: reciben las líneas de texto del PDF
/// y devuelven consumos, fechas y el chequeo contra el total que dice el resumen.
/// Los importes van en centavos (enteros).
library;

const _meses = <String, int>{
  'ene': 0, 'feb': 1, 'mar': 2, 'abr': 3, 'may': 4, 'jun': 5, 'jul': 6, 'ago': 7,
  'sep': 8, 'set': 8, 'oct': 9, 'nov': 10, 'dic': 11,
  'enero': 0, 'febrero': 1, 'marzo': 2, 'abril': 3, 'mayo': 4, 'junio': 5, 'julio': 6,
  'agosto': 7, 'septiembre': 8, 'setiembre': 8, 'octubre': 9, 'noviembre': 10, 'diciembre': 11,
};

const _amt = r'-?\d{1,3}(?:\.\d{3})*,\d{2}';
const _amtp = r'\d{1,3}(?:\.\d{3})*,\d{2}';

const issuerLabels = <String, String>{
  'galicia-visa': 'Galicia Visa',
  'galicia-mc': 'Galicia Mastercard',
  'mp': 'Mercado Pago',
};

String _strip(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑ';
  const to = 'aaaaeeeeiiiioooouuuunAAAAEEEEIIIIOOOOUUUUN';
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  return b.toString();
}

int _mesIdx(String s) => _meses[_strip(s).toLowerCase()] ?? -1;

/// "1.234,56" o "-1.234,56" -> centavos.
int _cents(String s) {
  final neg = s.startsWith('-');
  final t = s.replaceAll('-', '').replaceAll('.', '');
  final parts = t.split(',');
  final v = int.parse(parts[0]) * 100 + int.parse(parts[1]);
  return neg ? -v : v;
}

String _pad(int n) => n < 10 ? '0$n' : '$n';
String _iso(int y, int m, int d) => '$y-${_pad(m + 1)}-${_pad(d)}';

class StatementLine {
  StatementLine({
    required this.date,
    required this.desc,
    required this.descRaw,
    required this.amountCents,
    required this.currency,
    required this.ref,
    this.cuota,
    this.total,
    this.tag,
  });
  final String date; // AAAA-MM-DD
  final String desc;
  final String descRaw;
  final int amountCents;
  final String currency; // ARS o USD
  final String ref;
  final int? cuota;
  final int? total;
  final String? tag; // 'transferencia'
}

class StatementResult {
  StatementResult(this.issuer) : label = issuerLabels[issuer] ?? 'Formato desconocido';
  final String? issuer;
  final String label;
  String? closeISO;
  String? dueISO;
  String? payMonth;
  final List<StatementLine> lines = [];
  final List<StatementLine> refunds = [];
  int? expectedArs;
  int? expectedUsd;
  int sumArs = 0;
  int sumUsd = 0;
  bool ok = false;
  final List<String> problems = [];
}

String _fmt(int c) {
  final neg = c < 0;
  final a = c.abs();
  final s = '${a ~/ 100},${_pad(a % 100)}';
  return neg ? '-$s' : s;
}

StatementResult _finish(StatementResult r) {
  r.sumArs = 0;
  r.sumUsd = 0;
  for (final l in r.lines) {
    if (l.currency == 'USD') {
      r.sumUsd += l.amountCents;
    } else {
      r.sumArs += l.amountCents;
    }
  }
  if (r.closeISO == null) r.problems.add('No encontré las fechas de cierre y vencimiento.');
  if (r.lines.isEmpty) r.problems.add('No encontré ningún consumo.');
  if (r.expectedArs == null) {
    r.problems.add('No encontré el total de consumos del resumen para chequear.');
  } else {
    if (r.sumArs != r.expectedArs) {
      r.problems.add('La suma de lo que leí en pesos da ${_fmt(r.sumArs)} y el resumen dice ${_fmt(r.expectedArs!)}.');
    }
    if (r.sumUsd != (r.expectedUsd ?? 0)) {
      r.problems.add('La suma de lo que leí en dólares da ${_fmt(r.sumUsd)} y el resumen dice ${_fmt(r.expectedUsd ?? 0)}.');
    }
  }
  r.ok = r.problems.isEmpty;
  return r;
}

/// Limpia espacios raros y descarta líneas vacías.
List<String> cleanLines(Iterable<String> input) {
  final out = <String>[];
  for (final l in input) {
    final t = l.replaceAll(RegExp('[   ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isNotEmpty) out.add(t);
  }
  return out;
}

String? detectIssuer(List<String> lines) {
  final text = lines.join('\n');
  if (RegExp('Este es tu resumen de', caseSensitive: false).hasMatch(text) &&
      RegExp(r'mercado\s*pago|mercadolibre', caseSensitive: false).hasMatch(text)) {
    return 'mp';
  }
  if (RegExp(r'Tarjeta\s+Cr.dito\s+MASTERCARD', caseSensitive: false).hasMatch(text)) return 'galicia-mc';
  if (RegExp(r'Tarjeta\s+Cr.dito\s+VISA', caseSensitive: false).hasMatch(text)) return 'galicia-visa';
  return null;
}

/// Un pedacito de texto del PDF con su posición (x hacia la derecha, y hacia arriba).
class TextItem {
  const TextItem(this.str, this.x, this.y, this.w);
  final String str;
  final double x;
  final double y;
  final double w;
}

/// Arma líneas de texto agrupando pedacitos que están a la misma altura.
List<String> linesFromItems(List<TextItem> items) {
  final its = items.where((i) => i.str.trim().isNotEmpty).toList()
    ..sort((a, b) {
      final c = b.y.compareTo(a.y);
      return c != 0 ? c : a.x.compareTo(b.x);
    });
  final groups = <_Group>[];
  _Group? cur;
  for (final it in its) {
    if (cur != null && (cur.y - it.y).abs() <= 3) {
      cur.items.add(it);
    } else {
      cur = _Group(it.y, [it]);
      groups.add(cur);
    }
  }
  return groups.map((g) {
    final b = StringBuffer();
    double? prevEnd;
    final sorted = [...g.items]..sort((a, b) => a.x.compareTo(b.x));
    for (final it in sorted) {
      if (prevEnd != null) b.write((it.x - prevEnd < 0.8) ? '' : ' ');
      b.write(it.str.trim());
      prevEnd = it.x + it.w;
    }
    return b.toString();
  }).toList();
}

class _Group {
  _Group(this.y, this.items);
  final double y;
  final List<TextItem> items;
}

// ---------- Galicia ----------

({String closeISO, String dueISO})? _galiciaDates(List<String> lines) {
  final re = RegExp(r'\b(\d{2})-([A-Za-zÀ-ÿ]{3})-(\d{2})\b');
  for (final l in lines) {
    final m = re.allMatches(l).toList();
    if (m.length >= 6) {
      String f(RegExpMatch x) => _iso(2000 + int.parse(x[3]!), _mesIdx(x[2]!), int.parse(x[1]!));
      return (closeISO: f(m[2]), dueISO: f(m[3]));
    }
  }
  return null;
}

StatementResult _parseGalicia(List<String> lines, String issuer) {
  final res = StatementResult(issuer);
  final d = _galiciaDates(lines);
  if (d != null) {
    res.closeISO = d.closeISO;
    res.dueISO = d.dueISO;
    res.payMonth = d.dueISO.substring(0, 7);
  }
  final isVisa = issuer == 'galicia-visa';
  final reV = RegExp('^(\\d{2})-(\\d{2})-(\\d{2})\\s+(?:[*K]\\s+)?(.+?)\\s+(?:(\\d{2})/(\\d{2})\\s+)?(\\d{4,8})\\s+($_amt)\$');
  final reM = RegExp('^(\\d{2})-([A-Za-z\\u00C0-\\u00FF]{3})-(\\d{2})\\s+(.+?)\\s+(?:(\\d{1,2})/(\\d{1,2})\\s+)?(\\d{4,8})\\s+($_amt)\$');
  final reTotV = RegExp('Total Consumos de .*?($_amt)(?:\\s+($_amt))?\\s*\$');
  final reTotM = RegExp('^SUBTOTAL\\s+($_amt)(?:\\s+($_amt))?\\s*\$');
  final reUsd = RegExp(r'\s*\d*USD\s+[\d.,]+\s*$', caseSensitive: false);
  var inDetail = false;
  for (final l in lines) {
    if (RegExp(r'^DETALLE DEL CONSUMO', caseSensitive: false).hasMatch(l)) {
      inDetail = true;
      continue;
    }
    if (!inDetail) continue;
    final t = (isVisa ? reTotV : reTotM).firstMatch(l);
    if (t != null) {
      res.expectedArs = _cents(t[1]!);
      res.expectedUsd = t[2] != null ? _cents(t[2]!) : 0;
      break;
    }
    final m = (isVisa ? reV : reM).firstMatch(l);
    if (m == null) continue;
    final date = isVisa
        ? _iso(2000 + int.parse(m[3]!), int.parse(m[2]!) - 1, int.parse(m[1]!))
        : _iso(2000 + int.parse(m[3]!), _mesIdx(m[2]!), int.parse(m[1]!));
    final descRaw = m[4]!;
    final usd = RegExp('USD', caseSensitive: false).hasMatch(descRaw);
    final cleaned = descRaw.replaceFirst(reUsd, '').trim();
    res.lines.add(StatementLine(
      date: date,
      desc: cleaned.isEmpty ? descRaw : cleaned,
      descRaw: descRaw,
      cuota: m[5] != null ? int.parse(m[5]!) : null,
      total: m[6] != null ? int.parse(m[6]!) : null,
      amountCents: _cents(m[8]!),
      currency: usd ? 'USD' : 'ARS',
      ref: m[7]!,
    ));
  }
  return _finish(res);
}

// ---------- Mercado Pago ----------

int _mpYear(int day, int mIdx, int? cuotaN, ({int y, int m, int d}) close) {
  final closeIdx = close.y * 12 + close.m;
  if (cuotaN != null) {
    for (var y = close.y; y >= close.y - 5; y--) {
      final first = y * 12 + mIdx + (day > close.d ? 1 : 0);
      if (first + (cuotaN - 1) == closeIdx) return y;
    }
  }
  var yy = close.y;
  if (mIdx > close.m || (mIdx == close.m && day > close.d)) yy--;
  return yy;
}

StatementResult _parseMP(List<String> lines, DateTime today, int? year) {
  final res = StatementResult('mp');
  RegExpMatch? cyc;
  final reC = RegExp(
      r'Cierre actual\s+(\d{1,2}) de ([A-Za-zÀ-ÿ]+)\s+Vencimiento actual\s+(\d{1,2}) de ([A-Za-zÀ-ÿ]+)',
      caseSensitive: false);
  for (final l in lines) {
    cyc = reC.firstMatch(l);
    if (cyc != null) break;
  }
  ({int y, int m, int d})? close;
  if (cyc != null) {
    final cm = _mesIdx(cyc[2]!), cd = int.parse(cyc[1]!);
    final dm = _mesIdx(cyc[4]!), dd = int.parse(cyc[3]!);
    var cy = year;
    if (cy == null) {
      cy = today.year;
      if (DateTime(cy, cm + 1, cd).isAfter(today)) cy--;
    }
    final dy = dm < cm ? cy + 1 : cy;
    close = (y: cy, m: cm, d: cd);
    res.closeISO = _iso(cy, cm, cd);
    res.dueISO = _iso(dy, dm, dd);
    res.payMonth = res.dueISO!.substring(0, 7);
  }
  final reL = RegExp(
      '^(\\d{1,2})/([A-Za-z]{3})\\s+(.+?)\\s+(?:(\\d{1,2}) de (\\d{1,2})\\s+)?(\\d{4,8})\\s+(-)?(US)?\\\$\\s*($_amtp)\$');
  final reE = RegExp('^Consumos\\s+-?\\\$\\s*($_amtp)\\s+US\\\$\\s*($_amtp)');
  var sec = 'consumos';
  for (final l in lines) {
    final e = reE.firstMatch(l);
    if (e != null) {
      res.expectedArs = _cents(e[1]!);
      res.expectedUsd = _cents(e[2]!);
      continue;
    }
    if (RegExp(r'^Ajustes y reembolsos$', caseSensitive: false).hasMatch(l)) {
      sec = 'ajustes';
      continue;
    }
    if (RegExp(r'^Impuestos e intereses', caseSensitive: false).hasMatch(l)) {
      sec = 'impuestos';
      continue;
    }
    if (RegExp(r'^Pagos anticipados$', caseSensitive: false).hasMatch(l)) {
      sec = 'pagos';
      continue;
    }
    if (RegExp(r'^Consumos$', caseSensitive: false).hasMatch(l)) {
      sec = 'consumos';
      continue;
    }
    if (sec == 'impuestos' || sec == 'pagos') continue;
    final m = reL.firstMatch(l);
    if (m == null || close == null) continue;
    final mi = _mesIdx(m[2]!);
    if (mi < 0) continue;
    final cuota = m[4] != null ? int.parse(m[4]!) : null;
    final y = _mpYear(int.parse(m[1]!), mi, cuota, close);
    final cents = _cents(m[9]!) * (m[7] != null ? -1 : 1);
    final desc = m[3]!.trim();
    final line = StatementLine(
      date: _iso(y, mi, int.parse(m[1]!)),
      desc: desc,
      descRaw: desc,
      cuota: cuota,
      total: m[5] != null ? int.parse(m[5]!) : null,
      amountCents: cents,
      currency: m[8] != null ? 'USD' : 'ARS',
      ref: m[6]!,
      tag: RegExp(r'^Transferencia para ', caseSensitive: false).hasMatch(desc) ? 'transferencia' : null,
    );
    if (sec == 'ajustes') {
      res.refunds.add(line);
    } else {
      res.lines.add(line);
    }
  }
  return _finish(res);
}

/// Punto de entrada: líneas de texto del PDF -> resultado.
/// [today] y [year] solo se usan en Mercado Pago (el resumen no trae el año).
StatementResult parseStatement(Iterable<String> input, {DateTime? today, int? year}) {
  final lines = cleanLines(input);
  final issuer = detectIssuer(lines);
  if (issuer == null) {
    final r = StatementResult(null);
    r.problems.add('No reconozco este resumen. Por ahora leo Galicia Visa, Galicia Mastercard y Mercado Pago.');
    return r;
  }
  return issuer == 'mp'
      ? _parseMP(lines, today ?? DateTime.now(), year)
      : _parseGalicia(lines, issuer);
}
