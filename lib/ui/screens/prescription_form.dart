import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_data.dart';
import '../../data/models.dart';
import '../widgets.dart';

const _validityOptions = [
  (30, '30 dias'),
  (60, '60 dias'),
  (90, '90 dias'),
  (120, '120 dias'),
  (180, '6 meses'),
  (365, '1 ano'),
];

/// Receituário: vários medicamentos emitidos juntos para um paciente. Cada
/// medicamento tem a própria validade; os que vencem no mesmo dia geram um
/// lembrete só.
class PrescriptionFormScreen extends StatefulWidget {
  const PrescriptionFormScreen({super.key, required this.patientId, this.existing});

  final String patientId;

  /// Medicamentos do receituário em edição.
  final List<Prescription>? existing;

  @override
  State<PrescriptionFormScreen> createState() => _PrescriptionFormScreenState();
}

/// Um medicamento no formulário.
class _Item {
  _Item({this.source, String medication = '', String dosage = '', this.expires, this.resolved = false})
      : medication = TextEditingController(text: medication),
        dosage = TextEditingController(text: dosage);

  /// Receita já gravada (null para medicamento novo).
  final Prescription? source;
  final TextEditingController medication;
  final TextEditingController dosage;
  DateTime? expires;
  bool resolved;

  void dispose() {
    medication.dispose();
    dosage.dispose();
  }
}

class _PrescriptionFormScreenState extends State<PrescriptionFormScreen> {
  final _form = GlobalKey<FormState>();
  final _notes = TextEditingController();
  late DateTime _issued;
  final _items = <_Item>[];
  bool _saving = false;

  bool get _editing => widget.existing?.isNotEmpty ?? false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing ?? const [];
    _issued = existing.firstOrNull?.issuedAt ?? today();
    _notes.text = existing.firstOrNull?.notes ?? '';
    for (final r in existing) {
      _items.add(_Item(
        source: r,
        medication: r.medication,
        dosage: r.dosage ?? '',
        expires: r.expiresAt,
        resolved: r.resolved,
      ));
    }
    if (_items.isEmpty) _items.add(_Item(expires: addDays(_issued, 30)));
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  /// Validade comum a todos os medicamentos (null se forem diferentes).
  DateTime? get _commonExpiry {
    final first = _items.first.expires;
    if (first == null) return null;
    return _items.every((i) => i.expires != null && sameDay(i.expires!, first)) ? first : null;
  }

  void _addItem() {
    final last = _items.last.expires;
    setState(() => _items.add(_Item(expires: last ?? addDays(_issued, 30))));
  }

  void _removeItem(_Item item) {
    setState(() => _items.remove(item));
    // Descartado só depois do quadro: o campo ainda está na árvore agora.
    WidgetsBinding.instance.addPostFrameCallback((_) => item.dispose());
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_items.any((i) => i.expires == null)) {
      showSnack(context, 'Informe a validade de cada medicamento.');
      return;
    }
    setState(() => _saving = true);
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final existing = widget.existing ?? const [];
    // Receitas anteriores à v1.3 não têm grupo: a primeira dá o id do
    // receituário, para os medicamentos acrescentados ficarem com ela.
    final groupId = existing.firstOrNull?.groupKey ?? newId();
    final notes = opt(_notes);

    final items = [
      for (final i in _items)
        (i.source ??
            Prescription(
              id: newId(),
              patientId: widget.patientId,
              medication: '',
              issuedAt: _issued,
              expiresAt: i.expires!,
            ))
          ..medication = i.medication.text.trim()
          ..dosage = opt(i.dosage)
          ..issuedAt = _issued
          ..expiresAt = i.expires!
          ..resolved = i.resolved
          ..notes = notes
          ..groupId = groupId,
    ];
    final kept = {for (final i in _items) i.source?.id};
    final removed = existing.where((r) => !kept.contains(r.id)).toList();

