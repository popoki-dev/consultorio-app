import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../core/format.dart';

/// Banco SQLite cifrado com SQLCipher. A chave (256 bits aleatórios) fica no
/// Android Keystore / iOS Keychain e nunca sai do aparelho.
class LocalDb {
  static const syncedTables = [
    'care_lines',
    'patients',
    'appointments',
    'prescriptions',
    'exams',
  ];

  /// Colunas só do aparelho: nunca vão para o servidor nem para a exportação.
  ///  - dirty: alteração local ainda não enviada;
  ///  - base_updated_at: versão do servidor em que a linha local se baseia.
  ///    Na sincronização, separa "a versão que eu já conheço" (sem conflito)
  ///    de "uma alteração nova do outro aparelho" (conflito de verdade).
  static const localColumns = ['dirty', 'base_updated_at'];

  static const _schema = [
    '''CREATE TABLE care_lines (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      color INTEGER NOT NULL,
      default_return_days INTEGER,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      dirty INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE patients (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      birth_date TEXT,
      sex TEXT,
      phone TEXT,
      document TEXT,
      care_line_id TEXT,
      cid_codes TEXT,
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      dirty INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE appointments (
      id TEXT PRIMARY KEY,
      patient_id TEXT NOT NULL,
      start_at TEXT NOT NULL,
      duration_min INTEGER NOT NULL DEFAULT 30,
      status TEXT NOT NULL,
      notes TEXT,
      return_due TEXT,
      return_resolved INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      dirty INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE prescriptions (
      id TEXT PRIMARY KEY,
      patient_id TEXT NOT NULL,
      medication TEXT NOT NULL,
      dosage TEXT,
      issued_at TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      resolved INTEGER NOT NULL DEFAULT 0,
      notes TEXT,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      dirty INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE exams (
      id TEXT PRIMARY KEY,
      patient_id TEXT NOT NULL,
      name TEXT NOT NULL,
      performed_at TEXT NOT NULL,
      result TEXT,
      next_due TEXT,
      resolved INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      dirty INTEGER NOT NULL DEFAULT 1)''',
    '''CREATE TABLE sync_conflicts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      table_name TEXT NOT NULL,
      row_id TEXT NOT NULL,
      payload TEXT NOT NULL,
      created_at TEXT NOT NULL)''',
    'CREATE INDEX idx_appt_patient ON appointments(patient_id)',
    'CREATE INDEX idx_appt_start ON appointments(start_at)',
    'CREATE INDEX idx_rx_patient ON prescriptions(patient_id)',
    'CREATE INDEX idx_exam_patient ON exams(patient_id)',
  ];

  late Database db;

  /// Preenchido quando o arquivo existente não abriu com a chave do cofre
  /// (ex.: a chave foi perdida). O arquivo é guardado com este nome, o app
  /// começa vazio e a tela inicial avisa o usuário.
  String? setAsidePath;

  Future<void> open() async {
    final key = await _loadKey();
    final path = p.join(await getDatabasesPath(), 'consultorio.db');
    final file = File(path);
    try {
      db = await _openWith(path, key);
    } on DatabaseException catch (e) {
      // Só "não abre com esta chave" justifica começar de novo. Qualquer
      // outro erro sobe para a tela de erro, sem mexer no arquivo.
      if (!e.isOpenFailedError() || !await file.exists()) rethrow;
      try {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        db = await _openWith(path, key);
        return;
      } on DatabaseException catch (e2) {
        if (!e2.isOpenFailedError()) rethrow;
      }
      final aside = '$path.unreadable-${DateTime.now().millisecondsSinceEpoch}';
      await file.rename(aside);
      setAsidePath = aside;
      db = await _openWith(path, key);
    }
  }

  /// Colunas acrescentadas depois da primeira versão: (tabela, coluna).
  static final _addedColumns = [
    for (final t in syncedTables) (t, 'base_updated_at'), // v2
    ('patients', 'dum'), // v3: gestação
    ('patients', 'pregnancy_end'), // v3
  ];

  static const _version = 3;

