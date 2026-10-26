import 'dart:math';

import '../core/format.dart';
import '../data/app_data.dart';
import '../data/care_rules.dart';
import '../data/models.dart';

/// Gera dados fictícios para demonstração ao cliente. Todos os pacientes
/// recebem a marca [demoTag] nas observações e podem ser removidos depois.
const demoTag = '[DEMO]';

const _female = [
  'Ana', 'Maria', 'Juliana', 'Fernanda', 'Patrícia', 'Aline', 'Camila',
  'Luciana', 'Beatriz', 'Mariana', 'Helena', 'Rosa', 'Tereza', 'Sônia',
  'Cláudia', 'Vera', 'Lúcia', 'Raquel',
];
const _male = [
  'José', 'João', 'Antônio', 'Carlos', 'Paulo', 'Pedro', 'Lucas', 'Marcos',
  'Rafael', 'Luiz', 'Eduardo', 'Ricardo', 'Fernando', 'Roberto', 'Sérgio',
  'Gabriel', 'Mateus',
];
const _surnames = [
  'Silva', 'Santos', 'Oliveira', 'Souza', 'Rodrigues', 'Ferreira', 'Alves',
  'Pereira', 'Lima', 'Gomes', 'Costa', 'Ribeiro', 'Martins', 'Carvalho',
  'Almeida', 'Lopes', 'Barbosa', 'Rocha', 'Dias', 'Moreira',
];

const _cidByLine = {
  'cl-hipertensao': ['I10', 'I10', 'I11', 'E78', 'E66'],
  'cl-diabetes': ['E11', 'E11', 'E10', 'E66', 'E78', 'I10'],
  'cl-saude-mental': ['F32', 'F41', 'F33', 'F41', 'F31', 'F17'],
  'cl-saude-mulher': ['Z30', 'N95', 'Z34', 'Z00', 'D50'],
  'cl-saude-idoso': ['I10', 'M81', 'M17', 'G30', 'N18', 'E11'],
};

const _rxByLine = {
  'cl-hipertensao': [('Losartana', '50 mg 12/12h'), ('Hidroclorotiazida', '25 mg 1x/dia'), ('Anlodipino', '5 mg 1x/dia')],
  'cl-diabetes': [('Metformina', '850 mg 2x/dia'), ('Glicazida', '30 mg 1x/dia'), ('Insulina NPH', '20 UI à noite')],
  'cl-saude-mental': [('Sertralina', '50 mg 1x/dia'), ('Fluoxetina', '20 mg 1x/dia'), ('Clonazepam', '0,5 mg à noite')],
  'cl-saude-mulher': [('Anticoncepcional oral', '1 cp/dia'), ('Sulfato ferroso', '40 mg 1x/dia')],
  'cl-saude-idoso': [('Sinvastatina', '20 mg à noite'), ('Alendronato', '70 mg 1x/semana'), ('Losartana', '50 mg 1x/dia')],
};

const _examsByLine = {
  'cl-hipertensao': [('Creatinina', 'Creatinina: 0,9 mg/dL (VR 0,6–1,2)'), ('Potássio', 'K+: 4,3 mEq/L'), ('ECG', 'Ritmo sinusal, sem alterações agudas')],
  'cl-diabetes': [('Hemoglobina glicada (HbA1c)', 'HbA1c: 7,4%'), ('Glicemia de jejum', 'Glicemia: 132 mg/dL'), ('Microalbuminúria', '18 mg/g creatinina')],
  'cl-saude-mental': [('TSH', 'TSH: 2,1 µUI/mL'), ('Hemograma', 'Sem alterações')],
  'cl-saude-mulher': [('Papanicolau', 'Negativo para lesão intraepitelial'), ('Mamografia', 'BI-RADS 1'), ('Hemograma', 'Hb 11,8 g/dL')],
  'cl-saude-idoso': [('Vitamina D', '25-OH vitamina D: 22 ng/mL'), ('Colesterol total e frações', 'CT 198 · LDL 118 · HDL 46'), ('Creatinina', '1,1 mg/dL')],
};

