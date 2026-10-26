import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cid10.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_data.dart';
import '../../data/models.dart';
import '../widgets.dart';

/// Registro de exame com o resultado digitado em texto.
class ExamFormScreen extends StatefulWidget {
  const ExamFormScreen({super.key, required this.patientId, this.existing});

  final String patientId;
  final Exam? existing;

  @override
  State<ExamFormScreen> createState() => _ExamFormScreenState();
}

class _ExamFormScreenState extends State<ExamFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _result = TextEditingController();
  late DateTime _performed;
  DateTime? _nextDue;
  bool _resolved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _performed = e?.performedAt ?? today();
    _nextDue = e?.nextDue;
    _resolved = e?.resolved ?? false;
    _name.text = e?.name ?? '';
    _result.text = e?.result ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _result.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final e = widget.existing ??
        Exam(id: newId(), patientId: widget.patientId, name: '', performedAt: _performed);
    e
      ..name = _name.text.trim()
      ..performedAt = _performed
      ..result = _result.text.trim()
      ..nextDue = _nextDue
      ..resolved = _resolved;
    final data = context.read<AppData>();
    final ok = await saveGuarded(context, () => data.saveExam(e));
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final patient = data.patient(widget.patientId);
    final typed = normalize(_name.text);
    final suggestions = commonExams
        .where((x) => typed.isEmpty || (normalize(x).contains(typed) && normalize(x) != typed))
        .take(typed.isEmpty ? 10 : 6)
        .toList();
    final previous = data
        .examsOf(widget.patientId)
        .where((x) => x.id != widget.existing?.id && typed.length > 2 && normalize(x.name) == typed)
        .take(3)
        .toList();

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 64,
        leading: const BackCircle(),
        title: Text(widget.existing == null ? 'NOVO EXAME' : 'EXAME'),
        actions: [
          if (widget.existing != null)
            IconButton(
              tooltip: 'Excluir',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: 'Excluir exame?', message: 'Este exame será removido.', confirm: 'Excluir', danger: true);
                if (!ok || !context.mounted) return;
                final nav = Navigator.of(context);
                await context.read<AppData>().delete(widget.existing!);
                nav.pop();
              },
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (patient != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(patient.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Exame *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o exame' : null,
            ),
            if (widget.existing == null && suggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in suggestions)
                      ActionChip(
                        label: Text(s, style: const TextStyle(fontSize: 12)),
                        backgroundColor: AppColors.surface,
                        side: const BorderSide(color: AppColors.hairline),
                        onPressed: () => setState(() => _name.text = s),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            DateField(
              label: 'Data de realização',
              value: _performed,
              lastDate: DateTime.now(),
              onChanged: (d) {
                if (d != null) setState(() => _performed = d);
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _result,
              minLines: 5,
              maxLines: 16,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Resultado',
                hintText: 'Ex.: HbA1c 7,2% · Glicemia 128 mg/dL',
                alignLabelWithHint: true,
              ),
            ),
            if (previous.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Resultados anteriores', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              for (final x in previous)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: OutlinedCard(
                    color: AppColors.purpleSoft,
                    padding: const EdgeInsets.all(10),
                    radius: 14,
                    child: Text('${fmtDate(x.performedAt)} — ${x.result.isEmpty ? 'sem resultado' : x.result}'),
                  ),
                ),
            ],
            const SizedBox(height: 18),
            const Text('Repetir este exame?', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            QuickDateChips(
              from: _performed,
              selected: _nextDue,
              noneLabel: 'Não repetir',
              options: const [(90, '3 meses'), (180, '6 meses'), (365, '1 ano'), (730, '2 anos')],
              onChanged: (d) => setState(() => _nextDue = d),
            ),
            const SizedBox(height: 10),
            DateField(
              label: 'Data para repetir',
              value: _nextDue,
              allowClear: true,
              onChanged: (d) => setState(() => _nextDue = d),
            ),
            if (widget.existing != null && _nextDue != null) ...[
              const SizedBox(height: 12),
              OutlinedCard(
                padding: EdgeInsets.zero,
                child: SwitchListTile(
                  value: _resolved,
                  onChanged: (v) => setState(() => _resolved = v),
                  title: const Text('Repetição já solicitada', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Não gera mais lembrete'),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Salvar exame'),
            ),
          ],
        ),
      ),
    );
  }
}
