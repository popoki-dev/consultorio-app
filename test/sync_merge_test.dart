import 'dart:convert';

import 'package:consultorio/data/app_data.dart';
import 'package:consultorio/data/local_db.dart';
import 'package:consultorio/data/models.dart';
import 'package:consultorio/services/settings.dart';
import 'package:consultorio/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const t1 = '2026-10-01T10:00:00.000Z';
const t2 = '2026-10-02T10:00:00.000Z';
const t3 = '2026-10-03T10:00:00.000Z';

Map<String, Object?> _patient(String id, String name, String updatedAt) =>
    Patient(id: id, name: name, createdAt: t1, updatedAt: updatedAt).toMap();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late LocalDb db;
  late SyncService sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = LocalDb();
    await db.openForTest(databaseFactoryFfi, inMemoryDatabasePath);
    sync = SyncService(db, AppData(db), await AppSettings.load());
  });
  tearDown(() => db.db.close());

  Future<Map<String, Object?>> row(String id) async => (await db.byId('patients', id))!;

  Future<List<String>> conflictNames() async => [
        for (final c in await db.db.query('sync_conflicts'))
          (jsonDecode(c['payload'] as String) as Map)['name'] as String,
      ];

  test('linha nova do servidor entra como já sincronizada', () async {
    expect(await sync.merge('patients', _patient('p1', 'Ana', t1)), isTrue);
    final r = await row('p1');
    expect(r['dirty'], 0);
    expect(r['base_updated_at'], t1);
  });

  test('versão que o aparelho já conhece é ignorada, mesmo com edição pendente', () async {
    await db.write('patients', _patient('p1', 'Ana', t1), dirty: false);
    await db.write('patients', _patient('p1', 'Ana Maria', t2));

    expect(await sync.merge('patients', _patient('p1', 'Ana', t1)), isFalse);
    final r = await row('p1');
    expect(r['name'], 'Ana Maria');
    expect(r['dirty'], 1);
    expect(await db.conflictCount(), 0);
  });

  test('sem edição local, a versão nova do servidor substitui a local', () async {
    await db.write('patients', _patient('p1', 'Ana', t1), dirty: false);

    expect(await sync.merge('patients', _patient('p1', 'Ana Beatriz', t2)), isTrue);
    final r = await row('p1');
    expect(r['name'], 'Ana Beatriz');
    expect(r['dirty'], 0);
    expect(r['base_updated_at'], t2);
    expect(await db.conflictCount(), 0);
  });

  test('conflito: servidor mais novo vence e a versão local é guardada', () async {
    await db.write('patients', _patient('p1', 'Ana', t1), dirty: false);
    await db.write('patients', _patient('p1', 'Editado aqui', t2));

    expect(await sync.merge('patients', _patient('p1', 'Editado no outro', t3)), isTrue);
    final r = await row('p1');
    expect(r['name'], 'Editado no outro');
    expect(r['dirty'], 0);
    expect(await conflictNames(), ['Editado aqui']);
    final payload = (await db.db.query('sync_conflicts')).single['payload'] as String;
    expect(payload, isNot(contains('dirty')), reason: 'cópia sem colunas locais');
  });

  test('conflito: local mais novo continua pendente e não repete o conflito', () async {
    await db.write('patients', _patient('p1', 'Ana', t1), dirty: false);
    await db.write('patients', _patient('p1', 'Editado aqui', t3));

    expect(await sync.merge('patients', _patient('p1', 'Editado no outro', t2)), isFalse);
    var r = await row('p1');
    expect(r['name'], 'Editado aqui');
    expect(r['dirty'], 1);
    expect(r['base_updated_at'], t2);
    expect(await conflictNames(), ['Editado no outro']);

    // A sobreposição do cursor traz a mesma versão de novo.
    expect(await sync.merge('patients', _patient('p1', 'Editado no outro', t2)), isFalse);
    r = await row('p1');
    expect(r['dirty'], 1);
    expect(await db.conflictCount(), 1);
  });

  test('envio sem confirmação: a mesma versão só marca como sincronizada', () async {
    await db.write('patients', _patient('p1', 'Ana', t2));

    expect(await sync.merge('patients', _patient('p1', 'Ana', t2)), isFalse);
    final r = await row('p1');
    expect(r['dirty'], 0);
    expect(r['base_updated_at'], t2);
    expect(await db.conflictCount(), 0);
  });

  test('linha de cuidado padrão criada pelo app não gera conflito', () async {
    await AppData(db).ensureDefaults();
    final remote = CareLine(
      id: 'cl-hipertensao',
      name: 'Hipertensão arterial',
      color: 0xFFF2A394,
      defaultReturnDays: 60,
      updatedAt: t1,
    ).toMap();

    expect(await sync.merge('care_lines', remote), isTrue);
    final r = (await db.byId('care_lines', 'cl-hipertensao'))!;
    expect(r['name'], 'Hipertensão arterial');
    expect(r['dirty'], 0);
    expect(await db.conflictCount(), 0);
  });
}
