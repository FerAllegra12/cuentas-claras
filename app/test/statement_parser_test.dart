import 'package:cuentas_claras/core/statement_parser.dart';
import 'package:flutter_test/flutter_test.dart';

// Resúmenes inventados (no son datos reales) con el mismo formato que los de Galicia y Mercado Pago.
// Los resultados esperados salen del parser del prototipo (JS), que ya lee los PDFs reales.
const visa = [
  'Tarjeta Crédito VISA',
  '01-Oct-26 09-Oct-26 29-Oct-26 11-Nov-26 26-Nov-26 04-Dic-26',
  '09-10-26 SU PAGO EN PESOS -100.000,00',
  'DETALLE DEL CONSUMO',
  '09-05-26 * COMERCIO UNO 06/06 123456 12.499,50',
  '29-06-26 * TIENDA DOS SA 04/12 123457 31.916,16',
  '16-10-26 K SERVICIO TRES 123458 49.149,98',
  '23-10-26 K STREAMING USD 9,99 123459 19,94',
  '24-10-26 K SUSCRIPCION 123460 30.198,49',
  'TARJETA 0000 Total Consumos de F EJEMPLO 123.764,13 19,94',
  '29-10-26 IMPUESTO DE SELLOS \$ 3.005,47',
];

const mc = [
  'Tarjeta Crédito MASTERCARD BLACK',
  '27-Ago-26 04-Sep-26 01-Oct-26 09-Oct-26 29-Oct-26 10-Nov-26',
  '03-Sep-26 SU PAGO -186.751,94 -186.751,94',
  'DETALLE DEL CONSUMO',
  '27-Ago-26 DELIVERY UNO 08381 38.280,00',
  '07-Sep-26 DELIVERY DOS 01162 20.414,00',
  '16-Dic-25 TIENDA TRES 10/12 07265 18.958,27',
  '13-May-26 TIENDA CUATRO 05/24 07646 15.026,65',
  '18-May-26 TIENDA CUATRO 05/24 04206 -15.026,65',
  'SUBTOTAL 77.652,27 0,00',
];

const mp = [
  'Este es tu resumen de octubre Tarjeta de crédito',
  'Mercado Pago',
  'Consumos \$ 100.000,00 US\$ 0,00',
  'Impuestos e intereses \$ 1.000,00',
  'Cierre actual 27 de octubre Vencimiento actual 2 de noviembre',
  '2/oct Pago del resumen -\$ 50.000,00',
  'Consumos',
  '24/abr COMERCIO UNO 7 de 9 654321 \$ 11.611,11',
  '10/may COMERCIO DOS 6 de 12 654322 \$ 23.374,92',
  '26/sep Transferencia para PERSONA UNO 654323 \$ 56.704,70',
  '12/oct COMERCIO TRES 1 de 3 654324 \$ 8.309,27',
  'Ajustes y reembolsos',
  '28/sep Reembolso de COMERCIO CUATRO 654325 -\$ 1.000,00',
  'Impuestos e intereses',
  '27/oct Impuesto de sellos 654326 \$ 500,00',
];

void main() {
  test('Galicia Visa: fechas, consumos, cuotas, dólares y total', () {
    final r = parseStatement(visa);
    expect(r.issuer, 'galicia-visa');
    expect(r.closeISO, '2026-10-29');
    expect(r.dueISO, '2026-11-11');
    expect(r.payMonth, '2026-11');
    expect(r.lines.length, 5);
    expect(r.lines[0].date, '2026-05-09');
    expect(r.lines[0].desc, 'COMERCIO UNO');
    expect(r.lines[0].cuota, 6);
    expect(r.lines[0].total, 6);
    expect(r.lines[0].amountCents, 1249950);
    expect(r.lines[3].desc, 'STREAMING');
    expect(r.lines[3].currency, 'USD');
    expect(r.lines[3].amountCents, 1994);
    expect(r.expectedArs, 12376413);
    expect(r.expectedUsd, 1994);
    expect(r.ok, true, reason: r.problems.join(' | '));
  });

  test('Galicia Mastercard: subtotal, cuotas y anulación', () {
    final r = parseStatement(mc);
    expect(r.issuer, 'galicia-mc');
    expect(r.closeISO, '2026-10-01');
    expect(r.dueISO, '2026-10-09');
    expect(r.lines.length, 5);
    expect(r.lines[2].date, '2025-12-16');
    expect(r.lines[2].cuota, 10);
    expect(r.lines[2].total, 12);
    expect(r.lines[4].amountCents, -1502665);
    expect(r.expectedArs, 7765227);
    expect(r.ok, true, reason: r.problems.join(' | '));
  });

  test('Mercado Pago: año deducido, transferencias y reembolsos aparte', () {
    final r = parseStatement(mp, today: DateTime(2026, 11, 12));
    expect(r.issuer, 'mp');
    expect(r.closeISO, '2026-10-27');
    expect(r.dueISO, '2026-11-02');
    expect(r.payMonth, '2026-11');
    expect(r.lines.length, 4);
    expect(r.lines[0].date, '2026-04-24');
    expect(r.lines[0].cuota, 7);
    expect(r.lines[0].total, 9);
    expect(r.lines[2].tag, 'transferencia');
    expect(r.refunds.length, 1);
    expect(r.expectedArs, 10000000);
    expect(r.ok, true, reason: r.problems.join(' | '));
  });

  test('Si el total no cierra, avisa', () {
    final malo = [...visa]..removeAt(6); // falta un consumo en pesos
    final r = parseStatement(malo);
    expect(r.ok, false);
    expect(r.problems.any((p) => p.contains('pesos')), true);
  });

  test('Formato desconocido', () {
    final r = parseStatement(['hola', 'esto no es un resumen']);
    expect(r.issuer, null);
    expect(r.ok, false);
  });

  test('linesFromItems une pedacitos de la misma altura', () {
    final l = linesFromItems(const [
      TextItem('SUBTOTAL', 10, 500, 40),
      TextItem('1.000,00', 100, 500.5, 40),
      TextItem('Arriba', 10, 600, 30),
    ]);
    expect(l, ['Arriba', 'SUBTOTAL 1.000,00']);
  });
}
