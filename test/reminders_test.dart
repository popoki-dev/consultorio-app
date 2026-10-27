import 'package:consultorio/core/format.dart';
import 'package:consultorio/data/app_data.dart';
import 'package:consultorio/data/local_db.dart';
import 'package:consultorio/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

Patient _patient(String id) => Patient(id: id, name: 'Paciente $id');

Appointment _appt(
  String id,
  String patientId,
  DateTime start, {
  String status = ApptStatus.scheduled,
  DateTime? returnDue,
  bool returnResolved = false,
}) =>
    Appointment(
      id: id,
      patientId: patientId,
      startAt: start,
      status: status,
      returnDue: returnDue,
      returnResolved: returnResolved,
    );

void main() {
  final now = today();
  late AppData data;

  setUp(() => data = AppData(LocalDb()));

  group('retorno', () {
    test('consulta realizada com previsão gera lembrete', () {
      data.replaceAll(patients: [
        _patient('p1')
      ], appointments: [
        _appt('a1', 'p1', addDays(now, -30), status: ApptStatus.done, returnDue: addDays(now, 10)),
      ]);
      expect(data.reminders, hasLength(1));
      expect(data.reminders.single.kind, ReminderKind.returnVisit);
      expect(data.reminders.single.due, addDays(now, 10));
    });

    test('consulta futura agendada resolve o retorno', () {
      data.replaceAll(patients: [
        _patient('p1')
      ], appointments: [
        _appt('a1', 'p1', addDays(now, -30), status: ApptStatus.done, returnDue: addDays(now, 10)),
        _appt('a2', 'p1', addDays(now, 5)),
      ]);
      expect(data.reminders, isEmpty);
    });

    test('consulta passada que segue "Agendada" não resolve o retorno', () {
      data.replaceAll(patients: [
        _patient('p1')
      ], appointments: [
        _appt('a1', 'p1', addDays(now, -30), status: ApptStatus.done, returnDue: addDays(now, -2)),
        _appt('a2', 'p1', addDays(now, -3)),
      ]);
      expect(data.reminders, hasLength(1));
      expect(data.reminders.single.overdue, isTrue);
    });

    test('falta e cancelamento não resolvem o retorno', () {
      data.replaceAll(patients: [
        _patient('p1')
      ], appointments: [
        _appt('a1', 'p1', addDays(now, -30), status: ApptStatus.done, returnDue: addDays(now, 1)),
        _appt('a2', 'p1', addDays(now, -5), status: ApptStatus.missed),
        _appt('a3', 'p1', addDays(now, 3), status: ApptStatus.cancelled),
      ]);
      expect(data.reminders, hasLength(1));
    });

    test('retorno marcado como resolvido some', () {
      data.replaceAll(patients: [
        _patient('p1')
      ], appointments: [
        _appt('a1', 'p1', addDays(now, -30),
            status: ApptStatus.done, returnDue: addDays(now, 10), returnResolved: true),
      ]);
      expect(data.reminders, isEmpty);
    });
  });

  test('receitas e exames pendentes, do mais urgente ao mais distante', () {
    data.replaceAll(
      patients: [_patient('p1'), _patient('p2')],
      prescriptions: [
        Prescription(
            id: 'r1', patientId: 'p1', medication: 'Losartana', issuedAt: now, expiresAt: addDays(now, 20)),
        Prescription(
            id: 'r2',
            patientId: 'p1',
            medication: 'Metformina',
            issuedAt: now,
            expiresAt: addDays(now, 1),
            resolved: true),
      ],
      exams: [
        Exam(id: 'e1', patientId: 'p2', name: 'HbA1c', performedAt: now, nextDue: addDays(now, 5)),
        Exam(id: 'e2', patientId: 'p2', name: 'ECG', performedAt: now),
      ],
    );
    expect(data.reminders.map((r) => r.source.id), ['e1', 'r1']);
  });

  test('registros de pacientes inexistentes são ignorados', () {
    data.replaceAll(patients: [
      _patient('p1')
    ], prescriptions: [
      Prescription(id: 'r1', patientId: 'gone', medication: 'X', issuedAt: now, expiresAt: now),
    ]);
    expect(data.prescriptions, isEmpty);
    expect(data.reminders, isEmpty);
  });

  test('exclusão apaga os dados pessoais e mantém o marcador', () {
    final p = Patient(
      id: 'p1',
      name: 'Maria Silva',
      birthDate: DateTime(1980, 1, 2),
      sex: Sex.female,
      phone: '11999990000',
      document: '12345678900',
      careLineIds: ['cl-diabetes', 'cl-hipertensao'],
      cidCodes: ['E11'],
      notes: 'Alergia a dipirona',
    )..scrub();
    final map = p.toMap();
    for (final k in ['birth_date', 'sex', 'phone', 'document', 'care_line_id', 'notes']) {
      expect(map[k], isNull, reason: k);
    }
    expect(map['name'], '');
    expect(map['cid_codes'], '');
    expect(map['care_line_ids'], '');
    expect(map['id'], 'p1');
    expect(map['created_at'], isNotNull);

    final rx = Prescription(
        id: 'r1', patientId: 'p1', medication: 'Sertralina', dosage: '50 mg', issuedAt: now, expiresAt: now)
      ..scrub();
    expect(rx.medication, isEmpty);
    expect(rx.dosage, isNull);

    final exam = Exam(id: 'e1', patientId: 'p1', name: 'HIV', performedAt: now, result: 'Negativo')
      ..scrub();
    expect(exam.name, isEmpty);
    expect(exam.result, isEmpty);
  });

  test('colunas locais não vão para o servidor nem para a exportação', () {
    final row = LocalDb.withoutLocalColumns(
        {'id': 'x', 'updated_at': 't', 'dirty': 1, 'base_updated_at': 't'});
    expect(row.keys, ['id', 'updated_at']);
  });

  group('receitas que vencem no mesmo dia', () {
    Prescription rx(String id, String patientId, String med, DateTime expires, {bool resolved = false}) =>
        Prescription(
          id: id,
          patientId: patientId,
          medication: med,
          issuedAt: addDays(now, -30),
          expiresAt: expires,
          resolved: resolved,
        );

    test('do mesmo paciente viram um lembrete só', () {
      final due = addDays(now, 10);
      data.replaceAll(patients: [
        _patient('p1')
      ], prescriptions: [
        rx('r1', 'p1', 'Metformina', due),
        rx('r2', 'p1', 'Losartana', due),
        rx('r3', 'p1', 'AAS', addDays(now, 40)),
        rx('r4', 'p1', 'Sinvastatina', due, resolved: true),
      ]);
      expect(data.reminders, hasLength(2));
      final same = data.reminders.first;
      expect(same.due, due);
      expect(same.sources.map((s) => s.id), ['r2', 'r1'], reason: 'ordem alfabética');
      expect(same.label, 'Receitas (2)');
      expect(same.title, 'Receitas: Losartana, Metformina');
      expect(data.reminders.last.label, 'Receita');
    });

    test('de pacientes diferentes continuam separados', () {
      final due = addDays(now, 10);
      data.replaceAll(
        patients: [_patient('p1'), _patient('p2')],
        prescriptions: [rx('r1', 'p1', 'Metformina', due), rx('r2', 'p2', 'Metformina', due)],
      );
      expect(data.reminders, hasLength(2));
      expect(data.reminders.every((r) => r.sources.length == 1), isTrue);
    });
  });

  test('receituários do paciente: agrupados, mais recente primeiro', () {
    Prescription rx(String id, String? group, String med, DateTime issued) => Prescription(
          id: id,
          patientId: 'p1',
          medication: med,
          issuedAt: issued,
          expiresAt: addDays(issued, 30),
          groupId: group,
        );
    data.replaceAll(patients: [
      _patient('p1')
    ], prescriptions: [
      rx('r1', 'g1', 'Metformina', addDays(now, -60)),
      rx('r2', 'g1', 'Glicazida', addDays(now, -60)),
      rx('r3', null, 'Losartana', addDays(now, -90)), // anterior à v1.3
      rx('r4', 'g2', 'AAS', addDays(now, -5)),
    ]);
    final groups = data.receituariosOf('p1');
    expect(groups.map((g) => g.map((r) => r.id).toList()), [
      ['r4'],
      ['r2', 'r1'],
      ['r3'],
    ]);
  });

  group('linhas de cuidado do paciente', () {
    test('várias linhas: grava a primeira também em care_line_id', () {
      final p = Patient(id: 'p1', name: 'X', careLineIds: ['cl-diabetes', 'cl-hipertensao']);
      final map = p.toMap();
      expect(map['care_line_ids'], 'cl-diabetes,cl-hipertensao');
      expect(map['care_line_id'], 'cl-diabetes');
      expect(Patient.fromMap(map).careLineIds, ['cl-diabetes', 'cl-hipertensao']);
    });

    test('registro anterior à v1.3 só tem care_line_id', () {
      final map = Patient(id: 'p1', name: 'X').toMap()
        ..remove('care_line_ids')
        ..['care_line_id'] = 'cl-diabetes';
      expect(Patient.fromMap(map).careLineIds, ['cl-diabetes']);
    });

    test('alteração feita por um aparelho com versão anterior do app prevalece', () {
      final map = Patient(id: 'p1', name: 'X', careLineIds: ['cl-diabetes', 'cl-hipertensao']).toMap();
      // A versão anterior trocou a linha (só conhece care_line_id).
      expect(Patient.fromMap({...map, 'care_line_id': 'cl-saude-idoso'}).careLineIds, ['cl-saude-idoso']);
      // A versão anterior tirou a linha.
      expect(Patient.fromMap({...map, 'care_line_id': null}).careLineIds, isEmpty);
    });

    test('linha excluída não aparece', () {
      data.replaceAll(
        careLines: [CareLine(id: 'cl-diabetes', name: 'Diabetes', color: 0)],
        patients: [Patient(id: 'p1', name: 'X', careLineIds: ['cl-excluida', 'cl-diabetes'])],
      );
      expect(data.careLinesOf(data.patient('p1')).map((l) => l.id), ['cl-diabetes']);
    });
  });
}
