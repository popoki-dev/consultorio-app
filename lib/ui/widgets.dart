import 'dart:math';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';

/// Página no estilo da referência: cabeçalho colorido com título em
/// maiúsculas e um painel creme de cantos arredondados por cima.
class AccentPage extends StatelessWidget {
  const AccentPage({
    super.key,
    required this.accent,
    required this.title,
    required this.body,
    this.headerBottom,
    this.leading,
    this.actions = const [],
    this.fab,
  });

  final Accent accent;
  final String title;
  final Widget body;
  final Widget? headerBottom;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? fab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: accent.strong,
      floatingActionButton: fab,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  SizedBox(width: 112, child: Align(alignment: Alignment.centerLeft, child: leading)),
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 112,
                    child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
                  ),
                ],
              ),
            ),
            if (headerBottom != null) headerBottom!,
            const SizedBox(height: 10),
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: -2,
                    right: -2,
                    top: 0,
                    bottom: -2,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.cream,
                        border: Border.all(color: AppColors.ink, width: 1.5),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: body,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botão redondo amarelo com contorno (como o "voltar" da referência).
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color = AppColors.yellow,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: color,
          shape: const CircleBorder(side: kBorder),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(width: 38, height: 38, child: Icon(icon, size: 20, color: AppColors.ink)),
          ),
        ),
      ),
    );
  }
}

class BackCircle extends StatelessWidget {
  const BackCircle({super.key});

  @override
  Widget build(BuildContext context) => CircleIconButton(
        icon: Icons.arrow_back_rounded,
        tooltip: 'Voltar',
        onPressed: () => Navigator.of(context).maybePop(),
      );
}

class OutlinedCard extends StatelessWidget {
  const OutlinedCard({
    super.key,
    required this.child,
    this.color = AppColors.surface,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.radius = kRadius,
  });

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: kBorder,
    );
    return Material(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Seletor de dia da semana no estilo da referência.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.selected,
    required this.onSelected,
    this.marked = const {},
  });

  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  /// Datas (dateKey) com consultas, mostradas com um ponto.
  final Set<String> marked;

  @override
  Widget build(BuildContext context) {
    final start = startOfWeek(selected);
    final now = today();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: List.generate(7, (i) {
          final day = addDays(start, i);
          final isSel = sameDay(day, selected);
          final isToday = sameDay(day, now);
          return Expanded(
            child: Semantics(
              button: true,
              selected: isSel,
              label: fmtDayLong(day),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(day),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    border: isSel ? Border.all(color: AppColors.ink, width: 1.5) : null,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    children: [
                      Text(
                        weekdayShort(day),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: isSel ? AppColors.ink : AppColors.ink.withAlpha(150),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSel ? AppColors.ink : Colors.transparent,
                          shape: BoxShape.circle,
                          border: isToday && !isSel
                              ? Border.all(color: AppColors.ink, width: 1.2)
                              : null,
                        ),
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isSel ? Colors.white : AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: marked.contains(dateKey(day)) ? AppColors.ink : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Cartão pequeno de indicador ("2h16m · Time" na referência).
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.unit,
    this.icon,
    this.iconColor = AppColors.yellowSoft,
    this.valueColor = AppColors.ink,
    this.onTap,
  });

  final String value;
  final String? unit;
  final String label;
  final IconData? icon;
  final Color iconColor;
  final Color valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
              child: icon == null ? null : Icon(icon, size: 14, color: AppColors.ink),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: value,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: valueColor),
                ),
                if (unit != null)
                  TextSpan(
                    text: unit,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: valueColor),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.2),
          ),
        ],
      ),
    );
  }
}

/// Barra de progresso em pílula com contorno.
class ProgressPill extends StatelessWidget {
  const ProgressPill({super.key, required this.value, required this.color, this.height = 22});

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(height),
        border: Border.all(color: AppColors.ink, width: 1.5),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v == 0 ? 0.001 : v,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(height),
              border: v == 0 ? null : Border.all(color: AppColors.ink, width: 1.2),
            ),
          ),
        ),
      ),
    );
  }
}

