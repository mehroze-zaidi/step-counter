import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/activity_snapshot.dart';
import '../dev/seed_health_data.dart';
import '../state/step_controller.dart';
import 'widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final StepController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Today'),
          actions: [
            if (kDebugMode && controller.access == HealthAccess.connected)
              IconButton(
                tooltip: 'Seed sample Health data (debug)',
                icon: const Icon(Icons.science_outlined),
                onPressed: seedHealthData,
              ),
            if (controller.access == HealthAccess.connected)
              controller.syncing
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Sync now',
                      icon: const Icon(Icons.sync),
                      onPressed: () => controller.sync(reason: 'manual', force: true),
                    ),
          ],
        ),
        body: switch (controller.access) {
          HealthAccess.checking => const Center(child: CircularProgressIndicator()),
          HealthAccess.unsupported => const MessageView(
            icon: Icons.phone_iphone,
            title: 'iPhone only',
            body: 'Step data comes from Apple Health, which is only available on iPhone.',
          ),
          HealthAccess.needsPermission => MessageView(
            icon: Icons.favorite,
            title: 'Connect Apple Health',
            body:
                'Step Counter reads your steps and active energy to show your daily '
                'progress. Nothing is written or shared.',
            action: FilledButton(onPressed: controller.connect, child: const Text('Connect')),
          ),
          HealthAccess.connected => _Dashboard(controller: controller),
        },
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.controller});

  final StepController controller;

  @override
  Widget build(BuildContext context) {
    final today = controller.today;
    final snapshot = controller.snapshot;

    return RefreshIndicator(
      onRefresh: () => controller.sync(reason: 'pull', force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_banner(snapshot) case final banner?) ...[banner, const SizedBox(height: 16)],
          Center(
            child: StepRing(steps: today.steps, goal: StepController.dailyGoal),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: StatCard(
                  icon: Icons.local_fire_department,
                  label: today.caloriesEstimated ? 'Calories (est.)' : 'Active calories',
                  value: today.calories.round().toString(),
                  unit: 'kcal',
                  tooltip: today.caloriesEstimated
                      ? 'No Active Energy in Apple Health (e.g. no Apple Watch), '
                            'so this is estimated from steps.'
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  icon: Icons.straighten,
                  label: 'Distance (est.)',
                  value: today.distanceKm.toStringAsFixed(2),
                  unit: 'km',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Last 7 days', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          WeekChart(days: controller.week, goal: StepController.dailyGoal),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '${controller.isLive ? 'Live · ' : ''}${_syncLabel(snapshot, controller.now)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget? _banner(ActivitySnapshot s) {
    if (s.status case SyncStatus.ok || SyncStatus.unknown) {
      if (controller.probablyDenied) {
        return const StatusBanner(
          icon: Icons.info_outline,
          text:
              'No data yet. If you turned off access, enable Steps and Active Energy in '
              'Settings › Health › Data Access & Devices › Step Counter.',
        );
      }
      return null;
    }
    return StatusBanner(
      icon: s.status == SyncStatus.locked ? Icons.lock_outline : Icons.warning_amber,
      text:
          '${s.message ?? 'Sync failed.'}'
          '${s.days.isEmpty ? '' : ' Showing last synced data.'}',
      isError: s.status == SyncStatus.error,
    );
  }

  String _syncLabel(ActivitySnapshot s, DateTime now) {
    final at = s.lastSyncedAt;
    if (at == null) return 'Not synced yet';
    final ago = now.difference(at);
    final text = switch (ago) {
      _ when ago.inMinutes < 1 => 'just now',
      _ when ago.inHours < 1 => '${ago.inMinutes} min ago',
      _ when ago.inDays < 1 => '${ago.inHours} h ago',
      _ => '${ago.inDays} d ago',
    };
    return 'Synced with Apple Health $text';
  }
}
