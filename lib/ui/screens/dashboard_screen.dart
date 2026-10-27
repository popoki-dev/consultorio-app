import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cid10.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_data.dart';
import '../../data/care_rules.dart';
import '../../data/models.dart';
import '../widgets.dart';
import 'patient_list_screen.dart';

enum _Period { weekly, monthly }

enum _Group {
  all('Todos'),
  pregnant('Gestantes'),
  infants('Crianças < 2 anos');

  const _Group(this.label);
  final String label;
}

enum _Composition { line, sex, age }

/// Painel epidemiológico: pesquisa de pacientes por grupo, linha de cuidado,
/// idade, sexo e CID-10, com a composição e os indicadores do grupo
/// encontrado. Tudo é calculado no aparelho, então funciona offline.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _maxAge = 100.0;
  static const _fullAges = RangeValues(0, _maxAge);

  /// Atalhos de faixa etária: (rótulo, de, até).
  static const _ageShortcuts = [
    ('< 2 anos', 0.0, 1.0),
    ('2–11', 2.0, 11.0),
    ('12–17', 12.0, 17.0),
    ('18–39', 18.0, 39.0),
    ('40–59', 40.0, 59.0),
    ('60+', 60.0, _maxAge),
  ];

  /// Faixas da composição por idade.
  static const _ageBands = [
    ('< 2 anos', 0, 1),
    ('2–11 anos', 2, 11),
    ('12–17 anos', 12, 17),
    ('18–29 anos', 18, 29),
    ('30–44 anos', 30, 44),
    ('45–59 anos', 45, 59),
    ('60–74 anos', 60, 74),
    ('75+ anos', 75, 999),
  ];

  static const _sliceColors = [
    Color(0xFFF6C453),
    Color(0xFF8DB8E3),
    Color(0xFF8FC9A3),
    Color(0xFFF2A394),
    Color(0xFFB9A2DE),
    Color(0xFFE79BC0),
    Color(0xFF9FD3D0),
    Color(0xFFD3B58F),
  ];

  _Group _group = _Group.all;
  String? _line;
  RangeValues _ages = _fullAges;
  String? _sex;
  final _cid = TextEditingController();
  _Composition _composition = _Composition.line;
  _Period _period = _Period.monthly;

  @override
  void dispose() {
    _cid.dispose();
    super.dispose();
  }

  bool get _agesFiltered => _ages != _fullAges;

  bool get _filtered =>
      _group != _Group.all || _line != null || _agesFiltered || _sex != null || _cid.text.trim().isNotEmpty;

  void _clear() => setState(() {
        _group = _Group.all;
        _line = null;
        _ages = _fullAges;
        _sex = null;
        _cid.clear();
      });

  String get _ageText {
    if (!_agesFiltered) return 'Todas as idades';
    final lo = _ages.start.round();
    final hi = _ages.end.round();
    if (hi >= _maxAge) return '$lo anos ou mais';
    if (lo == hi) return lo == 1 ? '1 ano' : '$lo anos';
    return 'De $lo a $hi anos';
  }

  bool _matches(Patient p, DateTime now) {
    switch (_group) {
      case _Group.pregnant:
        if (!p.pregnant) return false;
      case _Group.infants:
        if (!isInfant(p, now)) return false;
      case _Group.all:
        break;
    }
    if (_line != null && !p.careLineIds.contains(_line)) return false;
    if (_sex != null && p.sex != _sex) return false;
    if (_agesFiltered) {
      final age = p.age;
      if (age == null) return false;
      if (age < _ages.start.round()) return false;
      if (_ages.end < _maxAge && age > _ages.end.round()) return false;
    }
    final q = _cid.text.trim();
    if (q.isNotEmpty) {
      final code = q.toUpperCase().replaceAll('.', '');
      final text = normalize(q);
      bool hit(String c) {
        if (c.startsWith(code)) return true;
        final desc = cid10Common[c] ?? (c.length > 3 ? cid10Common[c.substring(0, 3)] : null);
        return desc != null && normalize(desc).contains(text);
      }

      if (!p.cidCodes.any(hit)) return false;
    }
    return true;
  }

  String _criteria(AppData data) => [
        if (_group != _Group.all) _group.label,
        if (_line != null) data.careLine(_line)?.name ?? '',
        if (_agesFiltered) _ageText,
        if (_sex != null) Sex.label(_sex),
        if (_cid.text.trim().isNotEmpty) 'CID "${_cid.text.trim()}"',
      ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final now = today();
    final all = data.patients;
    final patients = all.where((p) => _matches(p, now)).toList();
    final ids = patients.map((p) => p.id).toSet();
    final appts = data.appointments.where((a) => ids.contains(a.patientId)).toList();
    final reminders = data.reminders.where((r) => ids.contains(r.patient.id)).toList();

    final line = data.careLine(_line);
    final strong = line?.colorValue ?? AppColors.blue;
    final soft = Color.alphaBlend(strong.withAlpha(90), AppColors.surface);

    final ages = patients.map((p) => p.age).whereType<int>().toList();
    final avgAge = ages.isEmpty ? null : ages.reduce((a, b) => a + b) / ages.length;
    final pregnant = patients.where((p) => p.pregnant).length;
    final infants = patients.where((p) => isInfant(p, now)).length;
    final last30 = appts
        .where((a) => a.status == ApptStatus.done && !a.startAt.isBefore(addDays(now, -30)))
        .length;
    final recent = appts.where((a) =>
        !a.startAt.isBefore(addDays(now, -90)) &&
        a.startAt.isBefore(addDays(now, 1)) &&
        (a.status == ApptStatus.done || a.status == ApptStatus.missed));
    final missedRate = recent.isEmpty
        ? null
        : recent.where((a) => a.status == ApptStatus.missed).length * 100 / recent.length;

    return AccentPage(
      accent: Accent.dashboard,
      title: 'Painel',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
        children: [
          _filterCard(data),
          const SizedBox(height: 14),
          _resultCard(data, patients, all.length),
          const SectionTitle('Indicadores do grupo'),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: avgAge == null ? '—' : avgAge.round().toString(),
                  unit: avgAge == null ? null : ' anos',
                  label: 'Idade média',
                  icon: Icons.cake_outlined,
                  iconColor: soft,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: '$pregnant',
                  label: 'Gestantes',
                  icon: Icons.pregnant_woman_rounded,
                  iconColor: soft,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: '$infants',
                  label: 'Crianças < 2 anos',
                  icon: Icons.child_care_rounded,
                  iconColor: soft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '$last30',
                  label: 'Consultas realizadas\n(últimos 30 dias)',
                  icon: Icons.event_available_outlined,
                  iconColor: soft,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: missedRate == null ? '—' : missedRate.round().toString(),
                  unit: missedRate == null ? null : '%',
                  label: 'Taxa de faltas\n(últimos 90 dias)',
                  icon: Icons.person_off_outlined,
                  iconColor: soft,
                ),
              ),
            ],
          ),
          _ChartCard(
            title: 'Consultas realizadas',
            child: Column(
              children: [
                SegmentedPills<_Period>(
                  options: const [(_Period.weekly, 'Semanal'), (_Period.monthly, 'Mensal')],
                  selected: _period,
                  selectedColor: soft,
                  onChanged: (p) => setState(() => _period = p),
                ),
                const SizedBox(height: 14),
                PillBarChart(data: _visitsSeries(appts, now), strong: strong, soft: soft),
              ],
            ),
          ),
          _ChartCard(
            title: 'Diagnósticos mais frequentes (CID-10)',
            child: HBarList(color: strong, showPercent: false, items: _topCids(patients)),
          ),
          _ChartCard(
            title: 'Pendências',
            child: HBarList(
              color: AppColors.purple,
              showPercent: false,
              items: [
                HBarItem(
                  'Retornos atrasados',
                  reminders.where((r) => r.kind == ReminderKind.returnVisit && r.overdue).length,
                ),
                HBarItem(
                  'Receitas vencidas',
                  reminders.where((r) => r.kind == ReminderKind.prescription && r.overdue).length,
                ),
                HBarItem(
                  'Receitas vencendo em 30 dias',
                  reminders
                      .where((r) => r.kind == ReminderKind.prescription && !r.overdue && r.daysLeft <= 30)
                      .length,
                ),
                HBarItem(
                  'Exames a repetir (atrasados)',
                  reminders.where((r) => r.kind == ReminderKind.exam && r.overdue).length,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- pesquisa

  Widget _filterCard(AppData data) {
    return OutlinedCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.manage_search_rounded),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Pesquisar pacientes', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ),
              if (_filtered) TextButton(onPressed: _clear, child: const Text('Limpar')),
            ],
          ),
          const _FilterLabel('Grupo'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in _Group.values)
                PillChip(label: g.label, selected: _group == g, onTap: () => setState(() => _group = g)),
            ],
          ),
          const _FilterLabel('Linha de cuidado'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PillChip(label: 'Todas', selected: _line == null, onTap: () => setState(() => _line = null)),
              for (final c in data.careLines)
                PillChip(
                  label: c.name,
                  dotColor: c.colorValue,
                  selected: _line == c.id,
                  onTap: () => setState(() => _line = _line == c.id ? null : c.id),
                ),
            ],
          ),
          const _FilterLabel('Faixa etária'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PillChip(label: 'Todas', selected: !_agesFiltered, onTap: () => setState(() => _ages = _fullAges)),
              for (final (label, lo, hi) in _ageShortcuts)
                PillChip(
                  label: label,
                  selected: _ages.start == lo && _ages.end == hi,
                  onTap: () => setState(() {
                    final r = RangeValues(lo, hi);
                    _ages = _ages == r ? _fullAges : r;
                  }),
                ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.ink,
              inactiveTrackColor: AppColors.hairline,
              thumbColor: AppColors.ink,
              overlayColor: AppColors.ink.withAlpha(30),
              valueIndicatorColor: AppColors.ink,
            ),
            child: RangeSlider(
              min: 0,
              max: _maxAge,
              divisions: _maxAge.toInt(),
              values: _ages,
              labels: RangeLabels(
                '${_ages.start.round()}',
                _ages.end >= _maxAge ? '${_maxAge.toInt()}+' : '${_ages.end.round()}',
              ),
              onChanged: (v) => setState(() => _ages = v),
            ),
          ),
          Center(child: Text(_ageText, style: const TextStyle(color: AppColors.muted))),
          const _FilterLabel('Sexo'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PillChip(label: 'Todos', selected: _sex == null, onTap: () => setState(() => _sex = null)),
              for (final s in const [Sex.female, Sex.male])
                PillChip(
                  label: Sex.label(s),
                  selected: _sex == s,
                  onTap: () => setState(() => _sex = _sex == s ? null : s),
                ),
            ],
          ),
          const _FilterLabel('Diagnóstico (CID-10)'),
          TextField(
            controller: _cid,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.medical_information_outlined),
              hintText: 'Ex.: E11 ou diabetes',
              suffixIcon: _cid.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(_cid.clear),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- resultado

  Widget _resultCard(AppData data, List<Patient> patients, int total) {
    final n = patients.length;
    final pct = total == 0 ? 0 : (n * 100 / total).round();
    final criteria = _criteria(data);
    final slices = _composition == _Composition.line ? const <DonutSlice>[] : _compositionSlices(data, patients);

    return OutlinedCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _filtered ? 'Resultado da pesquisa' : 'Todos os pacientes',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          if (criteria.isNotEmpty)
            Text(criteria, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('$n', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, height: 1)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _filtered
                      ? '${n == 1 ? 'paciente' : 'pacientes'}\nde $total cadastrados ($pct%)'
                      : (n == 1 ? 'paciente\ncadastrado' : 'pacientes\ncadastrados'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ],
          ),
          if (_filtered && total > 0) ...[
            const SizedBox(height: 14),
            Center(
              child: DonutChart(
                slices: [
                  DonutSlice('Atendem aos critérios', n, AppColors.blue),
                  DonutSlice('Demais pacientes', total - n, AppColors.hairline),
                ],
                centerValue: '$pct%',
                centerLabel: 'do total',
              ),
            ),
            const SizedBox(height: 10),
            DonutLegend(
              slices: [
                DonutSlice('Atendem aos critérios', n, AppColors.blue),
                DonutSlice('Demais pacientes', total - n, AppColors.hairline),
              ],
            ),
          ],
          if (n == 0)
            const EmptyState(icon: Icons.search_off_rounded, text: 'Nenhum paciente atende aos critérios.')
          else ...[
            const SizedBox(height: 16),
            const Text('Composição do grupo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            SegmentedPills<_Composition>(
              options: const [
                (_Composition.line, 'Linha'),
                (_Composition.sex, 'Sexo'),
                (_Composition.age, 'Idade'),
              ],
              selected: _composition,
              selectedColor: AppColors.blueSoft,
              onChanged: (c) => setState(() => _composition = c),
            ),
            const SizedBox(height: 14),
            if (_composition == _Composition.line) ...[
              HBarList(color: AppColors.blue, percentOf: n, items: _lineBars(data, patients)),
              const SizedBox(height: 4),
              const Text(
                'Um paciente pode estar em mais de uma linha: os percentuais são sobre o total '
                'do grupo e podem somar mais de 100%.',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ] else ...[
              Center(
                child: DonutChart(
                  slices: slices,
                  centerValue: '$n',
                  centerLabel: n == 1 ? 'paciente' : 'pacientes',
                ),
              ),
              const SizedBox(height: 10),
              DonutLegend(slices: slices),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.list_alt_rounded),
              label: Text('Ver pacientes ($n)'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PatientListScreen(
                    title: _filtered ? 'Resultado' : 'Pacientes',
                    subtitle: criteria.isEmpty ? null : criteria,
                    patientIds: patients.map((p) => p.id).toList(),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Pacientes por linha de cuidado (um paciente conta em cada linha dele).
  List<HBarItem> _lineBars(AppData data, List<Patient> patients) {
    final bars = [
      for (final c in data.careLines)
        HBarItem(c.name, patients.where((p) => p.careLineIds.contains(c.id)).length, color: c.colorValue),
    ]
      ..removeWhere((b) => b.value == 0)
      ..sort((a, b) => b.value.compareTo(a.value));
    final multi = patients.where((p) => data.careLinesOf(p).length > 1).length;
    final none = patients.where((p) => data.careLinesOf(p).isEmpty).length;
    return [
      ...bars,
      if (none > 0) HBarItem('Sem linha de cuidado', none, color: AppColors.hairline),
      if (multi > 0) HBarItem('Em mais de uma linha', multi, color: AppColors.blueSoft),
    ];
  }

  List<DonutSlice> _compositionSlices(AppData data, List<Patient> patients) {
    switch (_composition) {
      case _Composition.line:
        return const [];
      case _Composition.sex:
        return [
          DonutSlice('Feminino', patients.where((p) => p.sex == Sex.female).length, const Color(0xFFE79BC0)),
          DonutSlice('Masculino', patients.where((p) => p.sex == Sex.male).length, const Color(0xFF8DB8E3)),
          DonutSlice('Outro', patients.where((p) => p.sex == Sex.other).length, const Color(0xFFB9A2DE)),
          DonutSlice('Não informado', patients.where((p) => p.sex == null).length, AppColors.hairline),
        ];
      case _Composition.age:
        final out = <DonutSlice>[];
        var color = 0;
        for (final (label, lo, hi) in _ageBands) {
          final n = patients.where((p) => p.age != null && p.age! >= lo && p.age! <= hi).length;
          if (n == 0) continue;
          out.add(DonutSlice(label, n, _sliceColors[color++ % _sliceColors.length]));
        }
        out.add(DonutSlice(
          'Sem data de nascimento',
          patients.where((p) => p.age == null).length,
          AppColors.hairline,
        ));
        return out;
    }
  }

  // ---------------------------------------------------------------- gráficos

  List<BarDatum> _visitsSeries(List<Appointment> appts, DateTime now) {
    final done = appts.where((a) => a.status == ApptStatus.done).toList();
    if (_period == _Period.weekly) {
      final thisWeek = startOfWeek(now);
      return [
        for (var i = 7; i >= 0; i--)
          () {
            final start = addDays(thisWeek, -7 * i);
            final end = addDays(start, 7);
            final n = done.where((a) => !a.startAt.isBefore(start) && a.startAt.isBefore(end)).length;
            return BarDatum(fmtDateShort(start), n.toDouble());
          }(),
      ];
    }
    return [
      for (var i = 5; i >= 0; i--)
        () {
          final start = DateTime(now.year, now.month - i, 1);
          final end = DateTime(start.year, start.month + 1, 1);
          final n = done.where((a) => !a.startAt.isBefore(start) && a.startAt.isBefore(end)).length;
          return BarDatum(monthShort(start), n.toDouble());
        }(),
    ];
  }

  List<HBarItem> _topCids(List<Patient> patients) {
    final counts = <String, int>{};
    for (final p in patients) {
      for (final c in p.cidCodes) {
        counts[c] = (counts[c] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in sorted.take(8))
        HBarItem(
          e.key,
          e.value,
          sublabel: cid10Common[e.key] ?? cid10Common[e.key.length > 3 ? e.key.substring(0, 3) : e.key],
        ),
    ];
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      );
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: OutlinedCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
