import 'package:flutter_test/flutter_test.dart';
import 'package:step_counter/data/activity_snapshot.dart';

void main() {
  final snapshot = ActivitySnapshot.fromMap({
    'days': [
      {'date': '2026-10-08', 'steps': 8000, 'activeKcal': 310.5},
      {'date': '2026-10-09', 'steps': 2500, 'activeKcal': 0},
    ],
    'status': 'ok',
    'lastSyncedAt': 1760000000000,
    'lastAttemptAt': 1760000000000,
  });

  test('round-trips through the cache format', () {
    final copy = ActivitySnapshot.fromMap(snapshot.toMap());
    expect(copy.days.map((d) => d.toMap()), snapshot.days.map((d) => d.toMap()));
    expect(copy.status, SyncStatus.ok);
    expect(copy.lastSyncedAt, snapshot.lastSyncedAt);
  });

  test('estimates calories only when Active Energy is missing', () {
    final yesterday = snapshot.dayFor(DateTime(2026, 10, 8));
    final today = snapshot.dayFor(DateTime(2026, 10, 9));
    expect(yesterday.caloriesEstimated, isFalse);
    expect(yesterday.calories, 310.5);
    expect(today.caloriesEstimated, isTrue);
    expect(today.calories, 2500 * kcalPerStep);
  });

  test('a cache written before midnight does not leak into the new day', () {
    final today = snapshot.today(DateTime(2026, 10, 10, 0, 5));
    expect(today.steps, 0);
    expect(today.date, DateTime(2026, 10, 10));
  });

  test('week is always 7 days ending today, gaps padded with zeros', () {
    final week = snapshot.week(DateTime(2026, 10, 9, 15));
    expect(week, hasLength(7));
    expect(week.first.date, DateTime(2026, 10, 3));
    expect(week.last.steps, 2500);
    expect(week[0].steps, 0);
  });

  test('a failed sync keeps the last numbers and marks the status', () {
    final failed = snapshot.failed(SyncStatus.locked, 'locked', DateTime(2026, 10, 9, 16));
    expect(failed.days, snapshot.days);
    expect(failed.lastSyncedAt, snapshot.lastSyncedAt);
    expect(failed.status, SyncStatus.locked);
    expect(snapshot.isOlderThan(failed), isTrue);
  });

  test('live count wins only when ahead of HealthKit', () {
    final day = DayActivity(date: _d, steps: 5000, activeKcal: 200);
    expect(day.withLiveSteps(4000).steps, 5000); // Watch steps HK has, phone missed
    final live = day.withLiveSteps(5500);
    expect(live.steps, 5500);
    expect(live.calories, 200 + 500 * kcalPerStep);
    expect(live.caloriesEstimated, isFalse);

    final noEnergy = DayActivity(date: _d, steps: 1000, activeKcal: 0);
    expect(noEnergy.withLiveSteps(1500).calories, 1500 * kcalPerStep);
  });
}

final _d = DateTime(2026, 10, 9);
