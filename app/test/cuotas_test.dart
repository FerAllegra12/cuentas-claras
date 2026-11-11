import 'package:flutter_test/flutter_test.dart';
import 'package:cuentas_claras/core/cuotas.dart';

void main() {
  test('addMonths y monthDiff cruzan el año', () {
    expect(addMonths('2026-11', 3), '2027-02');
    expect(addMonths('2026-12', 1), '2027-01');
    expect(addMonths('2026-01', -1), '2025-12');
    expect(monthDiff('2026-10', '2027-02'), 4);
  });

  const ultima = CuotaPoint('2026-10', 5, 12, 2430000);

  test('mes siguiente: una cuota más, mismo monto', () {
    final c = projectCuota(ultima, '2026-11')!;
    expect(c.cuota, 6);
    expect(c.total, 12);
    expect(c.amountCents, 2430000);
  });

  test('con meses sin resumen la cuota sigue contando', () {
    expect(projectCuota(ultima, '2027-02')!.cuota, 9);
  });

  test('el plan terminado o un mes anterior devuelven null', () {
    expect(projectCuota(ultima, '2027-05')!.cuota, 12); // última cuota: 12 de 12
    expect(projectCuota(ultima, '2027-06'), isNull); // la 13 no existe
    expect(projectCuota(ultima, '2026-09'), isNull);
  });

  test('una corrección manual manda y los meses siguientes parten de ella', () {
    const ancla = CuotaPoint('2027-02', 7, 12, 2500000); // la app decía 9, el usuario dice 7
    expect(projectCuota(ultima, '2027-02', anchors: [ancla])!.cuota, 7);
    expect(projectCuota(ultima, '2027-02', anchors: [ancla])!.amountCents, 2500000);
    expect(projectCuota(ultima, '2027-03', anchors: [ancla])!.cuota, 8);
    // antes de la corrección sigue valiendo el dato original
    expect(projectCuota(ultima, '2027-01', anchors: [ancla])!.cuota, 8);
  });
}
