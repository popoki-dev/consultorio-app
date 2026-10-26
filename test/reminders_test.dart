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
      careLineId: 'cl-diabetes',
      cidCodes: ['E11'],
      notes: 'Alergia a dipirona',
    )..scrub();
    final map = p.toMap();
    for (final k in ['birth_date', 'sex', 'phone', 'document', 'care_line_id', 'notes']) {
      expect(map[k], isNull, reason: k);
    }
    expect(map['name'], '');
    expect(map['cid_codes'], '');
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
}
