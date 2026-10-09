/// Status of the most recent sync attempt, as reported by the native layer.
enum SyncStatus { ok, locked, notAuthorized, unavailable, error, unknown }

SyncStatus _parseStatus(Object? raw) => switch (raw) {
  'ok' => SyncStatus.ok,
  'locked' => SyncStatus.locked,
  'notAuthorized' => SyncStatus.notAuthorized,
  'unavailable' => SyncStatus.unavailable,
  'error' => SyncStatus.error,
  _ => SyncStatus.unknown,
};

/// Rough kcal-per-step for an average adult walking (~70 kg). Only used when
/// HealthKit has no Active Energy samples (e.g. iPhone without Apple Watch).
const double kcalPerStep = 0.04;

/// Average stride length in metres, for the distance estimate.
const double metresPerStep = 0.762;

class DayActivity {
  const DayActivity({
    required this.date,
    required this.steps,
    required this.activeKcal,
    this.liveExtraKcal = 0,
  });

  factory DayActivity.empty(DateTime date) => DayActivity(date: date, steps: 0, activeKcal: 0);

  factory DayActivity.fromMap(Map<Object?, Object?> map) => DayActivity(
    date: DateTime.parse(map['date'] as String),
    steps: (map['steps'] as num?)?.toInt() ?? 0,
    activeKcal: (map['activeKcal'] as num?)?.toDouble() ?? 0,
  );

  /// Local calendar day (time component is midnight).
  final DateTime date;
  final int steps;

  /// Active energy from HealthKit (kcal). 0 when no source records it.
  final double activeKcal;

  /// Estimated kcal for live steps HealthKit hasn't received yet.
  final double liveExtraKcal;

  Map<String, Object?> toMap() => {
    'date':
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
    'steps': steps,
    'activeKcal': activeKcal,
  };

  bool get caloriesEstimated => activeKcal <= 0 && steps > 0;

  double get calories => caloriesEstimated ? steps * kcalPerStep : activeKcal + liveExtraKcal;

  /// Merges a live CoreMotion count (this iPhone only, since midnight) into
  /// HealthKit's total. HealthKit lags while walking but also includes Apple
  /// Watch steps, so the larger number wins: live while you walk with the
  /// phone, HealthKit when the Watch counted steps the phone didn't see.
  DayActivity withLiveSteps(int liveSteps) {
    if (liveSteps <= steps) return this;
    return DayActivity(
      date: date,
      steps: liveSteps,
      activeKcal: activeKcal,
      // Only top up real Active Energy; with none, the whole value is
      // already estimated from steps.
      liveExtraKcal: activeKcal > 0 ? (liveSteps - steps) * kcalPerStep : 0,
    );
  }

  double get distanceKm => steps * metresPerStep / 1000;
}

class ActivitySnapshot {
  const ActivitySnapshot({
    required this.days,
    required this.status,
    this.lastSyncedAt,
    this.lastAttemptAt,
    this.message,
  });

  static const empty = ActivitySnapshot(days: [], status: SyncStatus.unknown);

  factory ActivitySnapshot.fromMap(Map<Object?, Object?> map) {
    final rawDays = (map['days'] as List<Object?>?) ?? const [];
    return ActivitySnapshot(
      days: [for (final d in rawDays) DayActivity.fromMap(d as Map<Object?, Object?>)]
        ..sort((a, b) => a.date.compareTo(b.date)),
      status: _parseStatus(map['status']),
      lastSyncedAt: _parseMillis(map['lastSyncedAt']),
      lastAttemptAt: _parseMillis(map['lastAttemptAt']),
      message: map['message'] as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'days': [for (final d in days) d.toMap()],
    'status': status.name,
    'lastSyncedAt': lastSyncedAt?.millisecondsSinceEpoch,
    'lastAttemptAt': lastAttemptAt?.millisecondsSinceEpoch,
    'message': message,
  };

  /// Keeps the previous numbers but records a failed attempt, so the UI can
  /// show "last known" data flagged as stale instead of zeros.
  ActivitySnapshot failed(SyncStatus status, String message, DateTime at) => ActivitySnapshot(
    days: days,
    status: status,
    lastSyncedAt: lastSyncedAt,
    lastAttemptAt: at,
    message: message,
  );

  final List<DayActivity> days;
  final SyncStatus status;

  /// When numbers were last successfully read from HealthKit.
  final DateTime? lastSyncedAt;

  /// When any sync (successful or not) last ran.
  final DateTime? lastAttemptAt;
  final String? message;

  bool get hasAnyData => days.any((d) => d.steps > 0 || d.activeKcal > 0);

  /// Today's totals. If the cache was written before midnight, its "today" is
  /// actually yesterday, so we return an empty day rather than show
  /// yesterday's steps under today's heading.
  DayActivity today(DateTime now) => dayFor(_dateOnly(now));

  /// The last 7 days ending today, padding gaps with zero days so the chart
  /// always has 7 bars even with a stale or partial cache.
  List<DayActivity> week(DateTime now) {
    final today = _dateOnly(now);
    return [for (var i = 6; i >= 0; i--) dayFor(DateTime(today.year, today.month, today.day - i))];
  }

  DayActivity dayFor(DateTime date) =>
      days.firstWhere((d) => d.date == date, orElse: () => DayActivity.empty(date));

  /// True if [other] is newer than this snapshot. Used to drop out-of-order
  /// updates (event channel push vs. method-call reply).
  bool isOlderThan(ActivitySnapshot other) {
    final mine = lastAttemptAt;
    final theirs = other.lastAttemptAt;
    if (mine == null) return true;
    if (theirs == null) return false;
    return mine.isBefore(theirs);
  }
}

DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

DateTime? _parseMillis(Object? raw) =>
    raw is num ? DateTime.fromMillisecondsSinceEpoch(raw.toInt()) : null;