    final data = context.read<AppData>();
    final ok = await saveGuarded(context, () => data.saveReceituario(items, removed: removed));
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Excluir receituário?',
      message: _items.length == 1
          ? 'Esta receita será removida.'
          : 'Os ${_items.length} medicamentos deste receituário serão removidos.',
      confirm: 'Excluir',
      danger: true,
    );
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    await context.read<AppData>().deleteMany(widget.existing!);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final patient = data.patient(widget.patientId);
    // Medicamentos já usados no consultório, como atalho.
    final known = {for (final r in data.prescriptions) r.medication}.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 64,
        leading: const BackCircle(),
        title: Text(_editing ? 'RECEITUÁRIO' : 'NOVO RECEITUÁRIO'),
        actions: [
          if (_editing)
            IconButton(
              tooltip: 'Excluir',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _delete,
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
            DateField(
              label: 'Data da receita',
              value: _issued,
              onChanged: (d) {
                if (d == null) return;
                setState(() {
                  // Cada medicamento mantém o prazo que tinha.
                  for (final i in _items) {
                    if (i.expires != null) i.expires = addDays(d, daysBetween(_issued, i.expires!));
                  }
                  _issued = d;
                });
              },
            ),
            const SizedBox(height: 18),
            const Text('Validade de todos', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            QuickDateChips(
              from: _issued,
              selected: _commonExpiry,
              options: _validityOptions,
              onChanged: (d) => setState(() {
                for (final i in _items) {
                  i.expires = d;
                }
              }),
            ),
            const SizedBox(height: 4),
            const Text(
              'Para um medicamento com prazo diferente, mude a data no próprio medicamento.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            SectionTitle(
              'Medicamentos',
              trailing: StatusBadge(text: '${_items.length}', color: AppColors.surface),
            ),
            for (final (n, item) in _items.indexed)
              Padding(
                key: ObjectKey(item),
                padding: const EdgeInsets.only(bottom: 10),
                child: _ItemCard(
                  number: n + 1,
                  item: item,
                  issued: _issued,
                  known: known,
                  onChanged: () => setState(() {}),
                  onRemove: _items.length == 1 ? null : () => _removeItem(item),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adicionar medicamento'),
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Observações', alignLabelWithHint: true),
            ),
            const SizedBox(height: 10),
            const Text(
              'Você receberá um lembrete antes do vencimento (ajustável em Ajustes). '
              'Medicamentos que vencem no mesmo dia geram um lembrete só.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Salvar receituário'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.number,
    required this.item,
    required this.issued,
    required this.known,
    required this.onChanged,
    required this.onRemove,
  });

  final int number;
  final _Item item;
  final DateTime issued;
  final List<String> known;
  final VoidCallback onChanged;

  /// Null quando é o único medicamento.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final typed = normalize(item.medication.text);
    final suggestions = typed.length < 2
        ? <String>[]
        : known.where((m) => normalize(m).contains(typed) && normalize(m) != typed).take(6).toList();

    return OutlinedCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Medicamento $number', style: const TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Tirar do receituário',
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  onPressed: onRemove,
                ),
            ],
          ),
          TextFormField(
            controller: item.medication,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => onChanged(),
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
                      onPressed: () {
                        item.medication.text = s;
                        onChanged();
                      },
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          TextFormField(
            controller: item.dosage,
            decoration: const InputDecoration(labelText: 'Posologia (ex.: 50 mg 12/12h)'),
          ),
          const SizedBox(height: 12),
          DateField(
            label: 'Válida até',
            value: item.expires,
            firstDate: issued,
            onChanged: (d) {
              item.expires = d;
              onChanged();
            },
          ),
          if (item.source != null) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 4),
              value: item.resolved,
              onChanged: (v) {
                item.resolved = v;
                onChanged();
              },
              title: const Text('Renovada / encerrada', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Não gera mais lembrete de vencimento'),
            ),
          ],
        ],
      ),
    );
  }
}
