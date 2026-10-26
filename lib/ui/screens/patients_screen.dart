import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_data.dart';
import '../../data/care_rules.dart';
import '../../data/models.dart';
import '../widgets.dart';
import 'patient_detail.dart';
import 'patient_form.dart';
import 'patient_picker.dart';

class PatientsScreen extends StatefulWidget {
  const PatientsScreen({super.key});

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  final _search = TextEditingController();
  String? _careLine;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _newPatient() async {
    final p = await Navigator.of(context).push<Patient>(
      MaterialPageRoute(builder: (_) => const PatientFormScreen()),
    );
    if (p != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PatientDetailScreen(patientId: p.id)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final q = _search.text;
    final list = data.patients
        .where((p) => (_careLine == null || p.careLineId == _careLine) && matchesPatient(p, q))
        .toList();
    final lastVisits = data.lastVisitByPatient();
    final pending = pendingByPatient(data);

    return AccentPage(
      accent: Accent.patients,
      title: 'Pacientes',
      headerBottom: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Buscar por nome, telefone, CPF ou CID',
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar busca',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  PillChip(
                    label: 'Todas',
                    selected: _careLine == null,
                    onTap: () => setState(() => _careLine = null),
                  ),
                  for (final c in data.careLines) ...[
                    const SizedBox(width: 8),
                    PillChip(
                      label: c.name,
                      dotColor: c.colorValue,
                      selected: _careLine == c.id,
                      onTap: () => setState(() => _careLine = _careLine == c.id ? null : c.id),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      fab: FloatingActionButton.extended(
        heroTag: 'fab-patients',
        onPressed: _newPatient,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Paciente', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: list.isEmpty
          ? ListView(
              children: [
                EmptyState(
                  icon: Icons.people_outline_rounded,
                  text: data.patients.isEmpty
                      ? 'Nenhum paciente cadastrado ainda.'
                      : 'Nenhum paciente encontrado.',
                  action: data.patients.isEmpty
                      ? FilledButton.icon(
                          onPressed: _newPatient,
                          icon: const Icon(Icons.person_add_alt_1_outlined),
                          label: const Text('Cadastrar paciente'),
                        )
                      : null,
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              itemCount: list.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Text(
                    plural(list.length, 'paciente', 'pacientes'),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted),
                  );
                }
                final p = list[i - 1];
                return PatientCard(
                  patient: p,
                  line: data.careLine(p.careLineId),
                  lastVisit: lastVisits[p.id],
                  pending: pending[p.id] ?? 0,
                );
              },
            ),
    );
  }
}

/// Lembretes dos próximos 30 dias (inclui atrasados) por paciente.
Map<String, int> pendingByPatient(AppData data) {
  final out = <String, int>{};
  for (final r in data.reminders) {
    if (r.daysLeft <= 30) out[r.patient.id] = (out[r.patient.id] ?? 0) + 1;
  }
  return out;
}

class PatientCard extends StatelessWidget {
  const PatientCard({
    super.key,
    required this.patient,
    required this.line,
    required this.lastVisit,
    required this.pending,
  });

  final Patient patient;
  final CareLine? line;
  final DateTime? lastVisit;
  final int pending;

  @override
  Widget build(BuildContext context) {
    return OutlinedCard(
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PatientDetailScreen(patientId: patient.id)),
      ),
      child: Row(
        children: [
          Avatar(name: patient.name, color: line?.colorValue ?? AppColors.salmonSoft),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    ageLabel(patient.birthDate),
                    if (line != null) line!.name,
                    if (patient.pregnant) 'Gestante ${gestationalAge(patient.dum!, today()).short}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.history_rounded, size: 14, color: AppColors.muted),
                    const SizedBox(width: 4),
                    Text(
                      lastVisit == null
                          ? 'Sem consultas realizadas'
                          : 'Última consulta: ${fmtDate(lastVisit)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (pending > 0)
            Tooltip(
              message: '$pending lembrete(s) nos próximos 30 dias',
              child: StatusBadge(
                text: '$pending',
                color: AppColors.purpleSoft,
                icon: Icons.notifications_active_outlined,
              ),
            ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
