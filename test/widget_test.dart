import 'package:consultorio/core/cid10.dart';
import 'package:consultorio/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('datas em pt-BR', () {
    expect(fmtDate(DateTime(2026, 3, 7)), '07/03/2026');
    expect(weekdayShort(DateTime(2026, 10, 15)), 'QUI');
    expect(dateKey(DateTime(2026, 1, 2)), '2026-01-02');
    expect(parseDate('2026-01-02'), DateTime(2026, 1, 2));
    expect(startOfWeek(DateTime(2026, 10, 18)), DateTime(2026, 10, 12));
  });

  test('idade considera aniversário', () {
    expect(ageOn(DateTime(1980, 12, 31), DateTime(2026, 12, 30)), 45);
    expect(ageOn(DateTime(1980, 12, 31), DateTime(2026, 12, 31)), 46);
  });

  test('busca ignora acentos', () {
    expect(normalize('José Antônio'), 'jose antonio');
  });

  test('CID-10 é normalizado', () {
    expect(parseCidCodes('i10, e11.9; I10'), ['I10', 'E119']);
    expect(cidLabel('I10'), 'I10 · Hipertensão essencial');
  });

  test('addMonths respeita fim do mês', () {
    expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
  });
}