  Future<Database> _openWith(String path, String key) => openDatabase(
        path,
        password: key,
        version: _version,
        onCreate: _createSchema,
        // As colunas novas são conferidas uma a uma em onOpen, então qualquer
        // versão anterior (ou um banco de outra versão do app) fica completa.
        onUpgrade: (db, from, to) async {},
        onDowngrade: (db, from, to) async {},
        onOpen: _ensureColumns,
      );

  /// Banco sem cifra, com o mesmo esquema, para os testes
  /// (sqflite_common_ffi em memória).
  @visibleForTesting
  Future<void> openForTest(DatabaseFactory factory, String path) async {
    db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _version,
        onCreate: _createSchema,
        onOpen: _ensureColumns,
        singleInstance: false,
      ),
    );
  }

  static Future<void> _createSchema(Database db, int version) async {
    for (final stmt in _schema) {
      await db.execute(stmt);
    }
  }

  static Future<void> _ensureColumns(Database db) async {
    for (final (table, column) in _addedColumns) {
      final existing = (await db.rawQuery('PRAGMA table_info($table)')).map((c) => c['name']);
      if (existing.contains(column)) continue;
      await db.execute('ALTER TABLE $table ADD COLUMN $column TEXT');
      if (column == 'base_updated_at') {
        await db.execute('UPDATE $table SET base_updated_at = updated_at WHERE dirty = 0');
      }
    }
  }

  final _columns = <String, Set<String>>{};

  /// Colunas da tabela no aparelho (para ignorar campos desconhecidos que
  /// venham do servidor ou de um backup de outra versão).
  Future<Set<String>> columns(String table) async =>
      _columns[table] ??= (await db.rawQuery('PRAGMA table_info($table)'))
          .map((c) => c['name'] as String)
          .toSet();

  /// Lê a chave do cofre. Se a leitura falhar, o erro sobe: gerar uma chave
  /// nova nesse caso tornaria o banco existente ilegível.
  Future<String> _loadKey() async {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    var key = await storage.read(key: 'db_key');
    if (key == null) {
      final rnd = Random.secure();
      key = base64UrlEncode(List<int>.generate(32, (_) => rnd.nextInt(256)));
      await storage.write(key: 'db_key', value: key);
    }
    return key;
  }

  Future<List<Map<String, Object?>>> active(String table) =>
      db.query(table, where: 'deleted_at IS NULL');

  Future<int> countAll(String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM $table');
    return _count(rows);
  }

  static int _count(List<Map<String, Object?>> rows) {
    final n = rows.isEmpty ? null : rows.first['n'];
    return n is int ? n : int.tryParse('${n ?? 0}') ?? 0;
  }

  Future<Map<String, Object?>?> byId(String table, String id) async {
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Grava a linha preservando base_updated_at. [dirty] = false é usado
  /// para linhas vindas do servidor, que passam a ser a nova base.
  Future<void> write(String table, Map<String, Object?> row, {bool dirty = true}) =>
      _upsert(db, table, row, dirty: dirty);

  Future<void> writeAll(Map<String, List<Map<String, Object?>>> rowsByTable) =>
      db.transaction((txn) async {
        for (final entry in rowsByTable.entries) {
          for (final row in entry.value) {
            await _upsert(txn, entry.key, row, dirty: true);
          }
        }
      });

  static Future<void> _upsert(
    DatabaseExecutor ex,
    String table,
    Map<String, Object?> row, {
    required bool dirty,
  }) async {
    final values = {
      ...row,
      'dirty': dirty ? 1 : 0,
      if (!dirty) 'base_updated_at': row['updated_at'],
    };
    final n = await ex.update(table, values, where: 'id = ?', whereArgs: [row['id']]);
    if (n == 0) await ex.insert(table, values);
  }

  Future<List<Map<String, Object?>>> dirtyRows(String table) =>
      db.query(table, where: 'dirty = 1');

  /// Linha sem as colunas que só existem no aparelho.
  static Map<String, Object?> withoutLocalColumns(Map<String, Object?> row) =>
      Map<String, Object?>.from(row)..removeWhere((k, _) => localColumns.contains(k));

  /// Marca como sincronizada só se a linha não mudou durante o envio.
  Future<void> markClean(String table, String id, String updatedAt) => db.update(
        table,
        {'dirty': 0, 'base_updated_at': updatedAt},
        where: 'id = ? AND updated_at = ?',
        whereArgs: [id, updatedAt],
      );

  /// A alteração local continua pendente, mas já levou em conta esta
  /// versão do servidor (ela foi guardada em sync_conflicts).
  Future<void> setBase(String table, String id, String baseUpdatedAt) => db.update(
        table,
        {'base_updated_at': baseUpdatedAt},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<int> pendingCount() async {
    var total = 0;
    for (final t in syncedTables) {
      total += _count(await db.rawQuery('SELECT COUNT(*) AS n FROM $t WHERE dirty = 1'));
    }
    return total;
  }

  Future<void> addConflict(String table, String rowId, Map<String, Object?> payload) =>
      db.insert('sync_conflicts', {
        'table_name': table,
        'row_id': rowId,
        'payload': jsonEncode(withoutLocalColumns(payload)),
        'created_at': nowUtcIso(),
      });

  Future<int> conflictCount() => countAll('sync_conflicts');

  /// Cópias de conflito guardam dados pessoais: somem quando o registro é
  /// excluído e, de resto, após [maxAge].
  Future<void> purgeConflicts(Iterable<String> rowIds) async {
    final ids = rowIds.toList();
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, min(i + 500, ids.length));
      await db.delete(
        'sync_conflicts',
        where: 'row_id IN (${List.filled(chunk.length, '?').join(',')})',
        whereArgs: chunk,
      );
    }
  }

  Future<void> pruneConflicts(Duration maxAge) => db.delete(
        'sync_conflicts',
        where: 'created_at < ?',
        whereArgs: [DateTime.now().toUtc().subtract(maxAge).toIso8601String()],
      );

  /// Todos os dados ativos, para exportação (portabilidade, LGPD art. 18).
  Future<Map<String, Object?>> exportAll() async {
    final out = <String, Object?>{
      'exported_at': nowUtcIso(),
      'app': 'consultorio',
    };
    for (final t in syncedTables) {
      final rows = await active(t);
      out[t] = rows.map(withoutLocalColumns).toList();
    }
    return out;
  }

  /// Restaura um arquivo gerado por [exportAll]. Cada registro entra se não
  /// existir no aparelho ou se a versão do arquivo for mais nova; nada mais
  /// recente é sobrescrito. Tudo ou nada: um arquivo inválido não altera o
  /// banco. Retorna quantos registros foram restaurados.
  Future<int> importAll(Map<String, Object?> data) async {
    if (data['app'] != 'consultorio') {
      throw const FormatException('Este arquivo não é uma exportação do Consultório.');
    }
    // Lido antes da transação: consultas fora dela esperariam o fim dela.
    final columnsByTable = {
      for (final t in syncedTables)
        t: (await columns(t)).where((c) => !localColumns.contains(c)).toSet(),
    };
    var restored = 0;
    await db.transaction((txn) async {
      for (final t in syncedTables) {
        final rows = data[t];
        if (rows == null) continue;
        if (rows is! List) throw FormatException('Seção "$t" inválida.');
        final columns = columnsByTable[t]!;
        for (final raw in rows) {
          if (raw is! Map) throw FormatException('Registro inválido em "$t".');
          final row = <String, Object?>{
            for (final e in raw.entries)
              if (columns.contains(e.key)) e.key as String: e.value,
          };
          final id = row['id'];
          final updatedAt = row['updated_at'];
          if (id is! String || updatedAt is! String || DateTime.tryParse(updatedAt) == null) {
            throw FormatException('Registro sem identificação em "$t".');
          }
          final local = await txn.query(t,
              columns: ['updated_at'], where: 'id = ?', whereArgs: [id], limit: 1);
          if (local.isNotEmpty) {
            final localTs = DateTime.tryParse('${local.first['updated_at']}');
            if (localTs != null && !DateTime.parse(updatedAt).isAfter(localTs)) continue;
          }
          await _upsert(txn, t, row, dirty: true);
          restored++;
        }
      }
    });
    return restored;
  }
}
