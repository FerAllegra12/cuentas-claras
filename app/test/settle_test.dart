import 'package:flutter_test/flutter_test.dart';
import 'package:cuentas_claras/core/settle.dart';

void main() {
  const f = 'fercho', p = 'pepito', j = 'juancito';

  test('saldos: reparto 100,00 entre 3, pagó Fercho', () {
    final nets = groupNets([f, p, j], [const GroupExpense(10000, f, [f, p, j])], []);
    expect(nets, {f: 6666, p: -3333, j: -3333});
    expect(nets.values.reduce((a, b) => a + b), 0);
  });

  test('un pago pendiente no baja la deuda, uno confirmado sí', () {
    final gastos = [const GroupExpense(10000, f, [f, p, j])];
    final pend = groupNets([f, p, j], gastos, [const GroupPayment(p, f, 3333, confirmed: false)]);
    expect(pend[p], -3333);
    final conf = groupNets([f, p, j], gastos, [const GroupPayment(p, f, 3333)]);
    expect(conf[p], 0);
    expect(conf[f], 3333);
  });

  test('settle: el que más debe le paga al que más tiene a favor', () {
    final t = settle({f: 6666, p: -3333, j: -3333});
    expect(t, [const Transfer(p, f, 3333), const Transfer(j, f, 3333)]);
  });

  test('settle minimiza transferencias en un caso cruzado', () {
    final t = settle({'a': 5000, 'b': 3000, 'c': -6000, 'd': -2000});
    expect(t, [const Transfer('c', 'a', 5000), const Transfer('d', 'b', 2000), const Transfer('c', 'b', 1000)]);
    // todos quedan a mano
    final neto = {'a': 5000, 'b': 3000, 'c': -6000, 'd': -2000};
    for (final x in t) {
      neto[x.from] = neto[x.from]! + x.cents;
      neto[x.to] = neto[x.to]! - x.cents;
    }
    expect(neto.values.every((v) => v == 0), isTrue);
  });

  test('settle sin deudas devuelve vacío', () {
    expect(settle({f: 0, p: 0}), isEmpty);
  });
}