Future<void> seedDemoData(AppData data, {int patients = 48}) async {
  final rnd = Random(42);
  final now = today();
  T pick<T>(List<T> l) => l[rnd.nextInt(l.length)];

  final lines = data.careLines.where((c) => _cidByLine.containsKey(c.id)).toList();
  final usable = lines.isEmpty ? data.careLines : lines;
  if (usable.isEmpty) return;

  final pList = <Patient>[];
  final aList = <Appointment>[];
  final rList = <Prescription>[];
  final eList = <Exam>[];

  for (var i = 0; i < patients; i++) {
    final line = pick(usable);
    final female = line.id == 'cl-saude-mulher' || rnd.nextDouble() < 0.56;
    final age = switch (line.id) {
      'cl-saude-idoso' => 62 + rnd.nextInt(28),
      'cl-saude-mulher' => 18 + rnd.nextInt(40),
      'cl-saude-mental' => 16 + rnd.nextInt(50),
      _ => 35 + rnd.nextInt(45),
    };
    final birth = DateTime(now.year - age, 1 + rnd.nextInt(12), 1 + rnd.nextInt(28));
    final cids = {pick(_cidByLine[line.id] ?? ['Z00'])};
    if (rnd.nextDouble() < 0.35) cids.add(pick(_cidByLine[line.id] ?? ['Z00']));

    final patient = Patient(
      id: newId(),
      name: _fullName(rnd, female ? pick(_female) : pick(_male)),
      birthDate: birth,
      sex: female ? Sex.female : Sex.male,
      phone: '(11) 9${1000 + rnd.nextInt(8999)}-${1000 + rnd.nextInt(8999)}',
      careLineId: line.id,
      cidCodes: cids.toList(),
      notes: '$demoTag Paciente fictício para demonstração.',
    );
    pList.add(patient);

    // Consultas passadas (últimos ~6 meses).
    final visits = 1 + rnd.nextInt(4);
    DateTime? lastDone;
    for (var v = 0; v < visits; v++) {
      final day = _weekday(addDays(now, -(5 + rnd.nextInt(175))));
      final start = DateTime(day.year, day.month, day.day, 8 + rnd.nextInt(9), rnd.nextBool() ? 0 : 30);
      final missed = rnd.nextDouble() < 0.12;
      aList.add(Appointment(
        id: newId(),
        patientId: patient.id,
        startAt: start,
        status: missed ? ApptStatus.missed : ApptStatus.done,
      ));
      if (!missed && (lastDone == null || start.isAfter(lastDone))) lastDone = start;
    }
    if (lastDone != null) {
      final latest = aList.lastWhere((a) => a.patientId == patient.id && a.startAt == lastDone);
      latest.returnDue = addDays(dateOnly(lastDone), line.defaultReturnDays ?? 90);
    }

    // Algumas consultas já marcadas para as próximas duas semanas.
    if (rnd.nextDouble() < 0.4) {
      final day = _weekday(addDays(now, rnd.nextInt(14)));
      aList.add(Appointment(
        id: newId(),
        patientId: patient.id,
        startAt: DateTime(day.year, day.month, day.day, 8 + rnd.nextInt(9), rnd.nextBool() ? 0 : 30),
      ));
    }

    // Receitas.
    final meds = _rxByLine[line.id] ?? const [];
    if (meds.isNotEmpty) {
      final count = 1 + rnd.nextInt(2);
      for (var r = 0; r < count; r++) {
        final (med, dose) = meds[(r + i) % meds.length];
        final issued = dateOnly(lastDone ?? addDays(now, -30));
        final validity = pick([30, 60, 90, 180]);
        rList.add(Prescription(
          id: newId(),
          patientId: patient.id,
          medication: med,
          dosage: dose,
          issuedAt: issued,
          expiresAt: addDays(issued, validity),
        ));
      }
    }

    // Exames.
    final ex = _examsByLine[line.id] ?? const [];
    if (ex.isNotEmpty) {
      final count = 1 + rnd.nextInt(2);
      for (var e = 0; e < count; e++) {
        final (name, result) = ex[(e + i) % ex.length];
        final performed = addDays(now, -(10 + rnd.nextInt(150)));
        eList.add(Exam(
          id: newId(),
          patientId: patient.id,
          name: name,
          performedAt: performed,
          result: result,
          nextDue: rnd.nextDouble() < 0.6 ? addMonths(performed, pick([3, 6])) : null,
        ));
      }
    }
  }

  _seedPregnancies(data, rnd, now, pList, aList, rList, eList);
  _seedInfants(data, rnd, now, pList, aList, rList, eList);

  await data.insertBulk({
    Patient.table: pList,
    Appointment.table: aList,
    Prescription.table: rList,
    Exam.table: eList,
  });
}

