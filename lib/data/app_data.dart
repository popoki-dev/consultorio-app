import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import 'local_db.dart';
import 'models.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Fonte única dos dados do app. Tudo é lido do banco local cifrado e mantido
/// em memória (um consultório tem poucos milhares de registros), então todas
/// as telas funcionam offline e respondem instantaneamente.
class AppData extends ChangeNotifier {
  AppData(this.db);

  final LocalDb db;

  /// Chamado após cada alteração feita no aparelho (dispara a sincronização).
  VoidCallback? onLocalWrite;

  List<CareLine> careLines = [];
  List<Patient> patients = [];
  List<Appointment> appointments = [];
  List<Prescription> prescriptions = [];
  List<Exam> exams = [];

  final Map<String, Patient> _patients = {};
  final Map<String, CareLine> _careLines = {};
  List<Reminder>? _reminders;

  // ---------------------------------------------------------------- carga

  static const prenatalLineId = 'cl-pre-natal';
  static const infantLineId = 'cl-puericultura';

  static const defaultCareLines = [
    ('cl-hipertensao', 'Hipertensão', 0xFFF2A394, 90),
    ('cl-diabetes', 'Diabetes', 0xFF8FC9A3, 90),
    (prenatalLineId, 'Pré-natal', 0xFFF6C453, 28),
    (infantLineId, 'Puericultura', 0xFF9FD3D0, 30),
    ('cl-saude-mental', 'Saúde Mental', 0xFFB9A2DE, 30),
    ('cl-saude-mulher', 'Saúde da Mulher', 0xFFE79BC0, 180),
    ('cl-saude-idoso', 'Saúde do Idoso', 0xFF8DB8E3, 90),
  ];

  /// Versão das linhas criadas pelo app: mais antiga que qualquer edição,
  /// então a versão do servidor sempre prevalece sobre ela.
  static const seedVersion = '2000-01-01T00:00:00.000Z';

  /// Linhas de cuidado iniciais (editáveis). IDs fixos para que dois
  /// aparelhos não criem cópias duplicadas. Uma linha que já existiu (mesmo
  /// excluída) não é recriada; linhas novas de versões futuras do app são
  /// acrescentadas.
  Future<void> ensureDefaults() async {
    for (final (id, name, color, days) in defaultCareLines) {
      if (await db.byId(CareLine.table, id) != null) continue;
      final line = CareLine(
        id: id,
        name: name,
        color: color,
        defaultReturnDays: days,
        updatedAt: seedVersion,
      );
      await db.write(CareLine.table, line.toMap());
    }
  }

  Future<void> load() async {
    replaceAll(
      careLines: (await db.active(CareLine.table)).map(CareLine.fromMap),
      patients: (await db.active(Patient.table)).map(Patient.fromMap),
      appointments: (await db.active(Appointment.table)).map(Appointment.fromMap),
      prescriptions: (await db.active(Prescription.table)).map(Prescription.fromMap),
      exams: (await db.active(Exam.table)).map(Exam.fromMap),
    );
  }

  /// Ordena, indexa e descarta registros de pacientes inexistentes.
  /// Público para os testes montarem dados sem banco.
  @visibleForTesting
  void replaceAll({
    Iterable<CareLine> careLines = const [],
    Iterable<Patient> patients = const [],
    Iterable<Appointment> appointments = const [],
    Iterable<Prescription> prescriptions = const [],
    Iterable<Exam> exams = const [],
  }) {
    this.careLines = careLines.toList()
      ..sort((a, b) => normalize(a.name).compareTo(normalize(b.name)));
    this.patients = patients.toList()
      ..sort((a, b) => normalize(a.name).compareTo(normalize(b.name)));
    _patients
      ..clear()
      ..addEntries(this.patients.map((p) => MapEntry(p.id, p)));
    _careLines
      ..clear()
      ..addEntries(this.careLines.map((c) => MapEntry(c.id, c)));

    this.appointments = appointments.where((a) => _patients.containsKey(a.patientId)).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    this.prescriptions = prescriptions.where((r) => _patients.containsKey(r.patientId)).toList()
      ..sort((a, b) => b.expiresAt.compareTo(a.expiresAt));
    this.exams = exams.where((e) => _patients.containsKey(e.patientId)).toList()
      ..sort((a, b) => b.performedAt.compareTo(a.performedAt));

    _reminders = null;
    notifyListeners();
  }

  // ------------------------------------------------------------- consultas

  Patient? patient(String? id) => id == null ? null : _patients[id];
  CareLine? careLine(String? id) => id == null ? null : _careLines[id];

