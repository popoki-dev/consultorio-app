import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_data.dart';
import '../../data/models.dart';
import '../widgets.dart';
import 'patient_form.dart';

/// Busca por nome (sem acentos), telefone, CPF ou CID.
bool matchesPatient(Patient p, String query) {
  final q = normalize(query.trim());
  if (q.isEmpty) return true;
  if (normalize(p.name).contains(q)) return true;
  final digits = digitsOnly(q);
  if (digits.length >= 3) {
    if (digitsOnly(p.phone ?? '').contains(digits)) return true;
    if (digitsOnly(p.document ?? '').contains(digits)) return true;
  }
  return p.cidCodes.any((c) => normalize(c).startsWith(q));
}

Future<Patient?> pickPatient(BuildContext context) {
  return showModalBottomSheet<Patient>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.cream,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      side: kBorder,
    ),
    builder: (_) => const _PatientPickerSheet(),
  );
}

class _PatientPickerSheet extends StatefulWidget {
  const _PatientPickerSheet();

  @override
  State<_PatientPickerSheet> createState() => _PatientPickerSheetState();
}

class _PatientPickerSheetState extends State<_PatientPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final list = data.patients.where((p) => matchesPatient(p, _q)).toList();
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(4)),
            ),
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('SELECIONAR PACIENTE',
                  style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Nome, telefone ou CPF',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Cadastrar novo paciente'),
                  onPressed: () async {
                    final created = await Navigator.of(context).push<Patient>(
                      MaterialPageRoute(
                        builder: (_) => PatientFormScreen(initialName: _q.trim()),
                      ),
                    );
                    if (created != null && context.mounted) Navigator.pop(context, created);
                  },
                ),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(icon: Icons.person_search_outlined, text: 'Nenhum paciente encontrado')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final p = list[i];
                        final line = data.careLine(p.careLineId);
                        return OutlinedCard(
                          padding: const EdgeInsets.all(10),
                          onTap: () => Navigator.pop(context, p),
                          child: Row(
                            children: [
                              Avatar(name: p.name, color: line?.colorValue ?? AppColors.yellowSoft, size: 38),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text(
                                      [ageLabel(p.birthDate), if (line != null) line.name].join(' · '),
                                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
