import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/cid10.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_data.dart';
import '../../data/care_rules.dart';
import '../../data/models.dart';
import '../widgets.dart';
import 'appointment_actions.dart';
import 'exam_form.dart';
import 'patient_form.dart';
import 'prescription_form.dart';

enum _Tab { summary, prescriptions, exams, visits }

class PatientDetailScreen extends StatefulWidget {
  const PatientDetailScreen({super.key, required this.patientId, this.initialTab});

  final String patientId;

  /// 0 resumo, 1 receitas, 2 exames, 3 consultas.
  final int? initialTab;

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  late _Tab _tab = _Tab.values[(widget.initialTab ?? 0).clamp(0, 3)];

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final p = data.patient(widget.patientId);
    if (p == null) {
      return Scaffold(
        appBar: AppBar(leadingWidth: 64, leading: const BackCircle()),
        body: const EmptyState(icon: Icons.person_off_outlined, text: 'Paciente não encontrado.'),
      );
    }
    final lines = data.careLinesOf(p);
    final List<Widget> content = switch (_tab) {
      _Tab.summary => _summary(context, data, p),
      _Tab.prescriptions => _prescriptions(context, data, p),
      _Tab.exams => _exams(context, data, p),
      _Tab.visits => _visits(context, data, p),
    };

    return AccentPage(
      accent: Accent.patients,
      title: 'Paciente',
      leading: const BackCircle(),
      actions: [
        CircleIconButton(
          icon: Icons.edit_outlined,
          tooltip: 'Editar cadastro',
          color: AppColors.surface,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PatientFormScreen(existing: p)),
          ),
        ),
      ],
      headerBottom: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Avatar(name: p.name, color: lines.firstOrNull?.colorValue ?? AppColors.salmonSoft, size: 58),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.15)),
                  const SizedBox(height: 4),
                  Text(
                    '${ageLabel(p.birthDate)} · ${Sex.label(p.sex)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (lines.isNotEmpty || p.pregnant) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final line in lines) StatusBadge(text: line.name, color: AppColors.surface),
                        if (p.pregnant)
                          StatusBadge(
                            text: 'Gestante · ${gestationalAge(p.dum!, today()).short}',
                            color: AppColors.yellowSoft,
                            icon: Icons.pregnant_woman_rounded,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      fab: _fab(context, p),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
        children: [
          SegmentedPills<_Tab>(
            options: const [
              (_Tab.summary, 'Resumo'),
              (_Tab.prescriptions, 'Receitas'),
              (_Tab.exams, 'Exames'),
              (_Tab.visits, 'Consultas'),
            ],
            selected: _tab,
            selectedColor: AppColors.salmonSoft,
            onChanged: (t) => setState(() => _tab = t),
          ),
          const SizedBox(height: 14),
          ...content,
        ],
      ),
    );
  }

  Widget _fab(BuildContext context, Patient p) {
    return switch (_tab) {
      _Tab.prescriptions => FloatingActionButton.extended(
          heroTag: 'fab-rx',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PrescriptionFormScreen(patientId: p.id)),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Receituário', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      _Tab.exams => FloatingActionButton.extended(
          heroTag: 'fab-exam',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ExamFormScreen(patientId: p.id)),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Exame', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      _ => FloatingActionButton.extended(
          heroTag: 'fab-appt',
          onPressed: () => openAppointmentForm(context, patientId: p.id),
          icon: const Icon(Icons.event_available_outlined),
          label: const Text('Agendar', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
    };
  }

  // ----------------------------------------------------------------- resumo

  List<Widget> _summary(BuildContext context, AppData data, Patient p) {
    final last = data.lastVisit(p.id);
    final next = data.nextAppointment(p.id);
    final reminders = data.remindersOf(p.id);
    final returnReminder = reminders.where((r) => r.kind == ReminderKind.returnVisit).firstOrNull;
    final activeRx = data.prescriptionsOf(p.id).where((r) => !r.resolved && !r.isExpired).length;
    final birth = p.birthDate;

    return [
      if (p.pregnant) ...[
        _PregnancyCard(patient: p),
        const SizedBox(height: 10),
      ],
      if (birth != null && isInfant(p, today())) ...[
        _InfantCard(
          birth: birth,
          doneVisits: [
            for (final a in data.appointmentsOf(p.id))
              if (a.status == ApptStatus.done) a.startAt,
          ],
        ),
        const SizedBox(height: 10),
      ],
      Row(
        children: [
          Expanded(
            child: StatTile(
              value: last == null ? '—' : fmtDateShort(last.startAt),
              label: last == null ? 'Última consulta' : 'Última consulta\n${relativeDays(last.startAt)}',
              icon: Icons.history_rounded,
              iconColor: AppColors.salmonSoft,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatTile(
              value: returnReminder == null ? '—' : fmtDateShort(returnReminder.due),
              label: returnReminder == null ? 'Retorno previsto' : 'Retorno previsto\n${relativeDays(returnReminder.due)}',
              icon: Icons.event_repeat_rounded,
              iconColor: AppColors.greenSoft,
              valueColor: returnReminder?.overdue == true ? AppColors.danger : AppColors.ink,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StatTile(
              value: '$activeRx',
              label: 'Medicamentos válidos',
              icon: Icons.medication_outlined,
              iconColor: AppColors.purpleSoft,
              onTap: () => setState(() => _tab = _Tab.prescriptions),
            ),
          ),
        ],
      ),
      if (next != null) ...[
        const SizedBox(height: 10),
        OutlinedCard(
          color: AppColors.greenSoft,
          onTap: () => showAppointmentActions(context, next),
          child: Row(
            children: [
              const Icon(Icons.event_available_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Próxima consulta: ${fmtDayLong(next.startAt)} às ${fmtTime(next.startAt)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ],
      if (reminders.isNotEmpty) ...[
        const SectionTitle('Pendências'),
        for (final r in reminders)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedCard(
              padding: const EdgeInsets.all(12),
              color: r.overdue ? AppColors.dangerSoft : AppColors.surface,
              child: Row(
                children: [
                  Icon(r.kind.icon),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          '${r.overdue ? 'Venceu' : 'Vence'} ${relativeDays(r.due)} · ${fmtDate(r.due)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: r.overdue ? AppColors.danger : AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      const SectionTitle('Dados do paciente'),
      OutlinedCard(
        child: Column(
          children: [
            InfoRow(icon: Icons.cake_outlined, label: 'Nascimento', value: fmtDate(p.birthDate)),
            _PhoneRow(phone: p.phone),
            InfoRow(icon: Icons.badge_outlined, label: 'CPF / SUS', value: p.document ?? '—'),
            InfoRow(
              icon: Icons.medical_information_outlined,
              label: 'CID-10',
              value: p.cidCodes.isEmpty ? '—' : p.cidCodes.map(cidLabel).join('\n'),
            ),
            if (p.dum != null && p.pregnancyEnd != null)
              InfoRow(
                icon: Icons.pregnant_woman_rounded,
                label: 'Última gestação',
                value: 'Encerrada em ${fmtDate(p.pregnancyEnd)} (DPP era ${fmtDate(dueDate(p.dum!))})',
              ),
            InfoRow(icon: Icons.notes_rounded, label: 'Observações', value: p.notes ?? '—'),
          ],
        ),
      ),
      const SizedBox(height: 18),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
        icon: const Icon(Icons.delete_outline_rounded),
        label: const Text('Excluir paciente'),
        onPressed: () async {
          final ok = await confirmDialog(
            context,
            title: 'Excluir ${p.name}?',
            message: 'O cadastro, consultas, receitas e exames deste paciente serão removidos de todos os aparelhos.',
            confirm: 'Excluir',
            danger: true,
          );
          if (!ok || !context.mounted) return;
          final nav = Navigator.of(context);
          await context.read<AppData>().delete(p);
          nav.pop();
        },
      ),
    ];
  }

  // --------------------------------------------------------------- receitas

  List<Widget> _prescriptions(BuildContext context, AppData data, Patient p) {
    final groups = data.receituariosOf(p.id);
    if (groups.isEmpty) {
      return const [EmptyState(icon: Icons.medication_outlined, text: 'Nenhuma receita registrada.')];
    }
    return [
      for (final group in groups)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PrescriptionFormScreen(patientId: p.id, existing: group)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.salmonSoft,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.ink, width: 1.3),
                      ),
                      child: const Icon(Icons.medication_outlined, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Receituário de ${fmtDate(group.first.issuedAt)}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                          Text(
                            plural(group.length, 'medicamento', 'medicamentos'),
                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                for (final r in group) ...[
                  const Divider(height: 18, color: AppColors.hairline),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.medication, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                            if (r.dosage != null) Text(r.dosage!, style: const TextStyle(fontSize: 13)),
                            Text(
                              'Válida até ${fmtDate(r.expiresAt)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      prescriptionBadge(r),
                    ],
                  ),
                ],
                if ((group.first.notes ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(group.first.notes!, style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
    ];
  }

  // ----------------------------------------------------------------- exames

  List<Widget> _exams(BuildContext context, AppData data, Patient p) {
    final list = data.examsOf(p.id);
    if (list.isEmpty) {
      return const [EmptyState(icon: Icons.biotech_outlined, text: 'Nenhum exame registrado.')];
    }
    return [
      for (final e in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ExamFormScreen(patientId: p.id, existing: e)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                    Text(fmtDate(e.performedAt), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                if (e.result.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(e.result, maxLines: 4, overflow: TextOverflow.ellipsis),
                ],
                if (e.nextDue != null) ...[
                  const SizedBox(height: 8),
                  StatusBadge(
                    text: e.resolved
                        ? 'Repetição resolvida'
                        : 'Repetir em ${fmtDate(e.nextDue)} (${relativeDays(e.nextDue!)})',
                    color: e.resolved
                        ? AppColors.hairline
                        : (e.nextDue!.isBefore(today()) ? AppColors.dangerSoft : AppColors.purpleSoft),
                    icon: Icons.event_repeat_rounded,
                  ),
                ],
              ],
            ),
          ),
        ),
    ];
  }

  // --------------------------------------------------------------- consultas

  List<Widget> _visits(BuildContext context, AppData data, Patient p) {
    final list = data.appointmentsOf(p.id);
    if (list.isEmpty) {
      return const [EmptyState(icon: Icons.event_note_outlined, text: 'Nenhuma consulta registrada.')];
    }
    return [
      for (final a in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedCard(
            padding: const EdgeInsets.all(12),
            onTap: () => showAppointmentActions(context, a),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${fmtDate(a.startAt)} · ${fmtTime(a.startAt)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (a.returnDue != null)
                        Text(
                          'Retorno previsto: ${fmtDate(a.returnDue)}',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      if ((a.notes ?? '').isNotEmpty)
                        Text(a.notes!, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                StatusBadge(text: ApptStatus.label(a.status), color: ApptStatus.color(a.status)),
              ],
            ),
          ),
        ),
    ];
  }
}

Widget prescriptionBadge(Prescription r) {
  if (r.resolved) return const StatusBadge(text: 'Renovada', color: AppColors.hairline);
  final days = daysBetween(today(), r.expiresAt);
  if (days < 0) {
    return const StatusBadge(text: 'Vencida', color: AppColors.dangerSoft, icon: Icons.error_outline_rounded);
  }
  if (days <= 7) {
    return StatusBadge(
      text: days == 0 ? 'Vence hoje' : 'Vence em $days d',
      color: AppColors.warnSoft,
      icon: Icons.schedule_rounded,
    );
  }
  return const StatusBadge(text: 'Válida', color: AppColors.okSoft, icon: Icons.check_rounded);
}

// ------------------------------------------------------------------ gestação

class _PregnancyCard extends StatelessWidget {
  const _PregnancyCard({required this.patient});
  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final dum = patient.dum!;
    final now = today();
    final ga = gestationalAge(dum, now);
    final dpp = dueDate(dum);
    final left = daysBetween(now, dpp);
    final phase = PrenatalPhase.of(ga);
    final dppText = left > 0
        ? 'faltam $left dias'
        : left == 0
            ? 'hoje'
            : 'passou há ${-left} dias';

    return OutlinedCard(
      color: AppColors.yellowSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.pregnant_woman_rounded),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Gestação', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              StatusBadge(text: '${ga.trimester}º trimestre', color: AppColors.surface),
            ],
          ),
          const SizedBox(height: 10),
          Text(ga.long, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const Text('idade gestacional hoje', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 10),
          ProgressPill(value: ga.totalDays / pregnancyDays, color: AppColors.yellow),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('DUM ${fmtDate(dum)}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              const Spacer(),
              const Text('40 semanas', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 8),
          InfoRow(icon: Icons.child_friendly_outlined, label: 'DPP', value: '${fmtDate(dpp)} · $dppText'),
          InfoRow(
            icon: Icons.event_repeat_rounded,
            label: 'Retornos',
            value: '${phase.label} (${phase.range})',
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final ph in PrenatalPhase.values)
                _Pill(
                  text: '${ph.label}: ${ph.range}',
                  color: ph == phase ? AppColors.yellow : AppColors.surface,
                ),
            ],
          ),
          if (ga.weeks >= postTermWeeks) ...[
            const SizedBox(height: 10),
            const Text(
              'Passou de 42 semanas. Registre o parto ou encerre a gestação.',
              style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(backgroundColor: AppColors.surface),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Registrar parto / encerrar'),
              onPressed: () => _endPregnancy(context, patient),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ink, width: 1.2),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

Future<void> _endPregnancy(BuildContext context, Patient p) async {
  final result = await showCreamSheet<(DateTime, bool)>(
    context,
    (_) => _EndPregnancySheet(dum: p.dum!),
  );
  if (result == null || !context.mounted) return;
  final (date, isBirth) = result;
  final data = context.read<AppData>();
  p.pregnancyEnd = date;
  final ok = await saveGuarded(context, () => data.savePatient(p));
  if (!ok || !context.mounted) return;
  if (!isBirth) {
    showSnack(context, 'Gestação encerrada.');
    return;
  }
  final register = await confirmDialog(
    context,
    title: 'Cadastrar o recém-nascido?',
    message: 'Abre o cadastro já com a data de nascimento, o telefone da mãe '
        'e a linha de puericultura.',
    confirm: 'Cadastrar',
  );
  if (!register || !context.mounted) return;
  final nav = Navigator.of(context);
  final baby = await nav.push<Patient>(
    MaterialPageRoute(
      builder: (_) => PatientFormScreen(
        initialName: 'RN de ${p.name}',
        initialBirth: date,
        initialPhone: p.phone,
        initialCareLines: [if (data.careLine(AppData.infantLineId) != null) AppData.infantLineId],
      ),
    ),
  );
  if (baby != null) {
    await nav.push(MaterialPageRoute(builder: (_) => PatientDetailScreen(patientId: baby.id)));
  }
}

class _EndPregnancySheet extends StatefulWidget {
  const _EndPregnancySheet({required this.dum});
  final DateTime dum;

  @override
  State<_EndPregnancySheet> createState() => _EndPregnancySheetState();
}

class _EndPregnancySheetState extends State<_EndPregnancySheet> {
  bool _birth = true;
  DateTime _date = today();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Registrar parto / encerrar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'A gestação sai do acompanhamento e fica no histórico da paciente.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            SegmentedPills<bool>(
              options: const [(true, 'Parto'), (false, 'Outro desfecho')],
              selected: _birth,
              selectedColor: AppColors.yellowSoft,
              onChanged: (v) => setState(() => _birth = v),
            ),
            const SizedBox(height: 12),
            DateField(
              label: _birth ? 'Data do parto' : 'Data do encerramento',
              value: _date,
              firstDate: widget.dum,
              lastDate: today(),
              onChanged: (d) => setState(() => _date = d ?? today()),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              icon: const Icon(Icons.check_rounded),
              label: Text(_birth ? 'Registrar parto em ${fmtDate(_date)}' : 'Encerrar em ${fmtDate(_date)}'),
              onPressed: () => Navigator.pop(context, (_date, _birth)),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- puericultura

class _InfantCard extends StatelessWidget {
  const _InfantCard({required this.birth, required this.doneVisits});
  final DateTime birth;
  final List<DateTime> doneVisits;

  @override
  Widget build(BuildContext context) {
    final now = today();
    final grid = infantVisitGrid(birth, doneVisits, now);
    final next = nextInfantVisit(birth, doneVisits, now);
    String? nextText;
    if (next != null) {
      nextText = next.currentMonth
          ? '${next.month}º mês: até ${fmtDate(addDays(addMonths(birth, next.month + 1), -1))}'
          : '${next.month}º mês: ${fmtDate(next.date)} (${relativeDays(next.date)})';
    }

    return OutlinedCard(
      color: AppColors.greenSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.child_care_rounded),
              SizedBox(width: 8),
              Text('Puericultura', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 10),
          Text(infantAgeLong(birth, now), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const Text('idade hoje', style: TextStyle(color: AppColors.muted)),
          if (nextText != null) ...[
            const SizedBox(height: 8),
            InfoRow(icon: Icons.event_available_outlined, label: 'Próx. retorno', value: nextText),
          ],
          const SizedBox(height: 10),
          const Text('Consultas mensais até 2 anos', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              const perRow = 8;
              const gap = 6.0;
              final size = ((constraints.maxWidth - gap * (perRow - 1)) / perRow).clamp(24.0, 44.0);
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [for (final m in grid) _MonthDot(month: m, size: size)],
              );
            },
          ),
          const SizedBox(height: 10),
          const Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _Legend(color: AppColors.green, text: 'realizada'),
              _Legend(color: AppColors.salmonSoft, text: 'sem consulta'),
              _Legend(color: AppColors.surface, text: 'a vir'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthDot extends StatelessWidget {
  const _MonthDot({required this.month, required this.size});
  final InfantMonth month;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = month.done
        ? AppColors.green
        : month.missed
            ? AppColors.salmonSoft
            : AppColors.surface;
    final state = month.done
        ? 'realizada'
        : month.missed
            ? 'sem consulta'
            : month.current
                ? 'mês atual'
                : 'a vir';
    return Semantics(
      label: '${month.month}º mês: $state',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.ink, width: month.current ? 3 : 1.2),
        ),
        child: Text(
          '${month.month}',
          style: TextStyle(fontSize: size * 0.32, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.ink, width: 1),
          ),
        ),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ],
    );
  }
}

class _PhoneRow extends StatelessWidget {
  const _PhoneRow({required this.phone});
  final String? phone;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onLongPress: phone == null
          ? null
          : () {
              Clipboard.setData(ClipboardData(text: phone!));
              showSnack(context, 'Telefone copiado.');
            },
      child: InfoRow(icon: Icons.phone_outlined, label: 'Telefone', value: phone ?? '—'),
    );
  }
}
