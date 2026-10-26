import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_data.dart';
import '../../data/models.dart';
import '../widgets.dart';
import 'patients_screen.dart';

/// Lista de pacientes de um resultado do painel ("Ver pacientes").
class PatientListScreen extends StatelessWidget {
  const PatientListScreen({
    super.key,
    required this.title,
    required this.patientIds,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<String> patientIds;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final list = patientIds.map(data.patient).whereType<Patient>().toList();
    final lastVisits = data.lastVisitByPatient();
    final pending = pendingByPatient(data);

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 64,
        leading: const BackCircle(),
        title: Text(title.toUpperCase()),
      ),
      body: list.isEmpty
          ? const EmptyState(icon: Icons.people_outline_rounded, text: 'Nenhum paciente.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: list.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Text(
                    [plural(list.length, 'paciente', 'pacientes'), if (subtitle != null) subtitle!].join(' · '),
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