/// Alternador "DIÁRIO · SEMANAL · MENSAL" da referência.
class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.selectedColor = AppColors.surface,
  });

  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final (value, label) in options)
          Flexible(
            child: Semantics(
              button: true,
              selected: value == selected,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: value == selected ? selectedColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: value == selected ? AppColors.ink : Colors.transparent,
                      width: 1.4,
                    ),
                  ),
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: value == selected ? AppColors.ink : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dotColor,
    this.selectedColor = AppColors.ink,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dotColor;
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    final fg = selected && selectedColor == AppColors.ink ? Colors.white : AppColors.ink;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? selectedColor : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.ink, width: 1.3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dotColor != null) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.ink, width: 1),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.text, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ink, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: AppColors.ink), const SizedBox(width: 4)],
          Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, required this.color, this.size = 46});

  final String name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.ink, width: 1.5),
      ),
      child: Text(
        initials(name),
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.34),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.yellowSoft,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.ink, width: 1.5),
            ),
            child: Icon(icon, size: 28),
          ),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 15)),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          SizedBox(
            width: 104,
            child: Text(label, style: const TextStyle(color: AppColors.muted)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ gráficos

class BarDatum {
  const BarDatum(this.label, this.value, {this.display});
  final String label;
  final double value;
  final String? display;
}

/// Barras verticais em pílula, com o valor escrito na própria barra e linha
/// tracejada da média, como na referência. Barras acima da média ficam na cor
/// forte; as demais, na suave.
class PillBarChart extends StatelessWidget {
  const PillBarChart({
    super.key,
    required this.data,
    required this.strong,
    required this.soft,
    this.height = 170,
  });

  final List<BarDatum> data;
  final Color strong;
  final Color soft;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const EmptyState(icon: Icons.bar_chart_rounded, text: 'Sem dados no período');
    }
    final maxV = data.map((d) => d.value).fold<double>(0, max);
    final top = maxV <= 0 ? 1.0 : maxV;
    final avg = data.map((d) => d.value).reduce((a, b) => a + b) / data.length;
    double barH(double v) => v <= 0 ? 6.0 : max(34.0, (height - 8) * v / top);

    return Column(
      children: [
        SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final d in data)
                      Expanded(
                        child: Tooltip(
                          message: '${d.label}: ${d.display ?? _num(d.value)}',
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Container(
                              height: barH(d.value),
                              alignment: Alignment.topCenter,
                              padding: const EdgeInsets.only(top: 8, left: 2, right: 2),
                              decoration: BoxDecoration(
                                color: d.value >= avg && d.value > 0 ? strong : soft,
                                borderRadius: BorderRadius.circular(40),
                                border: Border.all(color: AppColors.ink, width: 1.3),
                              ),
                              child: d.value > 0
                                  ? FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        d.display ?? _num(d.value),
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (avg > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: barH(avg),
                  child: IgnorePointer(
                    child: SizedBox(height: 1, child: CustomPaint(painter: _DashPainter())),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final d in data)
              Expanded(
                child: Text(
                  d.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(width: 18, height: 1, child: CustomPaint(painter: _DashPainter())),
            const SizedBox(width: 6),
            Text('média ${_num(avg)}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ],
        ),
      ],
    );
  }
}

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.danger.withAlpha(170)
      ..strokeWidth = 1.2;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(min(x + 4, size.width), 0), paint);
      x += 8;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HBarItem {
  const HBarItem(this.label, this.value, {this.color, this.sublabel});
  final String label;
  final int value;
  final Color? color;
  final String? sublabel;
}

/// Barras horizontais rotuladas: categoria escrita, valor e percentual,
/// então a cor nunca é a única pista.
class HBarList extends StatelessWidget {
  const HBarList({super.key, required this.items, required this.color, this.showPercent = true});

  final List<HBarItem> items;
  final Color color;
  final bool showPercent;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty || items.every((i) => i.value == 0)) {
      return const EmptyState(icon: Icons.bar_chart_rounded, text: 'Sem dados para exibir');
    }
    final maxV = items.map((i) => i.value).reduce(max);
    final total = items.fold<int>(0, (s, i) => s + i.value);
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                    Text(
                      showPercent && total > 0
                          ? '${item.value} · ${(item.value * 100 / total).round()}%'
                          : '${item.value}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ],
                ),
                if (item.sublabel != null)
                  Text(item.sublabel!, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                const SizedBox(height: 4),
                ProgressPill(
                  value: maxV == 0 ? 0 : item.value / maxV,
                  color: item.color ?? color,
                  height: 18,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class DonutSlice {
  const DonutSlice(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
}

/// Gráfico de rosca com contorno escuro, como os cartões. Sempre usado com
/// [DonutLegend], que escreve rótulo, número e percentual de cada fatia.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    required this.centerValue,
    required this.centerLabel,
    this.size = 190,
  });

  final List<DonutSlice> slices;
  final String centerValue;
  final String centerLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (s, x) => s + x.value);
    return Semantics(
      label: '$centerValue $centerLabel. '
          '${slices.where((s) => s.value > 0).map((s) => '${s.label}: ${s.value}').join(', ')}',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _DonutPainter(slices, total),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(centerValue, style: TextStyle(fontSize: size * 0.16, fontWeight: FontWeight.w800)),
                  Text(centerLabel, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.total);
  final List<DonutSlice> slices;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2 - 1;
    final inner = outer * 0.58;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.ink;
    final visible = slices.where((s) => s.value > 0).toList();

    if (total == 0 || visible.length == 1) {
      final ring = Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: c, radius: outer))
        ..addOval(Rect.fromCircle(center: c, radius: inner));
      canvas.drawPath(ring, Paint()..color = total == 0 ? AppColors.hairline : visible.single.color);
      canvas.drawPath(ring, stroke);
      return;
    }

    const gap = 0.015;
    var start = -pi / 2;
    for (final s in visible) {
      final sweep = 2 * pi * s.value / total;
      final a0 = start + gap / 2;
      final a1 = max(a0 + 0.001, start + sweep - gap / 2);
      final path = Path()
        ..addArc(Rect.fromCircle(center: c, radius: outer), a0, a1 - a0)
        ..arcTo(Rect.fromCircle(center: c, radius: inner), a1, -(a1 - a0), false)
        ..close();
      canvas.drawPath(path, Paint()..color = s.color);
      canvas.drawPath(path, stroke);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}

/// Legenda da rosca: cor, rótulo, quantidade e percentual.
class DonutLegend extends StatelessWidget {
  const DonutLegend({super.key, required this.slices});
  final List<DonutSlice> slices;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (s, x) => s + x.value);
    return Column(
      children: [
        for (final s in slices.where((s) => s.value > 0))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: s.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.ink, width: 1.2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(s.label, style: const TextStyle(fontSize: 15))),
                Text(
                  '${s.value} · ${total == 0 ? 0 : (s.value * 100 / total).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Confirmar',
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: kBorder),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void showSnack(BuildContext context, String text, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), action: action));
}

/// Grava os dados de um formulário. Se der erro, avisa e retorna false: o
/// formulário continua aberto com o que foi digitado.
Future<bool> saveGuarded(BuildContext context, Future<void> Function() save) async {
  try {
    await save();
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, 'Não foi possível salvar: $e');
    return false;
  }
}

