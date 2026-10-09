import 'dart:async';
import 'dart:convert';

import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activity_snapshot.dart';

/// Reads steps/active energy from Apple Health and caches the result.
///
/// Used from three places, possibly at the same time: the UI isolate, the
/// HealthKit background-delivery handler (same isolate) and the workmanager
/// background isolate. `SharedPreferencesAsync` has no in-memory cache, so
/// every isolate always sees what the others last wrote.
class StepRepository {
  StepRepository({Health? health, SharedPreferencesAsync? prefs, DateTime Function()? clock})
    : _health = health ?? Health(),
      _prefs = prefs ?? SharedPreferencesAsync(),
      _clock = clock ?? DateTime.now;

  static const _cacheKey = 'activity_snapshot_v1';
  static const _authRequestedKey = 'health_auth_requested';

  /// Days re-read on every sync (including today). Re-reading a window rather
  /// than adding deltas picks up late Apple Watch uploads, samples the user
  /// deleted in the Health app, and edits to past days.
  static const windowDays = 7;
  static const types = [HealthDataType.STEPS, HealthDataType.ACTIVE_ENERGY_BURNED];

  final Health _health;
  final SharedPreferencesAsync _prefs;
  final DateTime Function() _clock;

  final _updates = StreamController<ActivitySnapshot>.broadcast();
  Future<void>? _configured;
  Future<ActivitySnapshot>? _inFlight;
  bool _rerunRequested = false;

  /// Every snapshot this repository writes, regardless of who triggered it.
  Stream<ActivitySnapshot> get updates => _updates.stream;

  Future<void> _ensureConfigured() => _configured ??= _health.configure();

  Future<ActivitySnapshot?> readCache() async {
    final raw = await _prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      return ActivitySnapshot.fromMap(jsonDecode(raw) as Map<String, Object?>);
    } on FormatException {
      return null; // corrupt cache: behave like a first launch
    }
  }

  /// HealthKit never reveals whether *read* access was granted, only whether
  /// the sheet was shown. So we remember that we asked.
  Future<bool> get authorizationRequested async => await _prefs.getBool(_authRequestedKey) ?? false;

  Future<void> requestAuthorization() async {
    await _ensureConfigured();
    await _health.requestAuthorization(
      types,
      permissions: [for (final _ in types) HealthDataAccess.READ],
    );
    await _prefs.setBool(_authRequestedKey, true);
  }

  /// Syncs and returns the newest snapshot.
  ///
  /// Calls that arrive while a sync is running (the steps and energy
  /// observers often fire together, plus app resume) join it, and trigger
  /// one follow-up pass so data that landed mid-sync isn't missed.
  Future<ActivitySnapshot> sync({required String reason}) {
    final running = _inFlight;
    if (running != null) {
      _rerunRequested = true;
      return running;
    }
    return _inFlight = _syncLoop().whenComplete(() => _inFlight = null);
  }

  Future<ActivitySnapshot> _syncLoop() async {
    ActivitySnapshot result;
    do {
      _rerunRequested = false;
      result = await _syncOnce();
    } while (_rerunRequested);
    return result;
  }

  Future<ActivitySnapshot> _syncOnce() async {
    final previous = await readCache() ?? ActivitySnapshot.empty;
    final now = _clock();

    ActivitySnapshot next;
    try {
      await _ensureConfigured();
      next = ActivitySnapshot(
        days: await _fetchWindow(now),
        status: SyncStatus.ok,
        lastSyncedAt: now,
        lastAttemptAt: now,
      );
    } on Exception catch (e) {
      // Never overwrite good numbers with zeros because a read failed.
      final (status, message) = _classify(e);
      next = previous.failed(status, message, now);
    }

    // Another isolate may have written a newer snapshot while we were
    // querying; don't clobber it with ours.
    final latest = await readCache();
    if (latest != null && !latest.isOlderThan(next)) {
      _updates.add(latest);
      return latest;
    }
    await _prefs.setString(_cacheKey, jsonEncode(next.toMap()));
    _updates.add(next);
    return next;
  }

  Future<List<DayActivity>> _fetchWindow(DateTime now) async {
    final today = DateTime(now.year, now.month, now.day);
    final days = <DayActivity>[];

    for (var i = windowDays - 1; i >= 0; i--) {
      // Local-calendar day bounds, recomputed every sync, so time zone
      // changes and DST days (23h / 25h) bucket correctly.
      final start = DateTime(today.year, today.month, today.day - i);
      final nextDay = DateTime(start.year, start.month, start.day + 1);
      final end = nextDay.isAfter(now) ? now : nextDay;

      // One statistics bucket spanning the whole day. HealthKit's statistics
      // queries de-duplicate overlapping sources (iPhone + Apple Watch
      // counting the same walk) by the user's source priority; summing raw
      // samples would double count.
      final points = await _health.getHealthIntervalDataFromTypes(
        startDate: start,
        endDate: end,
        types: types,
        interval: nextDay.difference(start).inSeconds,
      );

      double sumOf(HealthDataType type) => points
          .where((p) => p.type == type)
          .map((p) => (p.value as NumericHealthValue).numericValue.toDouble())
          .fold(0, (a, b) => a + b);

      days.add(
        DayActivity(
          date: start,
          steps: sumOf(HealthDataType.STEPS).round(),
          activeKcal: sumOf(HealthDataType.ACTIVE_ENERGY_BURNED),
        ),
      );
    }
    return days;
  }

  (SyncStatus, String) _classify(Exception e) {
    final text = e.toString().toLowerCase();
    // HKError.errorDatabaseInaccessible: the Health store is encrypted while
    // the device is locked — common during background wakes.
    if (text.contains('inaccessible') || text.contains('protected health data')) {
      return (SyncStatus.locked, 'Health data is protected while your iPhone is locked.');
    }
    if (text.contains('not available') || text.contains('unavailable')) {
      return (SyncStatus.unavailable, 'Apple Health is not available on this device.');
    }
    if (text.contains('authoriz')) {
      return (
        SyncStatus.notAuthorized,
        'Allow Steps and Active Energy in Settings › Health › Data Access & Devices.',
      );
    }
    return (SyncStatus.error, 'Could not read Apple Health. Pull to retry.');
  }
}