  /// Linhas de cuidado do paciente que ainda existem, na ordem do cadastro.
  List<CareLine> careLinesOf(Patient? p) => [
        if (p != null)
          for (final id in p.careLineIds)
            if (_careLines[id] case final line?) line,
      ];

  List<Appointment> appointmentsOn(DateTime day) =>
      appointments.where((a) => sameDay(a.startAt, day)).toList();

  List<Appointment> appointmentsOf(String patientId) =>
      appointments.where((a) => a.patientId == patientId).toList().reversed.toList();

  List<Prescription> prescriptionsOf(String patientId) =>
      prescriptions.where((r) => r.patientId == patientId).toList();

  /// Receituários do paciente, do mais recente ao mais antigo; os
  /// medicamentos de cada um em ordem alfabética.
  List<List<Prescription>> receituariosOf(String patientId) {
    final groups = <String, List<Prescription>>{};
    for (final r in prescriptionsOf(patientId)) {
      groups.putIfAbsent(r.groupKey, () => []).add(r);
    }
    for (final g in groups.values) {
      g.sort((a, b) => normalize(a.medication).compareTo(normalize(b.medication)));
    }
    return groups.values.toList()..sort((a, b) => b.first.issuedAt.compareTo(a.first.issuedAt));
  }

  List<Exam> examsOf(String patientId) =>
      exams.where((e) => e.patientId == patientId).toList();

  /// Última consulta realizada.
  Appointment? lastVisit(String patientId) {
    for (final a in appointments.reversed) {
      if (a.patientId == patientId && a.status == ApptStatus.done) return a;
    }
    return null;
  }

  /// Próxima consulta agendada (hoje ou depois).
  Appointment? nextAppointment(String patientId) {
    final start = today();
    for (final a in appointments) {
      if (a.patientId == patientId &&
          a.status == ApptStatus.scheduled &&
          !a.startAt.isBefore(start)) {
        return a;
      }
    }
    return null;
  }

  Map<String, DateTime> lastVisitByPatient() {
    final map = <String, DateTime>{};
    for (final a in appointments) {
      if (a.status == ApptStatus.done) map[a.patientId] = a.startAt;
    }
    return map;
  }

  /// Lembretes pendentes, do mais urgente ao mais distante.
  List<Reminder> get reminders => _reminders ??= _computeReminders();

  List<Reminder> remindersOf(String patientId) =>
      reminders.where((r) => r.patient.id == patientId).toList();

  List<Reminder> _computeReminders() {
    final out = <Reminder>[];

    // Retorno: a consulta realizada mais recente com previsão de retorno,
    // desde que ainda não exista consulta posterior realizada ou marcada
    // para hoje em diante (uma consulta passada que segue "Agendada" não
    // foi registrada como atendida, então o retorno continua pendente).
    final start = today();
    final byPatient = <String, List<Appointment>>{};
    for (final a in appointments) {
      if (a.status == ApptStatus.cancelled) continue;
      byPatient.putIfAbsent(a.patientId, () => []).add(a);
    }
    byPatient.forEach((pid, list) {
      Appointment? source;
      for (final a in list.reversed) {
        if (a.status == ApptStatus.done && a.returnDue != null) {
          source = a;
          break;
        }
      }
      if (source == null || source.returnResolved) return;
      final src = source;
      final hasLater = list.any((x) =>
          x.startAt.isAfter(src.startAt) &&
          (x.status == ApptStatus.done ||
              (x.status == ApptStatus.scheduled && !x.startAt.isBefore(start))));
      if (hasLater) return;
      out.add(Reminder(
        kind: ReminderKind.returnVisit,
        patient: _patients[pid]!,
        due: src.returnDue!,
        title: 'Retorno previsto (última consulta ${fmtDate(src.startAt)})',
        sources: [src],
      ));
    });

    // Medicamentos do mesmo paciente que vencem no mesmo dia viram um
    // lembrete só, mesmo que sejam de receituários diferentes.
    final rxByDue = <(String, DateTime), List<Prescription>>{};
    for (final r in prescriptions) {
      if (r.resolved) continue;
      rxByDue.putIfAbsent((r.patientId, dateOnly(r.expiresAt)), () => []).add(r);
    }
    rxByDue.forEach((key, list) {
      list.sort((a, b) => normalize(a.medication).compareTo(normalize(b.medication)));
      final only = list.length == 1 ? list.single : null;
      out.add(Reminder(
        kind: ReminderKind.prescription,
        patient: _patients[key.$1]!,
        due: key.$2,
        title: only != null
            ? 'Receita: ${only.medication}${only.dosage == null ? '' : ' · ${only.dosage}'}'
            : 'Receitas: ${list.map((r) => r.medication).join(', ')}',
        sources: list,
      ));
    });

    for (final e in exams) {
      if (e.resolved || e.nextDue == null) continue;
      out.add(Reminder(
        kind: ReminderKind.exam,
        patient: _patients[e.patientId]!,
        due: e.nextDue!,
        title: 'Repetir exame: ${e.name}',
        sources: [e],
      ));
    }

    out.sort((a, b) => a.due.compareTo(b.due));
    return out;
  }

