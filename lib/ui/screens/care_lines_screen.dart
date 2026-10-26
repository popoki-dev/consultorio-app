import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/app_data.dart';
import '../../data/models.dart';
import '../widgets.dart';

class CareLinesScreen extends StatelessWidget {
  const CareLinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 64,
        leading: const BackCircle(),
        title: const Text('LINHAS DE CUIDADO'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-lines',
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nova linha', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          const Text(
            'As linhas de cuidado organizam os pacientes e o painel epidemiológico. '
            'O retorno padrão é sugerido ao concluir uma consulta.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          for (final c in data.careLines)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedCard(
                onTap: () => _edit(context, c),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: c.colorValue,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.ink, width: 1.3),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                          Text(
                            '${data.patients.where((p) => p.careLineId == c.id).length} pacientes · '
                            'retorno padrão: ${c.defaultReturnDays == null ? 'não definido' : '${c.defaultReturnDays} dias'}',
                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.edit_outlined, size: 20),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, CareLine? existing) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        side: kBorder,
      ),
      builder: (_) => _CareLineEditor(existing: existing),
    );
  }
}

class _CareLineEditor extends StatefulWidget {
  const _CareLineEditor({this.existing});
  final CareLine? existing;

  @override
  State<_CareLineEditor> createState() => _CareLineEditorState();
}

class _CareLineEditorState extends State<_CareLineEditor> {
  final _name = TextEditingController();
  late int _color;
  int? _days;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name.text = c?.name ?? '';
    _color = c?.color ?? AppColors.careLinePalette.first.toARGB32();
    _days = c == null ? 90 : c.defaultReturnDays;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final data = context.read<AppData>();
    final c = widget.existing ?? CareLine(id: newId(), name: name, color: _color);
    c
      ..name = name
      ..color = _color
      ..defaultReturnDays = _days;
    await data.saveCareLine(c);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final data = context.read<AppData>();
    final c = widget.existing!;
    final inUse = data.patients.where((p) => p.careLineId == c.id).length;
    if (inUse > 0) {
      showSnack(context, 'Há $inUse paciente(s) nesta linha. Mova-os antes de excluir.');
      return;
    }
    if (!await confirmDialog(context, title: 'Excluir "${c.name}"?', message: 'A linha de cuidado será removida.', confirm: 'Excluir', danger: true)) {
      return;
    }
    await data.delete(c);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 18, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null ? 'Nova linha de cuidado' : 'Editar linha de cuidado',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: widget.existing == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nome (ex.: Hipertensão)'),
          ),
          const SizedBox(height: 14),
          const Text('Cor', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in AppColors.careLinePalette)
                GestureDetector(
                  onTap: () => setState(() => _color = color.toARGB32()),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.ink, width: _color == color.toARGB32() ? 3 : 1.2),
                    ),
                    child: _color == color.toARGB32() ? const Icon(Icons.check_rounded, size: 18) : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text('Retorno padrão', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PillChip(label: 'Nenhum', selected: _days == null, onTap: () => setState(() => _days = null)),
              for (final (d, label) in const [(30, '30 dias'), (60, '60 dias'), (90, '90 dias'), (120, '120 dias'), (180, '6 meses'), (365, '1 ano')])
                PillChip(label: label, selected: _days == d, onTap: () => setState(() => _days = d)),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Salvar')),
          if (widget.existing != null) ...[
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: _delete,
              child: const Text('Excluir linha de cuidado'),
            ),
          ],
        ],
      ),
    );
  }
}
