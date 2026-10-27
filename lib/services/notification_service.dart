import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/format.dart';
import '../data/models.dart';

/// Agenda notificações locais para cada lembrete: uma com antecedência
/// configurável e outra no dia do vencimento, sempre às 8h. Ficam
/// registradas no sistema, então disparam mesmo sem internet e com o app
/// fechado.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Aumenta quando o usuário toca numa notificação (inclusive a que abriu
  /// o app); a tela inicial passa para a aba Lembretes.
  final taps = ValueNotifier<int>(0);

  /// iOS permite no máximo 64 notificações pendentes por app.
  static const _maxPending = 60;
  static const _hour = 8;

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
      }
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (_) => taps.value++,
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) taps.value++;
      _ready = true;
    } catch (e) {
      debugPrint('Notificações indisponíveis: $e');
    }
  }

  Future<void> requestPermission() async {
    if (!_ready) return;
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Sem [showNames], a notificação traz só as iniciais do paciente: ela
  /// aparece na tela bloqueada, à vista de qualquer pessoa.
  Future<void> reschedule(
    List<Reminder> reminders,
    int Function(ReminderKind) leadDays, {
    bool showNames = false,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      final now = tz.TZDateTime.now(tz.local);
      final items = <(tz.TZDateTime, Reminder, bool)>[];
      for (final r in reminders) {
        final lead = leadDays(r.kind);
        final before = _at(r.due, -lead);
        final onDay = _at(r.due, 0);
        if (lead > 0 && before.isAfter(now)) items.add((before, r, false));
        if (onDay.isAfter(now)) items.add((onDay, r, true));
      }
      items.sort((a, b) => a.$1.compareTo(b.$1));

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'lembretes',
          'Lembretes do consultório',
          channelDescription: 'Retornos, receitas e exames a vencer',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
        ),
        iOS: DarwinNotificationDetails(),
      );

      var id = 1;
      for (final (at, r, isDueDay) in items.take(_maxPending)) {
        final who = showNames ? r.patient.name : 'paciente ${initials(r.patient.name)}';
        final vence = r.sources.length == 1 ? 'vence' : 'vencem';
        final title = isDueDay
            ? '${r.label} $vence hoje · $who'
            : '${r.label} $vence em ${daysBetween(at, r.due)} dias · $who';
        final what = showNames ? '${r.title} — ' : '';
        final body = '$what${fmtDate(r.due)}. Toque para ver os lembretes.';
        await _plugin.zonedSchedule(
          id++,
          title,
          body,
          at,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (e) {
      debugPrint('Falha ao agendar notificações: $e');
    }
  }

  tz.TZDateTime _at(DateTime day, int offsetDays) {
    final d = DateTime(day.year, day.month, day.day + offsetDays);
    return tz.TZDateTime(tz.local, d.year, d.month, d.day, _hour);
  }
}
