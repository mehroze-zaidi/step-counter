import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../data/activity_snapshot.dart';
import '../data/live_steps.dart';
import '../data/step_repository.dart';
import '../sync/background_sync.dart';

enum HealthAccess { checking, unsupported, needsPermission, connected }

/// Decides *when* to sync and keeps the UI consistent. Reads and caching
/// live in [StepRepository]; background wakes in [BackgroundSync].
class StepController extends ChangeNotifier with WidgetsBindingObserver {
  StepController(this._repository, {LiveSteps? liveSteps, DateTime Function()? clock, bool? isIOS})
    : _live = liveSteps ?? LiveSteps(),
      _clock = clock ?? DateTime.now,
      _isIOS = isIOS ?? (!kIsWeb && Platform.isIOS);

  static const dailyGoal = 10000;

  /// Ignore resume-triggered syncs closer together than this; app switching
  /// can fire `resumed` many times a minute.
  static const _minAutoSyncInterval = Duration(seconds: 15);
  static const _syncTimeout = Duration(seconds: 30);

  final StepRepository _repository;
  final LiveSteps _live;
  final DateTime Function() _clock;
  final bool _isIOS;

  HealthAccess access = HealthAccess.checking;
  ActivitySnapshot snapshot = ActivitySnapshot.empty;
  bool syncing = false;

  /// Latest CoreMotion count (this iPhone, since midnight of [_liveDay]).
  int? _liveSteps;
  DateTime? _liveDay;

  /// CoreMotion count at the moment the current HealthKit numbers were read.
  /// Steps above it were taken after that read, so Health can't have them yet.
  int? _liveBaseline;

  StreamSubscription<ActivitySnapshot>? _updatesSub;
  Timer? _midnightTimer;
  bool _disposed = false;

  DateTime get now => _clock();
  DayActivity get today {
    final fromHealth = snapshot.today(now);
    final live = _liveSteps;
    // Ignore a count left over from yesterday's stream.
    final baseline = _liveBaseline;
    if (live == null || baseline == null || _liveDay != fromHealth.date) return fromHealth;
    // Health total + steps walked since it was read. Also never below the
    // phone's own count, in case Health is far behind (e.g. not synced yet).
    final sinceSync = math.max(0, live - baseline);
    return fromHealth.withLiveSteps(math.max(fromHealth.steps + sinceSync, live));
  }

  List<DayActivity> get week => [...snapshot.week(now).take(6), today];

  /// True while the live count is ahead of Apple Health.
  bool get isLive => today.steps > snapshot.today(now).steps;

  /// Synced successfully but every day is zero: on iOS this usually means
  /// read access was denied (HealthKit hides that and just returns nothing).
  bool get probablyDenied =>
      access == HealthAccess.connected && snapshot.status == SyncStatus.ok && !snapshot.hasAnyData;

  Future<void> init() async {
    if (!_isIOS) {
      _set(() => access = HealthAccess.unsupported);
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnightRollover();
    // Picks up syncs triggered by HealthKit background delivery while open.
    _updatesSub = _repository.updates.listen(_apply);

    // Paint cached numbers first so the screen is never blank, even while
    // the device is locked or Health is slow.
    final cached = await _repository.readCache();
    if (cached != null) _apply(cached);

    if (!await _repository.authorizationRequested) {
      _set(() => access = HealthAccess.needsPermission);
      return;
    }
    _set(() => access = HealthAccess.connected);
    // Re-arm on every launch: cheap, and repairs state after a reinstall.
    unawaited(BackgroundSync.enable());
    _startLive();
    await sync(reason: 'launch', force: true);
  }

  Future<void> connect() async {
    try {
      await _repository.requestAuthorization();
    } on Exception {
      // e.g. iPad without the Health app.
      _set(() => access = HealthAccess.unsupported);
      return;
    }
    _set(() => access = HealthAccess.connected);
    await BackgroundSync.enable();
    await sync(reason: 'authorized', force: true);
    // After the Health sheet, so the Motion prompt doesn't stack on top of it.
    _startLive();
  }

  /// Auto syncs are throttled; [force] is for launch, pull-to-refresh and
  /// day rollover. Overlapping calls are coalesced by the repository.
  Future<void> sync({required String reason, bool force = false}) async {
    if (access != HealthAccess.connected) return;
    final last = snapshot.lastAttemptAt;
    if (!force && last != null && now.difference(last) < _minAutoSyncInterval) return;

    _set(() => syncing = true);
    try {
      _apply(await _repository.sync(reason: reason).timeout(_syncTimeout));
    } on TimeoutException {
      _apply(snapshot.failed(SyncStatus.error, 'Apple Health took too long to respond.', now));
    } finally {
      _set(() => syncing = false);
    }
  }

  void _apply(ActivitySnapshot next) {
    // The stream and the awaited result can deliver the same sync, or an
    // older one, in either order — keep the newest.
    if (snapshot.lastAttemptAt != null && !snapshot.isOlderThan(next)) return;
    final freshHealthData = next.lastSyncedAt != snapshot.lastSyncedAt;
    _set(() {
      snapshot = next;
      // Health now includes everything up to here: restart the live delta.
      // (null if not streaming yet; the first live event sets it.)
      if (freshHealthData) _liveBaseline = _liveSteps;
    });
  }

  void _startLive() {
    if (access != HealthAccess.connected) return;
    final t = now;
    final dayStart = DateTime(t.year, t.month, t.day);
    if (_liveDay != dayStart) _liveSteps = _liveBaseline = null;
    _liveDay = dayStart;
    _live.start(dayStart, (steps) {
      _set(() {
        _liveSteps = steps;
        _liveBaseline ??= steps;
      });
    });
  }

  /// At local midnight "today" changes: repaint (cached data becomes
  /// yesterday's) and fetch the new day.
  void _scheduleMidnightRollover() {
    _midnightTimer?.cancel();
    final t = now;
    final nextMidnight = DateTime(t.year, t.month, t.day + 1);
    _midnightTimer = Timer(nextMidnight.difference(t) + const Duration(seconds: 1), () {
      _set(() {});
      _startLive(); // re-anchor the live count to the new day
      sync(reason: 'midnight', force: true);
      _scheduleMidnightRollover();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // CMPedometer doesn't deliver in the background; stop to save power.
      _live.stop();
      // Steps walked while closed show up in Health on the resume sync, so
      // start the live delta fresh rather than count them twice.
      _liveSteps = _liveBaseline = null;
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    // Its first event after restarting is the full count since midnight,
    // including steps taken while the app was closed.
    _startLive();
    // Timers don't fire while suspended, the day or time zone may have
    // changed, and a background isolate may have written a newer cache.
    _scheduleMidnightRollover();
    _set(() {});
    _repository.readCache().then((c) {
      if (c != null) _apply(c);
      sync(reason: 'resume');
    });
  }

  void _set(VoidCallback change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _updatesSub?.cancel();
    _live.stop();
    _midnightTimer?.cancel();
    super.dispose();
  }
}
