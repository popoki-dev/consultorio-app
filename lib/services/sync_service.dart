import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_data.dart';
import '../data/local_db.dart';
import 'settings.dart';

/// Configuração em tempo de compilação:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// Sem ela, o app funciona 100% local (um aparelho).
class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}

/// Sincronização offline-first:
///  1. toda gravação local marca a linha como "dirty";
///  2. ao sincronizar, primeiro baixa o que mudou no servidor desde o último
///     cursor (server_updated_at, gerado pelo banco), depois envia as linhas
///     locais pendentes;
///  3. se a mesma linha mudou nos dois lados, vence a alteração mais recente
///     (updated_at) e a versão perdedora é guardada em sync_conflicts —
///     nada é perdido. O servidor também recusa gravar uma versão mais
///     antiga que a dele (gatilho keep_newest em schema.sql).
class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  SyncService(this.db, this.data, this.settings);

  final LocalDb db;
  final AppData data;
  final AppSettings settings;

  bool syncing = false;
  String? lastError;
  int conflicts = 0;

  Timer? _debounce;
  Timer? _periodic;

  bool get enabled => SupabaseConfig.isConfigured;
  SupabaseClient? get _client => enabled ? Supabase.instance.client : null;
  bool get signedIn => _client?.auth.currentUser != null;
  String? get userEmail => _client?.auth.currentUser?.email;
  DateTime? get lastSync => settings.lastSync;

  Future<void> start() async {
    await db.pruneConflicts(const Duration(days: 90));
    conflicts = await db.conflictCount();
    if (!enabled) return;
    WidgetsBinding.instance.addObserver(this);
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => syncNow());
    unawaited(syncNow());
  }

  void scheduleSync() {
    if (!enabled || !signedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), syncNow);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(syncNow());
  }

  Future<String?> signIn(String email, String password) async {
    final client = _client;
    if (client == null) return 'Sincronização não configurada.';
    try {
      await client.auth.signInWithPassword(email: email.trim(), password: password);
      notifyListeners();
      await syncNow();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return _friendly(e);
    }
  }

  Future<void> signOut() async {
    await _client?.auth.signOut();
    await settings.clearSyncCursors();
    notifyListeners();
  }

  Future<void> syncNow() async {
    if (!enabled || !signedIn || syncing) return;
    syncing = true;
    lastError = null;
    notifyListeners();
    try {
      var changed = false;
      for (final t in LocalDb.syncedTables) {
        changed = await _pull(t) || changed;
      }
      for (final t in LocalDb.syncedTables) {
        changed = await _push(t) || changed;
      }
      await settings.setLastSync(DateTime.now());
      conflicts = await db.conflictCount();
      if (changed) await data.load();
    } catch (e) {
      lastError = _friendly(e);
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// server_updated_at é gerado quando a linha é gravada, mas ela só fica
  /// visível quando a transação termina. Uma gravação do outro aparelho pode
  /// aparecer "no passado", atrás do cursor. Por isso cada busca recomeça
  /// um pouco antes do cursor; linhas já conhecidas são ignoradas.
  static const _overlap = Duration(minutes: 5);

  Future<bool> _pull(String table) async {
    const page = 500;
    final saved = settings.syncCursor(table);
    var cursor = saved == null
        ? '1970-01-01T00:00:00.000Z'
        : DateTime.parse(saved).subtract(_overlap).toUtc().toIso8601String();
    var changed = false;
    while (true) {
      final rows = await _client!
          .from(table)
          .select()
          .gt('server_updated_at', cursor)
          .order('server_updated_at', ascending: true)
          .limit(page);
      if (rows.isEmpty) break;

      for (final remote in rows) {
        final serverTs = remote['server_updated_at'].toString();
        changed = await _merge(table, await _localRow(table, remote)) || changed;
        // Normaliza para UTC com "Z" (evita "+" na URL do filtro).
        cursor = DateTime.parse(serverTs).toUtc().toIso8601String();
      }
      if (saved == null || DateTime.parse(cursor).isAfter(DateTime.parse(saved))) {
        await settings.setSyncCursor(table, cursor);
      }
      if (rows.length < page) break;
    }
    return changed;
  }

  /// Linha do servidor só com as colunas que existem no aparelho (um
  /// aparelho com versão mais nova do app pode ter colunas a mais).
  Future<Map<String, Object?>> _localRow(String table, Map<String, dynamic> remote) async {
    final cols = await db.columns(table);
    return {
      for (final e in remote.entries)
        if (cols.contains(e.key) && !LocalDb.localColumns.contains(e.key)) e.key: e.value,
    };
  }

  /// Aplica uma linha do servidor. Retorna true se o banco local mudou.
  Future<bool> _merge(String table, Map<String, Object?> row) async {
    final id = row['id'] as String;
    final remoteVersion = row['updated_at'] as String;
    final local = await db.byId(table, id);
    if (local == null) {
      await db.write(table, row, dirty: false);
      return true;
    }
    // Versão que este aparelho já conhece (ele mesmo enviou ou já baixou).
    if (local['base_updated_at'] == remoteVersion) return false;

    final localDirty = local['dirty'] == 1;
    if (!localDirty) {
      if (local['updated_at'] == remoteVersion) {
        await db.markClean(table, id, remoteVersion);
        return false;
      }
      await db.write(table, row, dirty: false);
      return true;
    }

    // Os dois aparelhos alteraram a mesma linha: vence a mais recente e a
    // outra versão fica guardada em sync_conflicts.
    final localTs = DateTime.parse(local['updated_at'] as String);
    final remoteTs = DateTime.parse(remoteVersion);
    if (remoteTs.isAfter(localTs)) {
      // Linha padrão criada pelo app neste aparelho: não é edição de ninguém.
      if (local['updated_at'] != AppData.seedVersion) await db.addConflict(table, id, local);
      await db.write(table, row, dirty: false);
      return true;
    }
    if (remoteTs.isBefore(localTs)) {
      await db.addConflict(table, id, row);
      await db.setBase(table, id, remoteVersion);
    } else {
      await db.markClean(table, id, remoteVersion);
    }
    return false;
  }

  /// Envia as linhas pendentes. O servidor recusa (não devolve) as que
  /// são mais antigas que a versão dele; nesse caso a versão do servidor é
  /// baixada e a local vai para sync_conflicts. Retorna true se o banco
  /// local mudou.
  Future<bool> _push(String table) async {
    final dirty = await db.dirtyRows(table);
    var changed = false;
    for (var i = 0; i < dirty.length; i += 200) {
      final chunk = dirty.sublist(i, min(i + 200, dirty.length));
      final payload = chunk.map(LocalDb.withoutLocalColumns).toList();
      final saved = await _client!
          .from(table)
          .upsert(payload, onConflict: 'id')
          .select('id');
      final accepted = saved.map((r) => r['id']).toSet();
      final rejected = <String, Map<String, Object?>>{};
      for (final r in chunk) {
        final id = r['id'] as String;
        if (accepted.contains(id)) {
          await db.markClean(table, id, r['updated_at'] as String);
        } else {
          rejected[id] = r;
        }
      }
      if (rejected.isEmpty) continue;

      final newer = await _client!.from(table).select().inFilter('id', rejected.keys.toList());
      for (final remote in newer) {
        final row = await _localRow(table, remote);
        final id = row['id'] as String;
        // Editada de novo durante o envio: fica para a próxima rodada.
        final local = await db.byId(table, id);
        if (local == null || local['updated_at'] != rejected[id]!['updated_at']) continue;
        await db.addConflict(table, id, local);
        await db.write(table, row, dirty: false);
        changed = true;
      }
    }
    return changed;
  }

  /// Alterações feitas neste aparelho que ainda não foram enviadas.
  Future<int> pendingChanges() => db.pendingCount();

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('ClientException') ||
        s.contains('TimeoutException')) {
      return 'Sem conexão. Os dados continuam salvos no aparelho e serão enviados depois.';
    }
    if (s.contains('schema cache') || (s.contains('column') && s.contains('does not exist'))) {
      return 'O servidor precisa ser atualizado para esta versão do app: '
          'rode o arquivo supabase/schema.sql no SQL Editor do Supabase.';
    }
    return 'Falha na sincronização: $s';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _periodic?.cancel();
    if (enabled) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
