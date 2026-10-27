import '../core/format.dart';
import 'models.dart';

/// Regras de pré-natal e puericultura (calendário do Ministério da Saúde):
///  - gestação: DPP pela regra de Naegele (DUM + 280 dias); consultas
///    mensais até 28 semanas, quinzenais de 28 a 36 e semanais depois;
///  - criança: consultas mensais até os 2 anos, uma por mês de vida.
/// Tudo aqui é cálculo puro, sem banco nem tela, para ser testado.

const pregnancyDays = 280;

/// A partir desta idade gestacional o app pede para registrar o parto.
const postTermWeeks = 42;

class GestationalAge {
  const GestationalAge(this.totalDays);
  final int totalDays;

  int get weeks => totalDays ~/ 7;
  int get days => totalDays % 7;

  /// "20s3d"
  String get short => '${weeks}s${days}d';

  /// "20 semanas e 3 dias"
  String get long {
    final w = weeks == 1 ? '1 semana' : '$weeks semanas';
    if (days == 0) return w;
    return '$w e ${days == 1 ? '1 dia' : '$days dias'}';
  }

  int get trimester => weeks < 14 ? 1 : (weeks < 28 ? 2 : 3);
}

GestationalAge gestationalAge(DateTime dum, DateTime on) =>
    GestationalAge(daysBetween(dum, on));

DateTime dueDate(DateTime dum) => addDays(dateOnly(dum), pregnancyDays);

/// DUM equivalente a uma idade gestacional medida (ex.: ultrassom).
DateTime dumFromGestationalAge({
  required int weeks,
  required int days,
  required DateTime measuredOn,
}) =>
    addDays(dateOnly(measuredOn), -(weeks * 7 + days));

enum PrenatalPhase {
  monthly('Mensal', 'até 28 semanas', 28),
  biweekly('Quinzenal', '28 a 36 semanas', 14),
  weekly('Semanal', 'a partir de 36 semanas', 7);

  const PrenatalPhase(this.label, this.range, this.intervalDays);
  final String label;
  final String range;
  final int intervalDays;

  static PrenatalPhase of(GestationalAge ga) => ga.weeks < 28
      ? monthly
      : ga.weeks < 36
          ? biweekly
          : weekly;
}

/// A gestação estava em curso nesta data?
bool pregnantOn(Patient p, DateTime on) {
  final dum = p.dum;
  if (dum == null || on.isBefore(dum)) return false;
  final end = p.pregnancyEnd;
  return end == null || on.isBefore(end);
}

// -------------------------------------------------------------- puericultura

const childFollowUpMonths = 24;

/// Criança em acompanhamento de puericultura (menos de 2 anos).
bool isInfant(Patient p, DateTime on) {
  final b = p.birthDate;
  if (b == null || on.isBefore(b)) return false;
  return ageMonthsDays(b, on).$1 < childFollowUpMonths;
}

/// "3 meses e 6 dias"
String infantAgeLong(DateTime birth, DateTime on) {
  final (m, d) = ageMonthsDays(birth, on);
  final months = m == 1 ? '1 mês' : '$m meses';
  final days = d == 1 ? '1 dia' : '$d dias';
  if (m == 0) return days;
  if (d == 0) return months;
  return '$months e $days';
}

/// Situação de cada mês de vida (1 a 24) no quadro de consultas.
class InfantMonth {
  const InfantMonth(this.month, {required this.done, required this.past, required this.current});
  final int month;
  final bool done;

  /// O mês já terminou.
  final bool past;

  /// A criança está neste mês de vida hoje.
  final bool current;

  bool get missed => past && !done;
}

/// Uma consulta realizada no mês de vida k (idade entre k e k+1 meses)
/// cumpre a consulta do mês k.
List<InfantMonth> infantVisitGrid(DateTime birth, Iterable<DateTime> doneVisits, DateTime on) {
  final doneMonths = {for (final v in doneVisits) ageMonthsDays(birth, v).$1};
  final current = ageMonthsDays(birth, on).$1;
  return [
    for (var k = 1; k <= childFollowUpMonths; k++)
      InfantMonth(k, done: doneMonths.contains(k), past: k < current, current: k == current),
  ];
}

/// Próxima consulta de puericultura a partir de [on]: a do mês atual, se
/// ainda não aconteceu, senão a do mês seguinte. Null depois dos 2 anos.
({int month, DateTime date, bool currentMonth})? nextInfantVisit(
  DateTime birth,
  Iterable<DateTime> doneVisits,
  DateTime on,
) {
  final current = ageMonthsDays(birth, on).$1;
  final doneThisMonth = doneVisits.any((v) => ageMonthsDays(birth, v).$1 == current);
  if (current >= 1 && current < childFollowUpMonths && !doneThisMonth) {
    return (month: current, date: addMonths(birth, current), currentMonth: true);
  }
  final next = current + 1;
  if (next > childFollowUpMonths) return null;
  return (month: next, date: addMonths(birth, next), currentMonth: false);
}

// ------------------------------------------------------------ retorno sugerido

class ReturnSuggestion {
  const ReturnSuggestion(this.date, this.reason);
  final DateTime date;
  final String reason;
}

/// Sugestão de retorno ao concluir uma consulta em [visitDay]: gestação e
/// puericultura têm calendário próprio; os demais seguem o intervalo das
/// linhas de cuidado do paciente (o menor, se forem várias).
ReturnSuggestion? suggestReturn(Patient p, Iterable<CareLine> lines, DateTime visitDay) {
  final day = dateOnly(visitDay);
  if (p.dum != null && pregnantOn(p, day)) {
    final ga = gestationalAge(p.dum!, day);
    final phase = PrenatalPhase.of(ga);
    // Perto da mudança de fase (ex.: 27 semanas), o intervalo atual pularia
    // a fase seguinte, que é mais frequente: vale o intervalo dela. Cair
    // exatamente no início da fase (ex.: 24 + 4 = 28 semanas) está certo.
    final next = PrenatalPhase.of(GestationalAge(ga.totalDays + phase.intervalDays - 1));
    if (next.intervalDays < phase.intervalDays) {
      return ReturnSuggestion(
        addDays(day, next.intervalDays),
        'Gestante com ${ga.long}: retorno em ${next.intervalDays} dias, '
        'porque a partir de ${next == PrenatalPhase.biweekly ? 28 : 36} semanas '
        'as consultas passam a ser ${next == PrenatalPhase.biweekly ? 'quinzenais' : 'semanais'}.',
      );
    }
    return ReturnSuggestion(
      addDays(day, phase.intervalDays),
      'Gestante com ${ga.long}: retorno ${phase.label.toLowerCase()} (${phase.range}).',
    );
  }
  final birth = p.birthDate;
  if (birth != null && isInfant(p, day)) {
    final month = ageMonthsDays(birth, day).$1 + 1;
    if (month <= childFollowUpMonths) {
      return ReturnSuggestion(
        addMonths(birth, month),
        'Criança com ${infantAgeLong(birth, day)}: consulta do $monthº mês '
        '(puericultura mensal até 2 anos).',
      );
    }
  }
  final timed = lines.where((l) => l.defaultReturnDays != null).toList()
    ..sort((a, b) => a.defaultReturnDays!.compareTo(b.defaultReturnDays!));
  if (timed.isEmpty) return null;
  final line = timed.first;
  final days = line.defaultReturnDays!;
  return ReturnSuggestion(
    addDays(day, days),
    timed.length == 1
        ? '${line.name}: retorno a cada $days dias.'
        : '${line.name}: retorno a cada $days dias (o menor intervalo entre as '
            'linhas do paciente).',
  );
}