  // ------------------------------------------------------------- gravação

  Future<void> _save(Entity e) => _saveAll([e]);

  /// Grava tudo numa única transação.
  Future<void> _saveAll(List<Entity> entities) async {
    final now = nowUtcIso();
    final byTable = <String, List<Map<String, Object?>>>{};
    for (final e in entities) {
      e.updatedAt = now;
      byTable.putIfAbsent(e.tableName, () => []).add(e.toMap());
    }
    try {
      await db.writeAll(byTable);
    } finally {
      // As telas editam o objeto em memória antes de salvar; recarregar
      // também em caso de erro desfaz o que não chegou ao banco.
      await load();
    }
    onLocalWrite?.call();
  }

  Future<void> saveCareLine(CareLine c) => _save(c);
  Future<void> savePatient(Patient p) => _save(p);
  Future<void> saveAppointment(Appointment a) => _save(a);
  Future<void> saveExam(Exam e) => _save(e);

  /// Grava um receituário numa única transação. [removed] são os
  /// medicamentos tirados dele na edição. Uma receita nova de um
  /// medicamento encerra as anteriores do mesmo medicamento (deixam de
  /// gerar lembrete).
  Future<void> saveReceituario(
    List<Prescription> items, {
    List<Prescription> removed = const [],
  }) async {
    final mine = {...items.map((r) => r.id), ...removed.map((r) => r.id)};
    final rows = <Entity>[...items];
    for (final item in items) {
      final key = normalize(item.medication.trim());
      for (final old in prescriptions) {
        if (!mine.contains(old.id) &&
            old.patientId == item.patientId &&
            !old.resolved &&
            normalize(old.medication.trim()) == key &&
            !old.issuedAt.isAfter(item.issuedAt)) {
          old.resolved = true;
          mine.add(old.id);
          rows.add(old);
        }
      }
    }
    final now = nowUtcIso();
    for (final r in removed) {
      r
        ..scrub()
        ..deletedAt = now;
      rows.add(r);
    }
    await _saveAll(rows);
    if (removed.isNotEmpty) await db.purgeConflicts(removed.map((r) => r.id));
  }

  Future<void> delete(Entity e) => deleteMany([e]);

  /// Exclusão em uma única transação. Excluir um paciente exclui também
  /// consultas, receitas e exames dele. O registro vira um marcador sem
  /// dados pessoais ([Entity.scrub]); o marcador é o que leva a exclusão
  /// ao outro aparelho.
  Future<void> deleteMany(Iterable<Entity> entities) async {
    final now = nowUtcIso();
    final rows = <Entity>[];
    for (final e in entities) {
      rows.add(e);
      if (e is Patient) {
        rows
          ..addAll(appointments.where((a) => a.patientId == e.id))
          ..addAll(prescriptions.where((r) => r.patientId == e.id))
          ..addAll(exams.where((x) => x.patientId == e.id));
      }
    }
    if (rows.isEmpty) return;
    final byTable = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      r
        ..scrub()
        ..deletedAt = now
        ..updatedAt = now;
      byTable.putIfAbsent(r.tableName, () => []).add(r.toMap());
    }
    try {
      await db.writeAll(byTable);
      await db.purgeConflicts(rows.map((r) => r.id));
    } finally {
      await load();
    }
    onLocalWrite?.call();
  }

  Future<void> setReminderResolved(Reminder r, bool resolved) async {
    for (final s in r.sources) {
      if (s is Appointment) {
        s.returnResolved = resolved;
      } else if (s is Prescription) {
        s.resolved = resolved;
      } else if (s is Exam) {
        s.resolved = resolved;
      }
    }
    await _saveAll(r.sources);
  }

  Future<void> insertBulk(Map<String, List<Entity>> rows) async {
    await db.writeAll(rows.map((t, list) => MapEntry(t, list.map((e) => e.toMap()).toList())));
    await load();
    onLocalWrite?.call();
  }

  /// Restaura um backup exportado (ver [LocalDb.importAll]).
  Future<int> importBackup(Map<String, Object?> json) async {
    final n = await db.importAll(json);
    await load();
    if (n > 0) onLocalWrite?.call();
    return n;
  }
}