/// Nome e dois sobrenomes diferentes.
String _fullName(Random rnd, String first) {
  final a = rnd.nextInt(_surnames.length);
  final b = (a + 1 + rnd.nextInt(_surnames.length - 1)) % _surnames.length;
  return '$first ${_surnames[a]} ${_surnames[b]}';
}

DateTime _at(DateTime day, Random rnd) =>
    DateTime(day.year, day.month, day.day, 8 + rnd.nextInt(9), rnd.nextBool() ? 0 : 30);

/// Gestantes de 6 a 38 semanas, com consultas seguindo o calendário do
/// pré-natal (mensal, quinzenal, semanal) desde a 8ª semana.
void _seedPregnancies(
  AppData data,
  Random rnd,
  DateTime now,
  List<Patient> pList,
  List<Appointment> aList,
  List<Prescription> rList,
  List<Exam> eList,
) {
  T pick<T>(List<T> l) => l[rnd.nextInt(l.length)];
  final line = data.careLine(AppData.prenatalLineId);
  for (var i = 0; i < 8; i++) {
    final dum = addDays(now, -(7 * (6 + rnd.nextInt(33)) + rnd.nextInt(7)));
    final age = 18 + rnd.nextInt(24);
    final p = Patient(
      id: newId(),
      name: _fullName(rnd, pick(_female)),
      birthDate: DateTime(now.year - age, 1 + rnd.nextInt(12), 1 + rnd.nextInt(28)),
      sex: Sex.female,
      phone: '(11) 9${1000 + rnd.nextInt(8999)}-${1000 + rnd.nextInt(8999)}',
      careLineId: line?.id,
      cidCodes: ['Z34', if (rnd.nextDouble() < 0.25) 'D50'],
      notes: '$demoTag Gestante fictícia para demonstração.',
      dum: dum,
    );
    pList.add(p);

    Appointment? lastDone;
    var day = addDays(dum, 8 * 7 + rnd.nextInt(7));
    while (true) {
      final d = _weekday(day);
      if (!d.isBefore(now)) break;
      final missed = rnd.nextDouble() < 0.08;
      final a = Appointment(
        id: newId(),
        patientId: p.id,
        startAt: _at(d, rnd),
        status: missed ? ApptStatus.missed : ApptStatus.done,
      );
      aList.add(a);
      if (!missed) lastDone = a;
      day = addDays(d, PrenatalPhase.of(gestationalAge(dum, d)).intervalDays);
    }
    if (lastDone != null) {
      lastDone.returnDue = suggestReturn(p, line, lastDone.startAt)?.date;
      if (rnd.nextDouble() < 0.5 && lastDone.returnDue != null && lastDone.returnDue!.isAfter(now)) {
        aList.add(Appointment(id: newId(), patientId: p.id, startAt: _at(_weekday(lastDone.returnDue!), rnd)));
      }
    }

    final start = addDays(dum, 8 * 7);
    if (start.isBefore(now)) {
      for (final (med, dose, days) in const [
        ('Sulfato ferroso', '40 mg 1x/dia', 180),
        ('Ácido fólico', '5 mg 1x/dia', 90),
      ]) {
        rList.add(Prescription(
          id: newId(),
          patientId: p.id,
          medication: med,
          dosage: dose,
          issuedAt: start,
          expiresAt: addDays(start, days),
        ));
      }
      eList
        ..add(Exam(
          id: newId(),
          patientId: p.id,
          name: 'Ultrassonografia obstétrica',
          performedAt: start,
          result: 'Gestação tópica, feto único, BCF presente. IG compatível com a DUM.',
          nextDue: addDays(dum, 20 * 7),
        ))
        ..add(Exam(
          id: newId(),
          patientId: p.id,
          name: 'Sorologias do pré-natal (HIV, sífilis, hepatites B e C)',
          performedAt: start,
          result: 'Não reagentes.',
          nextDue: addDays(dum, 28 * 7),
        ));
    }
  }
}

