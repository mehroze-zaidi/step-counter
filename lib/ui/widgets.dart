import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/activity_snapshot.dart';

class StepRing extends StatelessWidget {
  const StepRing({super.key, required this.steps, required this.goal});

  final int steps;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final progress = goal == 0 ? 0.0 : steps / goal;

    return SizedBox.square(
      dimension: 220,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: progress.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => CustomPaint(
          painter: _RingPainter(value, scheme.primary, scheme.surfaceContainerHighest),
          child: child,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.directions_walk, color: scheme.primary),
              Text(
                _formatInt(steps),
                style: text.displaySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text('of ${_formatInt(goal)} steps', style: text.bodyMedium),
              if (progress >= 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Goal reached',
                    style: text.labelMedium?.copyWith(color: scheme.primary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color, this.track);

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, paint..color = track);
    if (progress > 0) {
      canvas.drawArc(arcRect, -math.pi / 2, 2 * math.pi * progress, false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final card = Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label, style: text.labelLarge, overflow: TextOverflow.ellipsis),
                ),
                if (tooltip != null) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.info_outline, size: 14),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: ' $unit', style: text.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return tooltip == null
        ? card
        : Tooltip(message: tooltip!, triggerMode: TooltipTriggerMode.tap, child: card);
  }
}

class WeekChart extends StatelessWidget {
  const WeekChart({super.key, required this.days, required this.goal});

  final List<DayActivity> days;
  final int goal;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final maxSteps = days.fold<int>(goal, (m, d) => math.max(m, d.steps));

    return SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, d) in days.indexed)
            Expanded(
              child: Tooltip(
                message: '${_formatInt(d.steps)} steps · ${d.calories.round()} kcal',
                triggerMode: TooltipTriggerMode.tap,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: maxSteps == 0 ? 0 : d.steps / maxSteps,
                          widthFactor: 0.55,
                          child: Container(
                            decoration: BoxDecoration(
                              color: d.steps >= goal
                                  ? scheme.primary
                                  : scheme.primary.withValues(
                                      alpha: i == days.length - 1 ? 0.7 : 0.35,
                                    ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _weekdays[d.date.weekday - 1],
                      style: text.labelMedium?.copyWith(
                        fontWeight: i == days.length - 1 ? FontWeight.w700 : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.icon, required this.text, this.isError = false});

  final IconData icon;
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: text.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, style: text.bodyMedium, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

String _formatInt(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
