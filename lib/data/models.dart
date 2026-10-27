import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';

bool _bool(Object? v) => v == 1 || v == true || v == '1';
int _int(Object? v, int fallback) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? fallback;
}

String? _str(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

/// Lista gravada como texto separado por vírgulas.
List<String> _list(Object? v) => (_str(v) ?? '')
    .split(',')
    .map((c) => c.trim())
    .where((c) => c.isNotEmpty)
    .toList();

/// Base de todos os registros sincronizados: UUID, carimbo de alteração
/// (para resolver conflitos) e exclusão lógica (para a exclusão sincronizar).
abstract class Entity {
  Entity(this.id, String? updatedAt, this.deletedAt)
      : updatedAt = updatedAt ?? nowUtcIso();

  final String id;
  String updatedAt;
  String? deletedAt;

  String get tableName;
  Map<String, Object?> toMap();

  /// Apaga o conteúdo pessoal ao excluir (LGPD, art. 18, VI). Fica só o
  /// marcador (id e datas), necessário para a exclusão chegar ao outro
  /// aparelho.
  void scrub() {}
}

class CareLine extends Entity {
  CareLine({
    required String id,
    required this.name,
    required this.color,
    this.defaultReturnDays,
    String? updatedAt,
    String? deletedAt,
  }) : super(id, updatedAt, deletedAt);

  static const table = 'care_lines';

  String name;
  int color;
  int? defaultReturnDays;

  Color get colorValue => Color(color);

  @override
  String get tableName => table;

  @override
  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'color': color,
        'default_return_days': defaultReturnDays,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  static CareLine fromMap(Map<String, Object?> m) => CareLine(
        id: m['id'] as String,
        name: _str(m['name']) ?? '',
        color: _int(m['color'], AppColors.careLinePalette.first.toARGB32()),
        defaultReturnDays:
            m['default_return_days'] == null ? null : _int(m['default_return_days'], 90),
        updatedAt: _str(m['updated_at']),
        deletedAt: _str(m['deleted_at']),
      );
}

class Sex {
  static const female = 'F';
  static const male = 'M';
  static const other = 'O';
  static const values = [female, male, other];

  static String label(String? s) => switch (s) {
        female => 'Feminino',
        male => 'Masculino',
        other => 'Outro',
        _ => 'Não informado',
      };
}

class Patient extends Entity {
  Patient({
    required String id,
    required this.name,
    this.birthDate,
    this.sex,
    this.phone,
    this.document,
    List<String>? careLineIds,
    List<String>? cidCodes,
    this.notes,
    this.dum,
    this.pregnancyEnd,
    String? createdAt,
    String? updatedAt,
    String? deletedAt,
  })  : careLineIds = careLineIds ?? [],
        cidCodes = cidCodes ?? [],
        createdAt = createdAt ?? nowUtcIso(),
        super(id, updatedAt, deletedAt);

  static const table = 'patients';

  String name;
  DateTime? birthDate;
  String? sex;
  String? phone;
  String? document;

  /// Linhas de cuidado do paciente (pode estar em várias). A primeira dá a
  /// cor do avatar.
  List<String> careLineIds;
  List<String> cidCodes;
  String? notes;

  /// Data da última menstruação da gestação atual (informada ou calculada
  /// a partir da idade gestacional de um ultrassom).
  DateTime? dum;

  /// Parto ou encerramento da gestação registrada em [dum].
  DateTime? pregnancyEnd;
  final String createdAt;

  int? get age => birthDate == null ? null : ageOn(birthDate!, DateTime.now());

  /// Gestação em acompanhamento (ver care_rules.dart para os cálculos).
  bool get pregnant => dum != null && pregnancyEnd == null;

  @override
  String get tableName => table;

  @override
  void scrub() {
    name = '';
    birthDate = null;
    sex = null;
    phone = null;
    document = null;
    careLineIds = [];
    cidCodes = [];
    notes = null;
    dum = null;
    pregnancyEnd = null;
  }

  @override
  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'birth_date': birthDate == null ? null : dateKey(birthDate!),
        'sex': sex,
        'phone': phone,
        'document': document,
        // Primeira linha também em care_line_id, que é o que um aparelho com
        // versão anterior do app lê e grava.
        'care_line_id': careLineIds.firstOrNull,
        'care_line_ids': careLineIds.join(','),
        'cid_codes': cidCodes.join(','),
        'notes': notes,
        'dum': dum == null ? null : dateKey(dum!),
        'pregnancy_end': pregnancyEnd == null ? null : dateKey(pregnancyEnd!),
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  static Patient fromMap(Map<String, Object?> m) => Patient(
        id: m['id'] as String,
        name: _str(m['name']) ?? '',
        birthDate: parseDate(m['birth_date']),
        sex: _str(m['sex']),
        phone: _str(m['phone']),
        document: _str(m['document']),
        careLineIds: _careLineIds(m),
        cidCodes: _list(m['cid_codes']),
        notes: _str(m['notes']),
        dum: parseDate(m['dum']),
        pregnancyEnd: parseDate(m['pregnancy_end']),
        createdAt: _str(m['created_at']),
        updatedAt: _str(m['updated_at']),
        deletedAt: _str(m['deleted_at']),
      );

  /// Esta versão grava care_line_id igual à primeira de care_line_ids.
  /// Se forem diferentes, o registro foi alterado por um aparelho com versão
  /// anterior do app (só conhece care_line_id) e vale a escolha dele.
  /// Registros anteriores à v1.3 não têm care_line_ids.
  static List<String> _careLineIds(Map<String, Object?> m) {
    final single = _str(m['care_line_id']);
    if (m['care_line_ids'] == null) return [if (single != null) single];
    final ids = _list(m['care_line_ids']);
    if (ids.firstOrNull == single) return ids;
    return [if (single != null) single];
  }
}

class ApptStatus {
  static const scheduled = 'scheduled';
  static const done = 'done';
  static const missed = 'missed';
  static const cancelled = 'cancelled';

  static String label(String s) => switch (s) {
        scheduled => 'Agendada',
        done => 'Realizada',
        missed => 'Faltou',
        cancelled => 'Cancelada',
        _ => s,
      };

  static Color color(String s) => switch (s) {
        done => AppColors.okSoft,
        missed => AppColors.dangerSoft,
        cancelled => AppColors.hairline,
        _ => AppColors.yellowSoft,
      };
}

class Appointment extends Entity {
  Appointment({
    required String id,
    required this.patientId,
    required this.startAt,
    this.durationMin = 30,
    this.status = ApptStatus.scheduled,
    this.notes,
    this.returnDue,
    this.returnResolved = false,
    String? updatedAt,
    String? deletedAt,
  }) : super(id, updatedAt, deletedAt);

  static const table = 'appointments';

  String patientId;
  DateTime startAt;
  int durationMin;
  String status;
  String? notes;

  /// Previsão de retorno definida ao concluir a consulta.
  DateTime? returnDue;
  bool returnResolved;

  DateTime get endAt => startAt.add(Duration(minutes: durationMin));

  @override
  String get tableName => table;

  @override
  void scrub() {
    notes = null;
    returnDue = null;
  }

  @override
  Map<String, Object?> toMap() => {
        'id': id,
        'patient_id': patientId,
        'start_at': localIso(startAt),
        'duration_min': durationMin,
        'status': status,
        'notes': notes,
        'return_due': returnDue == null ? null : dateKey(returnDue!),
        'return_resolved': returnResolved ? 1 : 0,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  static Appointment fromMap(Map<String, Object?> m) => Appointment(
        id: m['id'] as String,
        patientId: m['patient_id'] as String,
        startAt: parseDate(m['start_at']) ?? DateTime.now(),
        durationMin: _int(m['duration_min'], 30),
        status: _str(m['status']) ?? ApptStatus.scheduled,
        notes: _str(m['notes']),
        returnDue: parseDate(m['return_due']),
        returnResolved: _bool(m['return_resolved']),
        updatedAt: _str(m['updated_at']),
        deletedAt: _str(m['deleted_at']),
      );
}

class Prescription extends Entity {
  Prescription({
    required String id,
    required this.patientId,
    required this.medication,
    this.dosage,
    required this.issuedAt,
    required this.expiresAt,
    this.resolved = false,
    this.notes,
    this.groupId,
    String? updatedAt,
    String? deletedAt,
  }) : super(id, updatedAt, deletedAt);

  static const table = 'prescriptions';

  String patientId;
  String medication;
  String? dosage;
  DateTime issuedAt;
  DateTime expiresAt;

  /// Receita já renovada ou encerrada: não gera mais lembrete.
  bool resolved;
  String? notes;

  /// Receituário a que pertence: medicamentos emitidos juntos compartilham
  /// data e observações, mas cada um tem a própria validade. Receitas
  /// anteriores à v1.3 não têm: cada uma é um receituário.
  String? groupId;
  String get groupKey => groupId ?? id;

  bool get isExpired => expiresAt.isBefore(today());

  @override
  String get tableName => table;

  @override
  void scrub() {
    medication = '';
    dosage = null;
    notes = null;
  }

  @override
  Map<String, Object?> toMap() => {
        'id': id,
        'patient_id': patientId,
        'medication': medication,
        'dosage': dosage,
        'issued_at': dateKey(issuedAt),
        'expires_at': dateKey(expiresAt),
        'resolved': resolved ? 1 : 0,
        'notes': notes,
        'group_id': groupId,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  static Prescription fromMap(Map<String, Object?> m) => Prescription(
        id: m['id'] as String,
        patientId: m['patient_id'] as String,
        medication: _str(m['medication']) ?? '',
        dosage: _str(m['dosage']),
        issuedAt: parseDate(m['issued_at']) ?? today(),
        expiresAt: parseDate(m['expires_at']) ?? today(),
        resolved: _bool(m['resolved']),
        notes: _str(m['notes']),
        groupId: _str(m['group_id']),
        updatedAt: _str(m['updated_at']),
        deletedAt: _str(m['deleted_at']),
      );
}

class Exam extends Entity {
  Exam({
    required String id,
    required this.patientId,
    required this.name,
    required this.performedAt,
    this.result = '',
    this.nextDue,
    this.resolved = false,
    String? updatedAt,
    String? deletedAt,
  }) : super(id, updatedAt, deletedAt);

  static const table = 'exams';

  String patientId;
  String name;
  DateTime performedAt;
  String result;

  /// Data para repetir o exame (gera lembrete).
  DateTime? nextDue;
  bool resolved;

  @override
  String get tableName => table;

  @override
  void scrub() {
    name = '';
    result = '';
    nextDue = null;
  }

  @override
  Map<String, Object?> toMap() => {
        'id': id,
        'patient_id': patientId,
        'name': name,
        'performed_at': dateKey(performedAt),
        'result': result,
        'next_due': nextDue == null ? null : dateKey(nextDue!),
        'resolved': resolved ? 1 : 0,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  static Exam fromMap(Map<String, Object?> m) => Exam(
        id: m['id'] as String,
        patientId: m['patient_id'] as String,
        name: _str(m['name']) ?? '',
        performedAt: parseDate(m['performed_at']) ?? today(),
        result: _str(m['result']) ?? '',
        nextDue: parseDate(m['next_due']),
        resolved: _bool(m['resolved']),
        updatedAt: _str(m['updated_at']),
        deletedAt: _str(m['deleted_at']),
      );
}

enum ReminderKind {
  returnVisit('Retorno', Icons.event_repeat_rounded, AppColors.green, 7),
  prescription('Receita', Icons.medication_outlined, AppColors.salmon, 7),
  exam('Exame', Icons.biotech_outlined, AppColors.purple, 7);

  const ReminderKind(this.label, this.icon, this.color, this.defaultLeadDays);
  final String label;
  final IconData icon;
  final Color color;
  final int defaultLeadDays;
}

/// Lembrete derivado dos dados (não é armazenado): retorno previsto,
/// receita vencendo ou exame a repetir. Medicamentos do mesmo paciente que
/// vencem no mesmo dia formam um lembrete só (uma notificação).
class Reminder {
  Reminder({
    required this.kind,
    required this.patient,
    required this.due,
    required this.title,
    required this.sources,
  }) : assert(sources.isNotEmpty);

  final ReminderKind kind;
  final Patient patient;
  final DateTime due;
  final String title;

  /// Registros de origem (vários quando são medicamentos vencendo juntos).
  final List<Entity> sources;
  Entity get source => sources.first;

  /// "Receita" ou "Receitas (3)".
  String get label => sources.length == 1 ? kind.label : '${kind.label}s (${sources.length})';

  bool get overdue => due.isBefore(today());
  int get daysLeft => daysBetween(today(), due);
}
