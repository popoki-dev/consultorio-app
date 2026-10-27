import 'dart:convert';

import 'package:consultorio/data/app_data.dart';
import 'package:consultorio/data/local_db.dart';
import 'package:consultorio/data/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const t1 = '2026-10-01T10:00:00.000Z';
const t2 = '2026-10-02T10:00:00.000Z';
const t3 = '2026-10-03T10:00:00.000Z';

Map<String, Object?> _patient(String id, String name, String updatedAt) =>
    Patient(id: id, name: name, createdAt: t1, updatedAt: updatedAt).toMap();

Map<String, Object?> _backup({List<Map<String, Object?>> patients = const []}) =>
    {'app': 'consultorio', 'exported_at': t3, 'patients': patients};

Future<LocalDb> _openDb() async {
  final db = LocalDb();
  await db.openForTest(databaseFactoryFfi, inMemoryDatabasePath);
  return db;
}

void main() {
  setUpAll(sqfliteFfiInit);

  late LocalDb db;
  setUp(() async => db = await _openDb());
  tearDown(() => db.db.close());

  group('restaurar backup', () {
    test('arquivo de outro app é recusado', () async {
      expect(() => db.importAll({'app': 'outro'}), throwsA(isA<FormatException>()));
    });

    test('restaura o que falta e não sobrescreve o que é mais novo', () async {
      await db.write('patients', _patient('p1', 'Novo no aparelho', t3), dirty: false);
      await db.write('patients', _patient('p2', 'Velho no aparelho', t1), dirty: false);

      final n = await db.importAll(_backup(patients: [
        _patient('p1', 'Do backup', t2),
        _patient('p2', 'Atualizado pelo backup', t2),
        _patient('p3', 'Só no backup', t1),
      ]));

      expect(n, 2);
      expect((await db.byId('patients', 'p1'))!['name'], 'Novo no aparelho');
      final p2 = (await db.byId('patients', 'p2'))!;
      expect(p2['name'], 'Atualizado pelo backup');
      expect(p2['dirty'], 1, reason: 'restaurado precisa sincronizar');
      expect((await db.byId('patients', 'p3'))!['dirty'], 1);
    });

    test('arquivo com um registro inválido não altera nada', () async {
      final file = _backup(patients: [
        _patient('p1', 'Válido', t1),
        {'name': 'Sem id'},
      ]);
      await expectLater(db.importAll(file), throwsA(isA<FormatException>()));
      expect(await db.byId('patients', 'p1'), isNull);
    });

    test('colunas desconhecidas e colunas locais do arquivo são ignoradas', () async {
      final row = {
        ..._patient('p1', 'Ana', t1),
        'coluna_de_versao_futura': 'x',
        'dirty': 0,
        'base_updated_at': t1,
      };
      expect(await db.importAll(_backup(patients: [row])), 1);
      final saved = (await db.byId('patients', 'p1'))!;
      expect(saved.containsKey('coluna_de_versao_futura'), isFalse);
      expect(saved['dirty'], 1);
      expect(saved['base_updated_at'], isNull,
          reason: 'o arquivo não pode dizer qual versão o servidor tem');
    });

    test('exportar e restaurar em outro aparelho recupera tudo, menos o excluído', () async {
      await db.write('patients', _patient('p1', 'Ana', t1));
      await db.write('patients', {..._patient('p2', '', t2), 'deleted_at': t2});
      await db.write(
        'appointments',
        Appointment(id: 'a1', patientId: 'p1', startAt: DateTime(2026, 10, 5, 9), updatedAt: t1)
            .toMap(),
      );

      final exported = jsonDecode(jsonEncode(await db.exportAll())) as Map<String, Object?>;
      final patients = exported['patients'] as List;
      expect(patients.map((r) => (r as Map)['id']), ['p1']);
      expect((patients.single as Map).containsKey('dirty'), isFalse);

      final other = await _openDb();
      addTearDown(other.db.close);
      expect(await other.importAll(exported), 2);
      expect((await other.byId('patients', 'p1'))!['name'], 'Ana');
      expect((await other.byId('appointments', 'a1'))!['start_at'], '2026-10-05T09:00:00');
      expect(await other.byId('patients', 'p2'), isNull);
    });
  });

  test('excluir paciente apaga dados pessoais, consultas, receitas e cópias de conflito', () async {
    final data = AppData(db);
    final patient = Patient(id: 'p1', name: 'Maria Silva', phone: '11999990000');
    await data.savePatient(patient);
    await data.saveAppointment(
        Appointment(id: 'a1', patientId: 'p1', startAt: DateTime(2026, 10, 5, 9)));
    await data.savePrescription(Prescription(
      id: 'r1',
      patientId: 'p1',
      medication: 'Sertralina',
      issuedAt: DateTime(2026, 10, 1),
      expiresAt: DateTime(2026, 11, 1),
    ));
    await db.addConflict('patients', 'p1', _patient('p1', 'Maria (outro aparelho)', t1));

    await data.delete(data.patient('p1')!);

    final p = (await db.byId('patients', 'p1'))!;
    expect(p['deleted_at'], isNotNull);
    expect(p['name'], '');
    expect(p['phone'], isNull);
    expect((await db.byId('appointments', 'a1'))!['deleted_at'], isNotNull);
    final rx = (await db.byId('prescriptions', 'r1'))!;
    expect(rx['deleted_at'], isNotNull);
    expect(rx['medication'], '');
    expect(await db.conflictCount(), 0);
    expect(data.patients, isEmpty);
    expect(data.appointments, isEmpty);
  });
}
