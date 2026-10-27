import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_data.dart';
import '../../data/care_rules.dart';
import '../../data/models.dart';
import '../widgets.dart';
import 'appointment_form.dart';
import 'patient_detail.dart';

Future<T?> showCreamSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      side: kBorder,
    ),
    builder: builder,
  );
}

Future<void> openAppointmentForm(
  BuildContext context, {
  Appointment? existing,
  String? patientId,
  DateTime? date,
  Reminder? fromReminder,
}) async {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => AppointmentFormScreen(
        existing: existing,
        patientId: patientId,
        date: date,
        fromReminder: fromReminder,
      ),
    ),
  );
  if (saved == true && context.mounted) showSnack(context, 'Consulta salva.');
}

/// Ações rápidas ao tocar numa consulta.
Future<void> showAppointmentActions(BuildContext context, Appointment a) async {
  final data = context.read<AppData>();
  final patient = data.patient(a.patientId);
  final choice = await showCreamSheet<String>(
    context,
    (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              patient?.name ?? 'Paciente',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              '${fmtDayLong(a.startAt)} · ${fmtTime(a.startAt)} · ${ApptStatus.label(a.status)}',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            if (a.status != ApptStatus.done)
              _action(ctx, 'done', Icons.check_circle_outline_rounded, 'Marcar como realizada', AppColors.okSoft),
            if (a.status == ApptStatus.scheduled)
              _action(ctx, 'missed', Icons.person_off_outlined, 'Paciente faltou', AppColors.dangerSoft),
            if (a.status != ApptStatus.scheduled)
              _action(ctx, 'reopen', Icons.undo_rounded, 'Voltar para "agendada"', AppColors.yellowSoft),
            _action(ctx, 'edit', Icons.edit_outlined, 'Editar / remarcar', AppColors.surface),
            _action(ctx, 'patient', Icons.badge_outlined, 'Abrir ficha do paciente', AppColors.surface),
            if (a.status == ApptStatus.scheduled)
              _action(ctx, 'cancel', Icons.event_busy_outlined, 'Cancelar consulta', AppColors.surface),
            _action(ctx, 'delete', Icons.delete_outline_rounded, 'Excluir registro', AppColors.surface),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  switch (choice) {
    case 'done':
      await markDone(context, a);
    case 'missed':
      a.status = ApptStatus.missed;
      await data.saveAppointment(a);
      if (context.mounted) {
        showSnack(
          context,
          'Falta registrada.',
          action: SnackBarAction(
            label: 'Reagendar',
            onPressed: () => openAppointmentForm(context, patientId: a.patientId),
          ),
        );
      }
    case 'reopen':
      a.status = ApptStatus.scheduled;
      await data.saveAppointment(a);
    case 'edit':
      await openAppointmentForm(context, existing: a);
    case 'patient':
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PatientDetailScreen(patientId: a.patientId)),
      );
    case 'cancel':
      if (await confirmDialog(context,
          title: 'Cancelar consulta?', message: 'A consulta continuará no histórico como cancelada.',
          confirm: 'Cancelar consulta')) {
        a.status = ApptStatus.cancelled;
        await data.saveAppointment(a);
      }
    case 'delete':
      if (await confirmDialog(context,
          title: 'Excluir registro?', message: 'O registro desta consulta será removido.',
          confirm: 'Excluir', danger: true)) {
        await data.delete(a);
      }
  }
}

Widget _action(BuildContext ctx, String value, IconData icon, String label, Color color) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: OutlinedCard(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: 16,
      onTap: () => Navigator.pop(ctx, value),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
        ],
      ),
    ),
  );
}

/// Conclui a consulta e pergunta a previsão de retorno.
Future<void> markDone(BuildContext context, Appointment a) async {
  final data = context.read<AppData>();
  final patient = data.patient(a.patientId);
  final result = await askReturnDate(
    context,
    from: dateOnly(a.startAt),
    suggestion: patient == null
        ? null
        : suggestReturn(patient, data.careLinesOf(patient), a.startAt),
  );
  if (result == null) return;
  a
    ..status = ApptStatus.done
    ..returnDue = result.date
    ..returnResolved = false;
  await data.saveAppointment(a);
  if (context.mounted) {
    showSnack(
      context,
      result.date == null
          ? 'Consulta registrada.'
          : 'Consulta registrada. Retorno previsto para ${fmtDate(result.date)}.',
    );
  }
}

class ReturnChoice {
  const ReturnChoice(this.date);
  final DateTime? date;
}

Future<ReturnChoice?> askReturnDate(
  BuildContext context, {
  required DateTime from,
  ReturnSuggestion? suggestion,
}) {
  return showCreamSheet<ReturnChoice>(
    context,
    (_) => _ReturnSheet(from: from, suggestion: suggestion),
  );
}

/// Opções rápidas de retorno (a partir da data da consulta).
const returnOptions = [
  (7, '7 dias'),
  (14, '14 dias'),
  (30, '30 dias'),
  (60, '60 dias'),
  (90, '90 dias'),
  (180, '6 meses'),
  (365, '1 ano'),
];

class _ReturnSheet extends StatefulWidget {
  const _ReturnSheet({required this.from, required this.suggestion});
  final DateTime from;
  final ReturnSuggestion? suggestion;

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  late DateTime? _date = widget.suggestion?.date;

  @override
  Widget build(BuildContext context) {
    final s = widget.suggestion;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Consulta realizada', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Quando o paciente deve retornar?', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            if (s != null) ...[
              SuggestionCard(
                suggestion: s,
                selected: _date != null && sameDay(_date!, s.date),
                onTap: () => setState(() => _date = s.date),
              ),
              const SizedBox(height: 12),
            ],
            QuickDateChips(
              from: widget.from,
              selected: _date,
              noneLabel: 'Sem retorno',
              options: returnOptions,
              onChanged: (d) => setState(() => _date = d),
            ),
            const SizedBox(height: 12),
            DateField(
              label: 'Ou escolha a data',
              value: _date,
              allowClear: true,
              onChanged: (d) => setState(() => _date = d),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              icon: const Icon(Icons.check_rounded),
              label: Text(_date == null ? 'Confirmar sem retorno' : 'Confirmar retorno em ${fmtDate(_date)}'),
              onPressed: () => Navigator.pop(context, ReturnChoice(_date)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartão "Sugestão: dd/mm/aaaa (em N dias)" com o motivo.
class SuggestionCard extends StatelessWidget {
  const SuggestionCard({
    super.key,
    required this.suggestion,
    required this.selected,
    required this.onTap,
  });

  final ReturnSuggestion suggestion;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedCard(
      color: selected ? AppColors.yellowSoft : AppColors.surface,
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          Icon(selected ? Icons.check_circle_rounded : Icons.lightbulb_outline_rounded, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sugestão: ${fmtDate(suggestion.date)} (${relativeDays(suggestion.date)})',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(suggestion.reason, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