/// Crianças de 3 semanas a pouco mais de 2 anos, com consultas mensais de
/// puericultura (algumas faltando, para o quadro mostrar meses sem consulta).
void _seedInfants(
  AppData data,
  Random rnd,
  DateTime now,
  List<Patient> pList,
  List<Appointment> aList,
  List<Prescription> rList,
  List<Exam> eList,
) {
  T pick<T>(List<T> l) => l[rnd.nextInt(l.length)];
  final line = data.careLine(AppData.infantLineId);
  for (var i = 0; i < 7; i++) {
    final birth = addDays(now, -(20 + rnd.nextInt(780)));
    final male = rnd.nextBool();
    final p = Patient(
      id: newId(),
      name: _fullName(rnd, male ? pick(_male) : pick(_female)),
      birthDate: birth,
      sex: male ? Sex.male : Sex.female,
      phone: '(11) 9${1000 + rnd.nextInt(8999)}-${1000 + rnd.nextInt(8999)}',
      careLineId: line?.id,
      cidCodes: ['Z00', if (rnd.nextDouble() < 0.2) pick(const ['J45', 'D50'])],
      notes: '$demoTag Criança fictícia para demonstração.',
    );
    pList.add(p);

    final months = ageMonthsDays(birth, now).$1;
    Appointment? lastDone;
    for (var k = 1; k <= min(months, childFollowUpMonths); k++) {
      if (rnd.nextDouble() < 0.12) continue; // mês sem consulta
      final d = _weekday(addDays(addMonths(birth, k), rnd.nextInt(10)));
      if (!d.isBefore(now)) continue;
      final a = Appointment(id: newId(), patientId: p.id, startAt: _at(d, rnd), status: ApptStatus.done);
      aList.add(a);
      lastDone = a;
    }
    if (lastDone != null) lastDone.returnDue = suggestReturn(p, line, lastDone.startAt)?.date;

    // Receitas renovadas na última consulta.
    final issued = dateOnly(lastDone?.startAt ?? addDays(birth, 7));
    rList.add(Prescription(
      id: newId(),
      patientId: p.id,
      medication: 'Vitamina D (gotas)',
      dosage: '400 UI 1x/dia',
      issuedAt: issued,
      expiresAt: addDays(issued, 180),
    ));
    if (months >= 6) {
      rList.add(Prescription(
        id: newId(),
        patientId: p.id,
        medication: 'Sulfato ferroso (gotas)',
        dosage: '1 mg/kg/dia',
        issuedAt: issued,
        expiresAt: addDays(issued, 180),
      ));
    }
    eList.add(Exam(
      id: newId(),
      patientId: p.id,
      name: 'Teste do pezinho',
      performedAt: addDays(birth, 4),
      result: 'Triagem neonatal normal.',
    ));
  }
}

DateTime _weekday(DateTime d) {
  if (d.weekday == DateTime.saturday) return addDays(d, 2);
  if (d.weekday == DateTime.sunday) return addDays(d, 1);
  return d;
}

Future<void> removeDemoData(AppData data) async {
  final demo = data.patients.where((p) => (p.notes ?? '').startsWith(demoTag)).toList();
  await data.deleteMany(demo);
}

bool hasDemoData(AppData data) =>
    data.patients.any((p) => (p.notes ?? '').startsWith(demoTag));
