import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_data.dart';
import '../../data/models.dart';
import '../widgets.dart';

class PrescriptionFormScreen extends StatefulWidget {
  const PrescriptionFormScreen({super.key, required this.patientId, this.existing});

  final String patientId;
  final Prescription? existing;

  @override
  State<PrescriptionFormScreen> createState() => _PrescriptionFormScreenState();
}

class _PrescriptionFormScreenState extends State<PrescriptionFormScreen> {
  final _form = GlobalKey<FormState>();
  final _medication = TextEditingController();
  final _dosage = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _issued;
  DateTime? _expires;
  bool _resolved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _issued = r?.issuedAt ?? today();
    _expires = r?.expiresAt ?? addDays(_issued, 30);
    _resolved = r?.resolved ?? false;
    _medication.text = r?.medication ?? '';
    _dosage.text = r?.dosage ?? '';
    _notes.text = r?.notes ?? '';
  }

  @override
  void dispose() {
    _medication.dispose();
    _dosage.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_expires == null) {
      showSnack(context, 'Informe a validade da receita.');
      return;
    }
    setState(() => _saving = true);
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final r = widget.existing ??
        Prescription(
          id: newId(),
          patientId: widget.patientId,
          medication: '',
          issuedAt: _issued,
          expiresAt: _expires!,
        );
    r
      ..medication = _medication.text.trim()
      ..dosage = opt(_dosage)
      ..issuedAt = _issued
      ..expiresAt = _expires!
      ..resolved = _resolved
      ..notes = opt(_notes);
    final data = context.read<AppData>();
    final ok = await saveGuarded(context, () => data.savePrescription(r));
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
    // Medicamentos já usados no consultório, como atalho.
    final known = {for (final r in data.prescriptions) r.medication}.toList()..sort();
    final typed = normalize(_medication.text);
    final suggestions = typed.length < 2
        ? <String>[]
        : known.where((m) => normalize(m).contains(typed) && normalize(m) != typed).take(6).toList();

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 64,
        leading: const BackCircle(),
        title: Text(widget.existing == null ? 'NOVA RECEITA' : 'RECEITA'),
        actions: [
          if (widget.existing != null)
            IconButton(
              tooltip: 'Excluir',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: 'Excluir receita?', message: 'Esta receita será removida.', confirm: 'Excluir', danger: true);
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
              controller: _medication,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Medicamento *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Informe o medicamento' : null,
            ),
            if (suggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in suggestions)
                      ActionChip(
                        label: Text(s),
                        backgroundColor: AppColors.surface,
                        side: const BorderSide(color: AppColors.hairline),
                        onPressed: () => setState(() => _medication.text = s),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _dosage,
              decoration: const InputDecoration(labelText: 'Posologia (ex.: 50 mg 12/12h)'),
            ),
            const SizedBox(height: 14),
            DateField(
              label: 'Data da receita',
              value: _issued,
              onChanged: (d) {
                if (d == null) return;
                setState(() {
                  final days = _expires == null ? 30 : daysBetween(_issued, _expires!);
                  _issued = d;
                  _expires = addDays(d, days);
                });
              },
            ),
            const SizedBox(height: 18),
            const Text('Validade', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            QuickDateChips(
              from: _issued,
              selected: _expires,
              options: const [(30, '30 dias'), (60, '60 dias'), (90, '90 dias'), (120, '120 dias'), (180, '6 meses'), (365, '1 ano')],
              onChanged: (d) => setState(() => _expires = d),
            ),
            const SizedBox(height: 10),
            DateField(
              label: 'Válida até',
              value: _expires,
              onChanged: (d) => setState(() => _expires = d),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 12),
              OutlinedCard(
                padding: EdgeInsets.zero,
                child: SwitchListTile(
                  value: _resolved,
                  onChanged: (v) => setState(() => _resolved = v),
                  title: const Text('Receita renovada / encerrada', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Não gera mais lembrete de vencimento'),
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Observações', alignLabelWithHint: true),
            ),
            const SizedBox(height: 10),
            const Text(
              'Você receberá um lembrete antes do vencimento (ajustável em Ajustes).',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Salvar receita'),
            ),
          ],
        ),
      ),
    );
  }
}
