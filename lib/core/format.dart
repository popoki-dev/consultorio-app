// Datas e textos em pt-BR, sem depender de dados de localidade do intl.

const _weekdaysShort = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB', 'DOM'];
const _weekdaysLong = [
  'segunda-feira',
  'terça-feira',
  'quarta-feira',
  'quinta-feira',
  'sexta-feira',
  'sábado',
  'domingo',
];
const _months = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];
const _monthsShort = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

String _two(int n) => n.toString().padLeft(2, '0');

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime today() => dateOnly(DateTime.now());
DateTime addDays(DateTime d, int n) =>
    DateTime(d.year, d.month, d.day + n, d.hour, d.minute);
DateTime addMonths(DateTime d, int n) {
  final target = DateTime(d.year, d.month + n, 1);
  final lastDay = DateTime(target.year, target.month + 1, 0).day;
  return DateTime(target.year, target.month, d.day > lastDay ? lastDay : d.day);
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
DateTime startOfWeek(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// Dias de calendário entre duas datas (ignora horas).
int daysBetween(DateTime from, DateTime to) =>
    (dateOnly(to).difference(dateOnly(from)).inHours / 24).round();

String dateKey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
DateTime? parseDate(Object? s) {
  if (s == null) return null;
  final str = s.toString();
  if (str.isEmpty) return null;
  final parsed = DateTime.tryParse(str);
  return parsed == null ? null : (str.length <= 10 ? dateOnly(parsed) : parsed);
}

/// Data e hora locais, sem fuso (consultas sempre no horário do consultório).
String localIso(DateTime d) =>
    '${dateKey(d)}T${_two(d.hour)}:${_two(d.minute)}:00';

String nowUtcIso() => DateTime.now().toUtc().toIso8601String();

String fmtDate(DateTime? d) =>
    d == null ? '—' : '${_two(d.day)}/${_two(d.month)}/${d.year}';
String fmtDateShort(DateTime d) => '${_two(d.day)}/${_two(d.month)}';
String fmtTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
String weekdayShort(DateTime d) => _weekdaysShort[d.weekday - 1];
String weekdayLong(DateTime d) => _weekdaysLong[d.weekday - 1];
String monthShort(DateTime d) => _monthsShort[d.month - 1];
String monthYear(DateTime d) => '${capitalize(_months[d.month - 1])} ${d.year}';
String fmtDayLong(DateTime d) =>
    capitalize('${weekdayLong(d)}, ${d.day} de ${_months[d.month - 1]}');

String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String relativeDays(DateTime due) {
  final n = daysBetween(today(), due);
  if (n == 0) return 'hoje';
  if (n == 1) return 'amanhã';
  if (n == -1) return 'ontem';
  if (n > 1) return 'em $n dias';
  return 'há ${-n} dias';
}

int ageOn(DateTime birth, DateTime ref) {
  var age = ref.year - birth.year;
  if (ref.month < birth.month ||
      (ref.month == birth.month && ref.day < birth.day)) {
    age--;
  }
  return age;
}

/// Meses completos de vida e os dias além deles (para bebês).
(int, int) ageMonthsDays(DateTime birth, DateTime on) {
  final b = dateOnly(birth);
  final d = dateOnly(on);
  if (d.isBefore(b)) return (0, 0);
  var months = (d.year - b.year) * 12 + d.month - b.month;
  if (addMonths(b, months).isAfter(d)) months--;
  return (months, daysBetween(addMonths(b, months), d));
}

/// Até 2 anos a idade aparece em meses (ou dias), como na puericultura.
String ageLabel(DateTime? birth) {
  if (birth == null) return 'Idade não informada';
  final now = DateTime.now();
  final (months, days) = ageMonthsDays(birth, now);
  if (months == 0) return days == 1 ? '1 dia' : '$days dias';
  if (months < 24) return months == 1 ? '1 mês' : '$months meses';
  final a = ageOn(birth, now);
  return a == 1 ? '1 ano' : '$a anos';
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  final last = parts.length > 1 ? parts.last[0] : '';
  return (first + last).toUpperCase();
}

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
};

/// Minúsculas e sem acentos, para busca.
String normalize(String s) {
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final ch in lower.split('')) {
    b.write(_accents[ch] ?? ch);
  }
  return b.toString();
}

String digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

String plural(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';