/// Campo que abre o seletor de data.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.allowClear = false,
    this.inputMode = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool allowClear;

  /// Abre já em modo digitação (mais rápido para data de nascimento).
  final bool inputMode;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final now = DateTime.now();
        final first = firstDate ?? DateTime(1900);
        final last = lastDate ?? DateTime(now.year + 10);
        var initial = value ?? now;
        if (initial.isAfter(last)) initial = last;
        if (initial.isBefore(first)) initial = first;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: first,
          lastDate: last,
          initialEntryMode: inputMode ? DatePickerEntryMode.input : DatePickerEntryMode.calendar,
          helpText: label,
        );
        if (picked != null) onChanged(dateOnly(picked));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: allowClear && value != null
              ? IconButton(
                  tooltip: 'Limpar',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => onChanged(null),
                )
              : const Icon(Icons.calendar_today_outlined, size: 20),
        ),
        child: Text(
          value == null ? 'Selecionar' : fmtDate(value),
          style: TextStyle(
            fontSize: 16,
            color: value == null ? AppColors.muted : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

/// Atalhos de prazo ("30 dias", "6 meses"...) que definem uma data.
class QuickDateChips extends StatelessWidget {
  const QuickDateChips({
    super.key,
    required this.from,
    required this.selected,
    required this.onChanged,
    this.options = const [(30, '30 dias'), (60, '60 dias'), (90, '90 dias'), (180, '6 meses'), (365, '1 ano')],
    this.noneLabel,
  });

  final DateTime from;
  final DateTime? selected;
  final ValueChanged<DateTime?> onChanged;
  final List<(int, String)> options;

  /// Se definido, mostra uma opção para "sem data".
  final String? noneLabel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (noneLabel != null)
          PillChip(
            label: noneLabel!,
            selected: selected == null,
            onTap: () => onChanged(null),
          ),
        for (final (days, label) in options)
          PillChip(
            label: label,
            selected: selected != null && sameDay(selected!, addDays(from, days)),
            onTap: () => onChanged(dateOnly(addDays(from, days))),
          ),
      ],
    );
  }
}
