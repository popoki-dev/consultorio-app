import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async =>
      AppSettings._(await SharedPreferences.getInstance());

  bool get lockEnabled => _prefs.getBool('lock_enabled') ?? true;
  Future<void> setLockEnabled(bool v) async {
    await _prefs.setBool('lock_enabled', v);
    notifyListeners();
  }

  /// Esconde o conteúdo do app em capturas de tela e na lista de apps
  /// recentes (Android).
  bool get screenProtection => _prefs.getBool('screen_protection') ?? true;
  Future<void> setScreenProtection(bool v) async {
    await _prefs.setBool('screen_protection', v);
    notifyListeners();
  }

  /// Notificações aparecem na tela bloqueada: por padrão mostram só as
  /// iniciais do paciente.
  bool get notificationNames => _prefs.getBool('notification_names') ?? false;
  Future<void> setNotificationNames(bool v) async {
    await _prefs.setBool('notification_names', v);
    notifyListeners();
  }

  DateTime? get lastBackup {
    final s = _prefs.getString('last_backup');
    return s == null ? null : DateTime.tryParse(s)?.toLocal();
  }

  Future<void> setLastBackup(DateTime d) async {
    await _prefs.setString('last_backup', d.toUtc().toIso8601String());
    notifyListeners();
  }

  /// Quantos dias antes do vencimento o aviso é enviado.
  int leadDays(ReminderKind k) => _prefs.getInt('lead_${k.name}') ?? k.defaultLeadDays;
  Future<void> setLeadDays(ReminderKind k, int days) async {
    await _prefs.setInt('lead_${k.name}', days.clamp(0, 60));
    notifyListeners();
  }

  bool get notificationsAsked => _prefs.getBool('notifications_asked') ?? false;
  Future<void> setNotificationsAsked() => _prefs.setBool('notifications_asked', true);

  String? syncCursor(String table) => _prefs.getString('cursor_$table');
  Future<void> setSyncCursor(String table, String value) =>
      _prefs.setString('cursor_$table', value);
  Future<void> clearSyncCursors() async {
    for (final k in _prefs.getKeys().where((k) => k.startsWith('cursor_')).toList()) {
      await _prefs.remove(k);
    }
  }

  DateTime? get lastSync {
    final s = _prefs.getString('last_sync');
    return s == null ? null : DateTime.tryParse(s)?.toLocal();
  }

  Future<void> setLastSync(DateTime d) =>
      _prefs.setString('last_sync', d.toUtc().toIso8601String());
}
