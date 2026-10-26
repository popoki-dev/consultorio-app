import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/app_data.dart';
import '../services/notification_service.dart';
import '../services/settings.dart';
import '../services/sync_service.dart';
import 'screens/agenda_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/patients_screen.dart';
import 'screens/reminders_screen.dart';
import 'screens/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _remindersTab = 2;

  int _index = 0;
  late final NotificationService _notifications;

  static const _pages = [
    AgendaScreen(),
    PatientsScreen(),
    RemindersScreen(),
    DashboardScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _notifications = context.read<NotificationService>();
    if (_notifications.taps.value > 0) _index = _remindersTab;
    _notifications.taps.addListener(_openReminders);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _warnIfDataSetAside();
      if (!mounted) return;
      final settings = context.read<AppSettings>();
      if (!settings.notificationsAsked) {
        await _notifications.requestPermission();
        await settings.setNotificationsAsked();
      }
    });
  }

  @override
  void dispose() {
    _notifications.taps.removeListener(_openReminders);
    super.dispose();
  }

  void _openReminders() {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => _index = _remindersTab);
  }

  /// O banco anterior não abriu com a chave do cofre e foi guardado à
  /// parte (ver LocalDb.open). O usuário precisa saber e recuperar.
  Future<void> _warnIfDataSetAside() async {
    final db = context.read<AppData>().db;
    if (db.setAsidePath == null) return;
    db.setAsidePath = null;
    final sync = context.read<SyncService>();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Dados anteriores indisponíveis'),
        content: Text(
          'Os dados salvos neste aparelho não puderam ser abertos, porque a chave '
          'de proteção do sistema foi perdida (isso pode acontecer após restaurar '
          'ou atualizar o aparelho). O app começou vazio; nada foi apagado.\n\n'
          '${sync.enabled ? 'Entre em Ajustes → Sincronização para trazer os dados do servidor.' : 'Use Ajustes → Restaurar backup com o último arquivo exportado.'}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
    if (mounted) setState(() => _index = _pages.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final overdue = data.reminders.where((r) => r.daysLeft <= 0).length;

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: AppColors.yellow,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.ink, width: 1.5),
            ),
            child: Row(
              children: [
                _NavItem(icon: Icons.calendar_month_outlined, label: 'Agenda', index: 0, current: _index, onTap: _go),
                _NavItem(icon: Icons.people_alt_outlined, label: 'Pacientes', index: 1, current: _index, onTap: _go),
                _NavItem(
                  icon: Icons.notifications_none_rounded,
                  label: 'Lembretes',
                  index: 2,
                  current: _index,
                  onTap: _go,
                  badge: overdue,
                ),
                _NavItem(icon: Icons.insights_outlined, label: 'Painel', index: 3, current: _index, onTap: _go),
                _NavItem(icon: Icons.settings_outlined, label: 'Ajustes', index: 4, current: _index, onTap: _go),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _go(int i) => setState(() => _index = i);
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.current,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final int index;
  final int current;
  final ValueChanged<int> onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final selected = index == current;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: badge > 0 ? '$label, $badge pendentes' : label,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onTap(index),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 46,
                    height: 32,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.cream : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? AppColors.ink : Colors.transparent,
                        width: 1.4,
                      ),
                    ),
                    child: Icon(icon, size: 22, color: AppColors.ink),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -2,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 18),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.ink, width: 1),
                        ),
                        child: Text(
                          badge > 99 ? '99+' : '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
