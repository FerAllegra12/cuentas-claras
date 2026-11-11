import 'package:flutter_test/flutter_test.dart';
import 'package:cuentas_claras/core/money.dart';

void main() {
  test('formatArs usa puntos de mil y coma decimal', () {
    expect(formatArs(1234567), r'$ 12.345,67');
    expect(formatArs(5), r'$ 0,05');
    expect(formatArs(0), r'$ 0,00');
    expect(formatArs(-168482005 ~/ 1), r'-$ 1.684.820,05');
  });

  test('parseCents entiende formatos argentinos y planos', () {
    expect(parseCents('12.345,67'), 1234567);
    expect(parseCents('12345,67'), 1234567);
    expect(parseCents('12345.67'), 1234567);
    expect(parseCents(r'$ 24.999,83'), 2499983);
    expect(parseCents('1.234'), 123400);
    expect(parseCents('abc'), isNull);
  });

  test('splitCents: el centavo sobrante va a los primeros', () {
    expect(splitCents(10000, 3), [3334, 3333, 3333]);
    expect(splitCents(10001, 2), [5001, 5000]);
    expect(splitCents(9, 3), [3, 3, 3]);
    expect(splitCents(10000, 3).reduce((a, b) => a + b), 10000);
  });
}
