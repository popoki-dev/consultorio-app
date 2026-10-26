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

enum _GaMode { dum, gestationalAge }

/// Cadastro/edição de paciente. Retorna o paciente salvo.
class PatientFormScreen extends StatefulWidget {
  const PatientFormScreen({
    super.key,
    this.existing,
    this.initialName,
    this.initialBirth,
    this.initialCareLine,
    this.initialPhone,
  });

  final Patient? existing;
  final String? initialName;

  /// Usados ao cadastrar o recém-nascido a partir da ficha da mãe.
  final DateTime? initialBirth;
  final String? initialCareLine;
  final String? initialPhone;

  @override
  State<PatientFormScreen> createState() => _PatientFormScreenState();
}

class _PatientFormScreenState extends State<PatientFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _document = TextEditingController();
  final _notes = TextEditingController();
  final _cidInput = TextEditingController();
  final _gaWeeks = TextEditingController();
  final _gaDays = TextEditingController();
  DateTime? _birth;
  String? _sex;
  String? _careLine;
  List<String> _cids = [];
  bool _saving = false;

  bool _pregnant = false;
  _GaMode _gaMode = _GaMode.dum;
  DateTime? _dum;
  DateTime _gaMeasuredOn = today();

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    if (p != null) {
      _name.text = p.name;
      _phone.text = p.phone ?? '';
      _document.text = p.document ?? '';
      _notes.text = p.notes ?? '';
      _birth = p.birthDate;
      _sex = p.sex;
      _careLine = p.careLineId;
      _cids = [...p.cidCodes];
      _pregnant = p.pregnant;
      if (p.pregnant) _dum = p.dum;
    } else {
      _name.text = widget.initialName ?? '';
      _phone.text = widget.initialPhone ?? '';
      _birth = widget.initialBirth;
      _careLine = widget.initialCareLine;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _document, _notes, _cidInput, _gaWeeks, _gaDays]) {
      c.dispose();
    }
    super.dispose();
  }

  /// DUM informada ou calculada a partir da idade gestacional.
  DateTime? get _effectiveDum {
    if (_gaMode == _GaMode.dum) return _dum;
    final w = int.tryParse(_gaWeeks.text.trim());
    final d = _gaDays.text.trim().isEmpty ? 0 : int.tryParse(_gaDays.text.trim());
    if (w == null || d == null || w > 44 || d > 6) return null;
    return dumFromGestationalAge(weeks: w, days: d, measuredOn: _gaMeasuredOn);
  }

  /// Mensagem de erro da gestação, ou null se estiver tudo certo.
  String? _pregnancyError() {
    if (!_pregnant) return null;
    final dum = _effectiveDum;
    if (dum == null) {
      return _gaMode == _GaMode.dum
          ? 'Informe a data da última menstruação (DUM).'
          : 'Informe a idade gestacional: semanas (0–44) e dias (0–6).';
    }
    final ga = gestationalAge(dum, today());
    if (ga.totalDays < 0) return 'A DUM não pode estar no futuro.';
    if (ga.weeks > 44) return 'A idade gestacional passa de 44 semanas: confira a data.';
    return null;
  }

  void _addCids(String raw) {
    final codes = parseCidCodes(raw);
    if (codes.isEmpty) return;
    setState(() {
      for (final c in codes) {
        if (!_cids.contains(c)) _cids.add(c);
      }
      _cidInput.clear();
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final pregnancyError = _pregnancyError();
    if (pregnancyError != null) {
      showSnack(context, pregnancyError);
      return;
    }
    if (_cidInput.text.trim().isNotEmpty) _addCids(_cidInput.text);
    setState(() => _saving = true);
    final data = context.read<AppData>();
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final p = widget.existing ?? Patient(id: newId(), name: '');
    var careLine = _careLine;
    if (_pregnant) {
      p
        ..dum = _effectiveDum
        ..pregnancyEnd = null;
      if (careLine == null && data.careLine(AppData.prenatalLineId) != null) {
        careLine = AppData.prenatalLineId;
      }
    } else if (p.pregnant) {
      // Desmarcado: a gestação foi registrada por engano. (Para parto ou
      // encerramento há o botão na ficha, que mantém o histórico.)
      p.dum = null;
    }
    p
      ..name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ')
      ..birthDate = _birth
      ..sex = _sex
      ..phone = opt(_phone)
      ..document = opt(_document)
      ..careLineId = careLine
      ..cidCodes = _cids
      ..notes = opt(_notes);
    final ok = await saveGuarded(context, () => data.savePatient(p));
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, p);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final typed = _cidInput.text.trim().toUpperCase();
    final suggestions = cid10Common.entries
        .where((e) => !_cids.contains(e.key))
        .where((e) =>
            typed.isEmpty ||
            e.key.startsWith(typed) ||
            normalize(e.value).contains(normalize(typed)))
        .take(typed.isEmpty ? 8 : 12)
        .toList();

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 64,
        leading: const BackCircle(),
        title: Text(widget.existing == null ? 'NOVO PACIENTE' : 'EDITAR PACIENTE'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome completo *'),
              validator: (v) => (v ?? '').trim().length < 3 ? 'Informe o nome do paciente' : null,
            ),
            const SizedBox(height: 14),
            DateField(
              label: 'Data de nascimento',
              value: _birth,
              lastDate: DateTime.now(),
              inputMode: true,
              allowClear: true,
              onChanged: (d) => setState(() => _birth = d),
            ),
            if (_birth != null)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 4),
                child: Text(ageLabel(_birth), style: const TextStyle(color: AppColors.muted)),
              ),
            const SizedBox(height: 14),
            const _Label('Sexo'),
            Wrap(
              spacing: 8,
              children: [
                for (final s in Sex.values)
                  PillChip(
                    label: Sex.label(s),
                    selected: _sex == s,
                    onTap: () => setState(() {
                      _sex = _sex == s ? null : s;
                      if (_sex == Sex.male) _pregnant = false;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_sex != Sex.male) ...[
              _pregnancyCard(),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefone / WhatsApp', prefixIcon: Icon(Icons.phone_outlined)),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _document,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'CPF ou Cartão SUS (opcional)', prefixIcon: Icon(Icons.badge_outlined)),
            ),
            const SizedBox(height: 18),
            const _Label('Linha de cuidado'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PillChip(
                  label: 'Nenhuma',
                  selected: _careLine == null,
                  onTap: () => setState(() => _careLine = null),
                ),
                for (final c in data.careLines)
                  PillChip(
                    label: c.name,
                    dotColor: c.colorValue,
                    selected: _careLine == c.id,
                    onTap: () => setState(() => _careLine = c.id),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const _Label('Diagnósticos (CID-10)'),
            if (_cids.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in _cids)
                      InputChip(
                        label: Text(cidLabel(c)),
                        backgroundColor: AppColors.salmonSoft,
                        side: const BorderSide(color: AppColors.ink),
                        onDeleted: () => setState(() => _cids.remove(c)),
                      ),
                  ],
                ),
              ),
            TextField(
              controller: _cidInput,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              onSubmitted: _addCids,
              decoration: InputDecoration(
                labelText: 'Digite o código ou a doença',
                hintText: 'Ex.: I10, E11 ou "diabetes"',
                suffixIcon: IconButton(
                  tooltip: 'Adicionar',
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: () => _addCids(_cidInput.text),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in suggestions)
                  ActionChip(
                    label: Text('${e.key} · ${e.value}', style: const TextStyle(fontSize: 12)),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.hairline),
                    onPressed: () => _addCids(e.key),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _notes,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Observações (alergias, histórico, etc.)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Salvar paciente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pregnancyCard() {
    final dum = _pregnant ? _effectiveDum : null;
    final ga = dum == null ? null : gestationalAge(dum, today());
    final error = _pregnant && (_dum != null || _gaWeeks.text.isNotEmpty) ? _pregnancyError() : null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
      decoration: BoxDecoration(
        color: _pregnant ? AppColors.yellowSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: AppColors.ink, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gestante', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(
                      'Calcula idade gestacional, DPP e retornos do pré-natal',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _pregnant,
                onChanged: (v) => setState(() {
                  _pregnant = v;
                  if (v && _sex == null) _sex = Sex.female;
                }),
              ),
            ],
          ),
          if (_pregnant) ...[
            const SizedBox(height: 10),
            SegmentedPills<_GaMode>(
              options: const [
                (_GaMode.dum, 'Pela DUM'),
                (_GaMode.gestationalAge, 'Pela idade gestacional'),
              ],
              selected: _gaMode,
              onChanged: (m) => setState(() => _gaMode = m),
            ),
            const SizedBox(height: 12),
            if (_gaMode == _GaMode.dum)
              DateField(
                label: 'Data da última menstruação (DUM)',
                value: _dum,
                firstDate: addDays(today(), -44 * 7),
                lastDate: today(),
                inputMode: true,
                onChanged: (d) => setState(() => _dum = d),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _gaWeeks,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Semanas'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _gaDays,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(1)],
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Dias (0–6)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DateField(
                label: 'Idade gestacional medida em',
                value: _gaMeasuredOn,
                firstDate: addDays(today(), -44 * 7),
                lastDate: today(),
                onChanged: (d) => setState(() => _gaMeasuredOn = d ?? today()),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
            ] else if (dum != null && ga != null) ...[
              const SizedBox(height: 12),
              Text(
                'Idade gestacional hoje: ${ga.long}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                'Data provável do parto (DPP): ${fmtDate(dueDate(dum))}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (_gaMode == _GaMode.gestationalAge)
                Text(
                  'DUM equivalente: ${fmtDate(dum)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
            ],
          ],
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
