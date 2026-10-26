import 'package:consultorio/core/format.dart';
import 'package:consultorio/data/care_rules.dart';
import 'package:consultorio/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('gestação', () {
    // Caso das capturas de tela: 20s3d em 16/10/2026.
    final measured = DateTime(2026, 10, 16);
    final dum = dumFromGestationalAge(weeks: 20, days: 3, measuredOn: measured);

    test('DUM equivalente, DPP e idade gestacional', () {
      expect(dum, DateTime(2026, 5, 26));
      expect(dueDate(dum), DateTime(2027, 3, 2));
      final ga = gestationalAge(dum, measured);
      expect(ga.short, '20s3d');
      expect(ga.long, '20 semanas e 3 dias');
      expect(ga.trimester, 2);
    });

    test('trimestres e fases do calendário', () {
      expect(const GestationalAge(13 * 7 + 6).trimester, 1);
      expect(const GestationalAge(14 * 7).trimester, 2);
      expect(const GestationalAge(28 * 7).trimester, 3);
      expect(PrenatalPhase.of(const GestationalAge(27 * 7 + 6)), PrenatalPhase.monthly);
      expect(PrenatalPhase.of(const GestationalAge(28 * 7)), PrenatalPhase.biweekly);
      expect(PrenatalPhase.of(const GestationalAge(36 * 7)), PrenatalPhase.weekly);
    });

    test('retorno sugerido para gestante é mensal até 28 semanas', () {
      final p = Patient(id: 'g', name: 'Gestante', sex: Sex.female, dum: dum);
      final s = suggestReturn(p, null, measured)!;
      expect(s.date, DateTime(2026, 11, 13));
      expect(s.reason, contains('20 semanas e 3 dias'));
      expect(s.reason, contains('mensal'));
    });

    test('perto da mudança de fase o retorno não pula a fase seguinte', () {
      final on = DateTime(2026, 10, 23);
      Patient at(int weeks, int days) => Patient(
            id: 'g',
            name: 'G',
            dum: dumFromGestationalAge(weeks: weeks, days: days, measuredOn: on),
          );
      // 27s2d: +28 dias cairia em 31 semanas; a partir de 28 é quinzenal.
      expect(suggestReturn(at(27, 2), null, on)!.date, addDays(on, 14));
      expect(suggestReturn(at(27, 2), null, on)!.reason, contains('quinzenais'));
      // 35s0d: +14 cairia em 37 semanas; a partir de 36 é semanal.
      expect(suggestReturn(at(35, 0), null, on)!.date, addDays(on, 7));
      // 24s0d: +28 = exatamente 28s0d, início da fase quinzenal: mantém.
      expect(suggestReturn(at(24, 0), null, on)!.date, addDays(on, 28));
      // 24s1d: +28 passaria de 28 semanas → 14 dias.
      expect(suggestReturn(at(24, 1), null, on)!.date, addDays(on, 14));
      // 32s0d: +14 = exatamente 36s0d: mantém quinzenal.
      expect(suggestReturn(at(32, 0), null, on)!.date, addDays(on, 14));
    });

    test('gestação encerrada não sugere calendário de pré-natal', () {
      final p = Patient(id: 'g', name: 'X', dum: dum, pregnancyEnd: DateTime(2026, 9, 1));
      expect(p.pregnant, isFalse);
      expect(pregnantOn(p, measured), isFalse);
      expect(suggestReturn(p, null, measured), isNull);
    });
  });

  group('puericultura', () {
    final birth = DateTime(2026, 7, 10);
    final on = DateTime(2026, 10, 16);

    test('idade em meses e dias', () {
      expect(ageMonthsDays(birth, on), (3, 6));
      expect(infantAgeLong(birth, on), '3 meses e 6 dias');
      expect(ageLabel(addDays(today(), -10)), '10 dias');
      expect(ageMonthsDays(DateTime(2026, 1, 31), DateTime(2026, 2, 28)), (1, 0));
    });

    test('quadro de consultas: realizada, sem consulta, atual e a vir', () {
      final visits = [DateTime(2026, 8, 12), DateTime(2026, 10, 12)]; // meses 1 e 3
      final grid = infantVisitGrid(birth, visits, on);
      expect(grid, hasLength(24));
      expect(grid[0].done, isTrue); // 1º mês
      expect(grid[1].missed, isTrue); // 2º mês, sem consulta
      expect(grid[2].done && grid[2].current, isTrue); // 3º mês, hoje
      expect(grid[3].past || grid[3].done, isFalse); // 4º mês, a vir
    });

    test('próximo retorno: mês seguinte se o atual já teve consulta', () {
      final next = nextInfantVisit(birth, [DateTime(2026, 10, 12)], on)!;
      expect(next.month, 4);
      expect(next.date, DateTime(2026, 11, 10));
      expect(next.currentMonth, isFalse);

      final pending = nextInfantVisit(birth, const [], on)!;
      expect(pending.month, 3);
      expect(pending.currentMonth, isTrue);
    });

    test('retorno sugerido para criança é a consulta do próximo mês', () {
      final p = Patient(id: 'c', name: 'Bebê', birthDate: birth);
      final s = suggestReturn(p, null, DateTime(2026, 10, 12))!;
      expect(s.date, DateTime(2026, 11, 10));
      expect(s.reason, contains('4º mês'));
    });

    test('depois dos 2 anos vale o intervalo da linha de cuidado', () {
      final p = Patient(id: 'c', name: 'Criança', birthDate: DateTime(2024, 1, 1));
      final line = CareLine(id: 'l', name: 'Puericultura', color: 0, defaultReturnDays: 30);
      expect(isInfant(p, on), isFalse);
      expect(suggestReturn(p, line, on)!.date, addDays(on, 30));
    });
  });
}
