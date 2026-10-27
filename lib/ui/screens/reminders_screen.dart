import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_data.dart';
import '../../data/models.dart';
import '../widgets.dart';
import 'appointment_actions.dart';
import 'patient_detail.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  ReminderKind? _kind;
  bool _showLater = false;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final all = data.reminders;
    final list = _kind == null ? all : all.where((r) => r.kind == _kind).toList();

    final overdue = list.where((r) => r.daysLeft < 0).toList();
    final week = list.where((r) => r.daysLeft >= 0 && r.daysLeft <= 7).toList();
    final month = list.where((r) => r.daysLeft > 7 && r.daysLeft <= 30).toList();
    final later = list.where((r) => r.daysLeft > 30).toList();

    return AccentPage(
      accent: Accent.reminders,
      title: 'Lembretes',
      headerBottom: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: _HeaderCount(
                value: all.where((r) => r.daysLeft < 0).length,
                label: 'Atrasados',
                highlight: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HeaderCount(
                value: all.where((r) => r.daysLeft >= 0 && r.daysLeft <= 7).length,
                label: 'Próx. 7 dias',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HeaderCount(
                value: all.where((r) => r.daysLeft > 7 && r.daysLeft <= 30).length,
                label: 'Próx. 30 dias',
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
        children: [
          SegmentedPills<ReminderKind?>(
            options: const [
              (null, 'Todos'),
              (ReminderKind.returnVisit, 'Retornos'),
              (ReminderKind.prescription, 'Receitas'),
              (ReminderKind.exam, 'Exames'),
            ],
            selected: _kind,
            selectedColor: AppColors.purpleSoft,
            onChanged: (k) => setState(() => _kind = k),
          ),
          if (list.isEmpty)
            const EmptyState(
              icon: Icons.notifications_off_outlined,
              text: 'Nenhum lembrete pendente. Tudo em dia!',
            ),
          if (overdue.isNotEmpty) ...[
            SectionTitle('Atrasados', trailing: _count(overdue.length)),
            ...overdue.map((r) => _ReminderCard(reminder: r)),
          ],
          if (week.isNotEmpty) ...[
            SectionTitle('Hoje e próximos 7 dias', trailing: _count(week.length)),
            ...week.map((r) => _ReminderCard(reminder: r)),
          ],
          if (month.isNotEmpty) ...[
            SectionTitle('Próximos 30 dias', trailing: _count(month.length)),
            ...month.map((r) => _ReminderCard(reminder: r)),
          ],
          if (later.isNotEmpty) ...[
            SectionTitle(
              'Mais adiante',
              trailing: TextButton(
                onPressed: () => setState(() => _showLater = !_showLater),
                child: Text(_showLater ? 'Ocultar' : 'Ver ${later.length}'),
              ),
            ),
            if (_showLater) ...later.map((r) => _ReminderCard(reminder: r)),
          ],
        ],
      ),
    );
  }

  Widget _count(int n) => StatusBadge(text: '$n', color: AppColors.surface);
}

class _HeaderCount extends StatelessWidget {
  const _HeaderCount({required this.value, required this.label, this.highlight = false});
  final int value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final alert = highlight && value > 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: alert ? AppColors.dangerSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ink, width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: alert ? AppColors.danger : AppColors.ink,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.reminder});
  final Reminder reminder;

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final data = context.read<AppData>();
    final tabIndex = switch (r.kind) {
      ReminderKind.prescription => 1,
      ReminderKind.exam => 2,
      ReminderKind.returnVisit => 0,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OutlinedCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PatientDetailScreen(patientId: r.patient.id, initialTab: tabIndex),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: r.kind.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.ink, width: 1.3),
                  ),
                  child: Icon(r.kind.icon, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.patient.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(r.title, style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          StatusBadge(
                            text: r.label,
                            color: AppColors.surface,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${fmtDate(r.due)} · ${r.overdue ? 'venceu ' : ''}${relativeDays(r.due)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: r.overdue ? AppColors.danger : AppColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: const Text('Resolvido'),
                  onPressed: () async {
                    await data.setReminderResolved(r, true);
                    if (!context.mounted) return;
                    showSnack(
                      context,
                      'Lembrete resolvido.',
                      action: SnackBarAction(
                        label: 'Desfazer',
                        onPressed: () => data.setReminderResolved(r, false),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(40, 40)),
                  icon: const Icon(Icons.event_available_outlined, size: 18),
                  label: const Text('Agendar'),
                  onPressed: () => openAppointmentForm(
                    context,
                    patientId: r.patient.id,
                    date: r.overdue ? today() : r.due,
                    fromReminder: r,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
