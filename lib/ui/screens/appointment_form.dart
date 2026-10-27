import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_data.dart';
import '../../data/care_rules.dart';
import '../../data/models.dart';
import '../widgets.dart';
import 'appointment_actions.dart';
import 'patient_picker.dart';

class AppointmentFormScreen extends StatefulWidget {
  const AppointmentFormScreen({
    super.key,
    this.existing,
    this.patientId,
    this.date,
    this.fromReminder,
  });

  final Appointment? existing;
  final String? patientId;
  final DateTime? date;

  /// Ao agendar a partir de um lembrete de receita/exame, ele é dado como
  /// resolvido (o retorno se resolve sozinho quando há consulta posterior).
  final Reminder? fromReminder;

  @override
  State<AppointmentFormScreen> createState() => _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends State<AppointmentFormScreen> {
  String? _patientId;
  late DateTime _day;
  late TimeOfDay _time;
  int _duration = 30;
  String _status = ApptStatus.scheduled;
  DateTime? _returnDue;
  final _notes = TextEditingController();
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final data = context.read<AppData>();
    final e = widget.existing;
    if (e != null) {
      _patientId = e.patientId;
      _day = dateOnly(e.startAt);
      _time = TimeOfDay(hour: e.startAt.hour, minute: e.startAt.minute);
      _duration = e.durationMin;
      _status = e.status;
      _returnDue = e.returnDue;
      _notes.text = e.notes ?? '';
    } else {
      _patientId = widget.patientId;
      final d = dateOnly(widget.date ?? DateTime.now());
      _day = d.isBefore(today()) ? today() : d;
      _time = _suggestTime(data, _day);
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  /// Primeiro horário livre do dia, de 30 em 30 minutos, das 8h às 18h.
  TimeOfDay _suggestTime(AppData data, DateTime day) {
    final busy = data
        .appointmentsOn(day)
        .where((a) => a.status != ApptStatus.cancelled)
        .toList();
    final now = DateTime.now();
    for (var m = 8 * 60; m < 18 * 60; m += 30) {
      final start = DateTime(day.year, day.month, day.day, m ~/ 60, m % 60);
      if (sameDay(day, now) && start.isBefore(now)) continue;
      final end = start.add(Duration(minutes: _duration));
      final clash = busy.any((a) => start.isBefore(a.endAt) && a.startAt.isBefore(end));
      if (!clash) return TimeOfDay(hour: m ~/ 60, minute: m % 60);
    }
    return const TimeOfDay(hour: 8, minute: 0);
  }

  DateTime get _start => DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute);

  List<Appointment> _clashes(AppData data) {
    final start = _start;
    final end = start.add(Duration(minutes: _duration));
    return data
        .appointmentsOn(_day)
        .where((a) =>
            a.id != widget.existing?.id &&
            a.status != ApptStatus.cancelled &&
            start.isBefore(a.endAt) &&
            a.startAt.isBefore(end))
        .toList();
  }

  Future<void> _save() async {
    final data = context.read<AppData>();
    if (_patientId == null) {
      showSnack(context, 'Selecione o paciente.');
      return;
    }
    setState(() => _saving = true);
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    final appt = widget.existing ??
        Appointment(id: newId(), patientId: _patientId!, startAt: _start);
    appt
      ..patientId = _patientId!
      ..startAt = _start
      ..durationMin = _duration
      ..status = _status
      ..notes = notes;
    if (_status == ApptStatus.done) {
      if (appt.returnDue != _returnDue) appt.returnResolved = false;
      appt.returnDue = _returnDue;
    }
    final ok = await saveGuarded(context, () async {
      await data.saveAppointment(appt);
      final r = widget.fromReminder;
      if (r != null && r.kind != ReminderKind.returnVisit) {
        await data.setReminderResolved(r, true);
      }
    });
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final patient = data.patient(_patientId);
    final lines = data.careLinesOf(patient);
    final last = patient == null ? null : data.lastVisit(patient.id);
    final clashes = _clashes(data);
    final suggestion = patient == null ? null : suggestReturn(patient, lines, _day);

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 64,
        leading: const BackCircle(),
        title: Text(_editing ? 'EDITAR CONSULTA' : 'NOVA CONSULTA'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _Label('Paciente'),
          OutlinedCard(
            color: patient == null ? AppColors.yellowSoft : AppColors.surface,
            onTap: _editing
                ? null
                : () async {
                    final p = await pickPatient(context);
                    if (p != null) setState(() => _patientId = p.id);
                  },
            child: Row(
              children: [
                patient == null
                    ? const Icon(Icons.person_search_outlined, size: 30)
                    : Avatar(name: patient.name, color: lines.firstOrNull?.colorValue ?? AppColors.yellowSoft, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient?.name ?? 'Toque para selecionar o paciente',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      if (patient != null)
                        Text(
                          'Última consulta: ${last == null ? 'nenhuma' : fmtDate(last.startAt)}'
                          '${lines.map((l) => ' · ${l.name}').join()}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                if (!_editing) const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: DateField(
                  label: 'Data',
                  value: _day,
                  firstDate: DateTime(2020),
                  onChanged: (d) {
                    if (d == null) return;
                    setState(() {
                      _day = d;
                      if (!_editing) _time = _suggestTime(data, d);
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: _time,
                      helpText: 'Horário',
                    );
                    if (t != null) setState(() => _time = t);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Horário',
                      suffixIcon: Icon(Icons.schedule_rounded, size: 20),
                    ),
                    child: Text(fmtTime(_start), style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
          if (clashes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warnSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.ink, width: 1.2),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Conflito de horário com ${clashes.map((a) => '${data.patient(a.patientId)?.name ?? 'outro paciente'} (${fmtTime(a.startAt)})').join(', ')}.',
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          const _Label('Duração'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in const [15, 20, 30, 45, 60])
                PillChip(
                  label: '$m min',
                  selected: _duration == m,
                  onTap: () => setState(() => _duration = m),
                ),
            ],
          ),
          if (_editing) ...[
            const SizedBox(height: 18),
            const _Label('Situação'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in const [
                  ApptStatus.scheduled,
                  ApptStatus.done,
                  ApptStatus.missed,
                  ApptStatus.cancelled,
                ])
                  PillChip(
                    label: ApptStatus.label(s),
                    selected: _status == s,
                    onTap: () => setState(() {
                      _status = s;
                      if (s == ApptStatus.done && _returnDue == null) _returnDue = suggestion?.date;
                    }),
                  ),
              ],
            ),
          ],
          if (_status == ApptStatus.done) ...[
            const SizedBox(height: 18),
            const _Label('Previsão de retorno'),
            if (suggestion != null) ...[
              SuggestionCard(
                suggestion: suggestion,
                selected: _returnDue != null && sameDay(_returnDue!, suggestion.date),
                onTap: () => setState(() => _returnDue = suggestion.date),
              ),
              const SizedBox(height: 10),
            ],
            QuickDateChips(
              from: _day,
              selected: _returnDue,
              noneLabel: 'Sem retorno',
              options: returnOptions,
              onChanged: (d) => setState(() => _returnDue = d),
            ),
            const SizedBox(height: 10),
            DateField(
              label: 'Data do retorno',
              value: _returnDue,
              allowClear: true,
              onChanged: (d) => setState(() => _returnDue = d),
            ),
          ],
          const SizedBox(height: 18),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Observações (opcional)', alignLabelWithHint: true),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(_editing ? 'Salvar alterações' : 'Agendar consulta'),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      );
}
