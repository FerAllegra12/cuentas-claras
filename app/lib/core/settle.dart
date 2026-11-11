/// Saldos de grupo y "quién le paga a quién".
library;

import 'money.dart';

class Transfer {
  final String from;
  final String to;
  final int cents;
  const Transfer(this.from, this.to, this.cents);

  @override
  bool operator ==(Object other) =>
      other is Transfer && other.from == from && other.to == to && other.cents == cents;

  @override
  int get hashCode => Object.hash(from, to, cents);

  @override
  String toString() => '$from -> $to ${formatArs(cents)}';
}

class GroupExpense {
  final int cents;
  final String paidBy;
  final List<String> splitAmong; // el orden decide a quién le toca el centavo sobrante
  const GroupExpense(this.cents, this.paidBy, this.splitAmong);
}

class GroupPayment {
  final String from;
  final String to;
  final int cents;
  final bool confirmed;
  const GroupPayment(this.from, this.to, this.cents, {this.confirmed = true});
}

/// Neto por miembro: + puso de más, - le falta poner. Los pagos pendientes no cuentan.
Map<String, int> groupNets(
  List<String> members,
  List<GroupExpense> expenses,
  List<GroupPayment> payments,
) {
  final paid = {for (final m in members) m: 0};
  final owed = {for (final m in members) m: 0};
  final adj = {for (final m in members) m: 0};
  for (final e in expenses) {
    if (paid.containsKey(e.paidBy)) paid[e.paidBy] = paid[e.paidBy]! + e.cents;
    final shares = splitCents(e.cents, e.splitAmong.length);
    for (var i = 0; i < e.splitAmong.length; i++) {
      final id = e.splitAmong[i];
      if (owed.containsKey(id)) owed[id] = owed[id]! + shares[i];
    }
  }
  for (final p in payments) {
    if (!p.confirmed) continue;
    if (adj.containsKey(p.from)) adj[p.from] = adj[p.from]! + p.cents;
    if (adj.containsKey(p.to)) adj[p.to] = adj[p.to]! - p.cents;
  }
  return {for (final m in members) m: paid[m]! - owed[m]! + adj[m]!};
}

class _Item {
  final String id;
  int v;
  final int order;
  _Item(this.id, this.v, this.order);
}

/// Pocas transferencias: el que más debe le paga al que más tiene a favor.
/// Mismo algoritmo que el prototipo (en empate manda el orden de aparición).
List<Transfer> settle(Map<String, int> nets) {
  final deudores = <_Item>[];
  final acreedores = <_Item>[];
  var i = 0;
  nets.forEach((id, n) {
    if (n < 0) deudores.add(_Item(id, -n, i));
    if (n > 0) acreedores.add(_Item(id, n, i));
    i++;
  });
  int porMonto(_Item a, _Item b) {
    final c = b.v.compareTo(a.v);
    return c != 0 ? c : a.order.compareTo(b.order);
  }

  final out = <Transfer>[];
  while (deudores.isNotEmpty && acreedores.isNotEmpty) {
    deudores.sort(porMonto);
    acreedores.sort(porMonto);
    final d = deudores.first;
    final c = acreedores.first;
    final x = d.v < c.v ? d.v : c.v;
    out.add(Transfer(d.id, c.id, x));
    d.v -= x;
    c.v -= x;
    if (d.v == 0) deudores.removeAt(0);
    if (c.v == 0) acreedores.removeAt(0);
  }
  return out;
}
