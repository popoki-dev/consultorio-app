import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_data.dart';
import '../../data/models.dart';
import '../widgets.dart';
import 'appointment_actions.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  DateTime _day = today();

  void _go(DateTime d) => setState(() => _day = dateOnly(d));

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final items = data.appointmentsOn(_day);
    final active = items.where((a) => a.status != ApptStatus.cancelled).toList();
    final done = active.where((a) => a.status == ApptStatus.done).length;
    final missed = active.where((a) => a.status == ApptStatus.missed).length;
    final pending = active.where((a) => a.status == ApptStatus.scheduled).length;

    final weekStart = startOfWeek(_day);
    final weekEnd = addDays(weekStart, 7);
    final marked = {
      for (final a in data.appointments)
        if (a.status != ApptStatus.cancelled &&
            !a.startAt.isBefore(weekStart) &&
            a.startAt.isBefore(weekEnd))
          dateKey(a.startAt),
    };

    return AccentPage(
      accent: Accent.agenda,
      title: 'Agenda',
      leading: sameDay(_day, today())
          ? null
          : CircleIconButton(icon: Icons.today_rounded, tooltip: 'Hoje', onPressed: () => _go(today())),
      actions: [
        CircleIconButton(
          icon: Icons.calendar_month_outlined,
          tooltip: 'Escolher data',
          color: AppColors.surface,
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _day,
              firstDate: DateTime(2020),
              lastDate: DateTime(today().year + 3),
            );
            if (d != null) _go(d);
          },
        ),
      ],
      headerBottom: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Semana anterior',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => _go(addDays(_day, -7)),
              ),
              Expanded(
                child: Text(
                  monthYear(_day),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Próxima semana',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () => _go(addDays(_day, 7)),
              ),
            ],
          ),
          WeekStrip(selected: _day, onSelected: _go, marked: marked),
        ],
      ),
      fab: FloatingActionButton.extended(
        heroTag: 'fab-agenda',
        onPressed: () => openAppointmentForm(context, date: _day),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Consulta', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: GestureDetector(
        // Deslizar para os lados troca o dia.
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -300) _go(addDays(_day, 1));
          if (v > 300) _go(addDays(_day, -1));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
          children: [
            Text(fmtDayLong(_day), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    value: '${active.length}',
                    label: 'Consultas',
                    icon: Icons.event_note_outlined,
                    iconColor: AppColors.greenSoft,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    value: '$done',
                    label: 'Realizadas',
                    icon: Icons.check_rounded,
                    iconColor: AppColors.okSoft,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatTile(
                    value: '$pending',
                    label: missed > 0 ? 'A atender · $missed faltas' : 'A atender',
                    icon: Icons.hourglass_bottom_rounded,
                    iconColor: AppColors.yellowSoft,
                  ),
                ),
              ],
            ),
            if (active.isNotEmpty) ...[
              const SizedBox(height: 12),
              ProgressPill(
                value: (done + missed) / active.length,
                color: AppColors.green,
              ),
            ],
            const SizedBox(height: 8),
            if (items.isEmpty)
              EmptyState(
                icon: Icons.event_available_outlined,
                text: 'Nenhuma consulta neste dia.',
                action: OutlinedButton.icon(
                  onPressed: () => openAppointmentForm(context, date: _day),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Agendar consulta'),
                ),
              )
            else
              for (final a in items)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _AppointmentTile(appointment: a),
                ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final data = context.read<AppData>();
    final a = appointment;
    final p = data.patient(a.patientId);
    final lines = data.careLinesOf(p);
    final cancelled = a.status == ApptStatus.cancelled;

    return Opacity(
      opacity: cancelled ? 0.55 : 1,
      child: OutlinedCard(
        padding: const EdgeInsets.all(10),
        onTap: () => showAppointmentActions(context, a),
        child: Row(
          children: [
            Container(
              width: 66,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: a.status == ApptStatus.done ? AppColors.green : AppColors.greenSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.ink, width: 1.3),
              ),
              child: Column(
                children: [
                  Text(fmtTime(a.startAt), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text('${a.durationMin} min', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p?.name ?? 'Paciente removido',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      decoration: cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      for (final line in lines) ...[
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: line.colorValue,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.ink, width: 0.8),
                          ),
                        ),
                        const SizedBox(width: 3),
                      ],
                      if (lines.isNotEmpty) const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          [...lines.map((l) => l.name), if (p != null) ageLabel(p.birthDate)].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                  if ((a.notes ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        a.notes!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            StatusBadge(text: ApptStatus.label(a.status), color: ApptStatus.color(a.status)),
          ],
        ),
      ),
    );
  }
}
