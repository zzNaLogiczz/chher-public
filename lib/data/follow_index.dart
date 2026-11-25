import 'dart:convert';
import 'dart:io';

import '../core/app_paths.dart';
import '../core/display_time.dart';
import '../models/models.dart';
import 'account_local_index.dart';
import 'user_block_index.dart';

final FollowIndex followIndex = FollowIndex(
  directory: () => AppPaths.instance.subdir('follows'),
);

class FollowedUser {
  final String uid;
  final String name;
  final String? avatar;
  final DateTime at;
  final int? lastTid;
  final DateTime? lastCheck;
  final int unseen;
  final Object _generation;

  FollowedUser({
    required this.uid,
    required this.name,
    this.avatar,
    required this.at,
    this.lastTid,
    this.lastCheck,
    this.unseen = 0,
  }) : _generation = Object();

  FollowedUser._activity(
    this.uid,
    this.name,
    this.avatar,
    this.at,
    this.lastTid,
    this.lastCheck,
    this.unseen,
    this._generation,
  );

  FollowedUser _withActivity({
    int? lastTid,
    DateTime? lastCheck,
    int? unseen,
  }) => FollowedUser._activity(
    uid,
    name,
    avatar,
    at,
    lastTid ?? this.lastTid,
    lastCheck ?? this.lastCheck,
    unseen ?? this.unseen,
    _generation,
  );
}

class FollowActivity {
  final ThreadSummary thread;
  final DateTime at;
  final bool unseen;

  const FollowActivity(this.thread, this.at, {required this.unseen});
}

class FollowIndexState extends AccountIndexState {
  FollowIndexState(super.file);

  final entries = <String, FollowedUser>{};
  final activities = <int, FollowActivity>{};
  bool hasEverFollowed = false;
}

/// Local follows and new-thread counts for the selected account.
class FollowIndex extends AccountLocalIndex<FollowIndexState> {
  static const checkInterval = Duration(minutes: 30);
  static const betweenChecks = Duration(seconds: 1);
  static const maxChecksPerRound = 20;
  static const _maxActivities = 200;

  FollowIndex({super.directory}) : super(filename: 'follows-v1.json');

  FollowIndex.forTesting(File? file)
    : super(filename: 'follows-v1.json', fixture: FollowIndexState(file));

  @override
  FollowIndexState createState(File? file) => FollowIndexState(file);

  @override
  String get readError => '关注列表读取失败，请稍后重试';

  @override
  String get writeError => '关注列表未保存，请稍后重试';

  bool isFollowed(String? uid) =>
      activeState?.entries.containsKey(UserBlockIndex.normalizeUid(uid)) ??
      false;

  List<FollowedUser> get all => List.unmodifiable(
    (activeState?.entries.values.toList() ?? [])
      ..sort((a, b) => b.at.compareTo(a.at)),
  );

  int get unseenCount => _unseenCount(activeState);
  int _unseenCount(FollowIndexState? state) =>
      state?.entries.values.fold<int>(0, (sum, e) => sum + e.unseen) ?? 0;
  bool get hasEverFollowed => activeState?.hasEverFollowed ?? false;

  List<FollowActivity> get activities =>
      List.unmodifiable(_sortedActivities(activeState));

  List<FollowActivity> _sortedActivities(FollowIndexState? state) =>
      (state?.activities.values.toList() ?? [])..sort(_newestFirst);

  static int _newestFirst(FollowActivity a, FollowActivity b) =>
      b.thread.tid.compareTo(a.thread.tid);

  @override
  Future<void> readFrom(FollowIndexState state, File file) async {
    final data = jsonDecode(await file.readAsString());
    if (data is! Map || data['version'] != 1 || data['users'] is! List) {
      throw const FormatException('Invalid follows index');
    }
    for (final value in data['users'] as List) {
      if (value is! Map) continue;
      final uid = UserBlockIndex.normalizeUid(value['uid']?.toString());
      if (uid == null) continue;
      final lastTid = value['lastTid'];
      final unseen = value['unseen'];
      state.entries.putIfAbsent(
        uid,
        () => FollowedUser(
          uid: uid,
          name: value['name'] is String ? value['name'] : 'UID $uid',
          avatar: value['avatar'] is String ? value['avatar'] : null,
          at: _readTime(value['at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
          lastTid: lastTid is int && lastTid > 0 ? lastTid : null,
          lastCheck: _readTime(value['lastCheck']),
          unseen: unseen is int && unseen > 0 ? unseen : 0,
        ),
      );
    }
    state.hasEverFollowed |=
        data['hasEverFollowed'] == true || (data['users'] as List).isNotEmpty;
    final storedActivities = data['activities'];
    if (storedActivities is List) {
      for (final value in storedActivities) {
        if (value is Map) _readActivity(state, value);
      }
      _trimActivities(state);
    }
  }

  static DateTime? _readTime(Object? value) =>
      value is int && value >= -8640000000000000 && value <= 8640000000000000
      ? DateTime.fromMillisecondsSinceEpoch(value)
      : null;

  void _readActivity(FollowIndexState state, Map value) {
    final uid = UserBlockIndex.normalizeUid(value['uid']?.toString());
    final tid = value['tid'];
    final fid = value['fid'];
    final title = value['title'];
    final at = _readTime(value['at']);
    final user = state.entries[uid];
    if (user == null ||
        tid is! int ||
        tid <= 0 ||
        fid is! int ||
        fid <= 0 ||
        title is! String ||
        title.isEmpty ||
        at == null) {
      return;
    }
    state.activities.putIfAbsent(
      tid,
      () => FollowActivity(
        ThreadSummary(
          tid: tid,
          author: user.name,
          authorUid: uid,
          title: title,
          forumFid: fid,
          forumName: value['forum'] is String ? value['forum'] : null,
          createdAt: _readTime(value['createdAt']),
          replies: value['replies'] is int ? value['replies'] : null,
          views: 0,
        ),
        at,
        unseen: value['unseen'] == true && user.unseen > 0,
      ),
    );
  }

  Future<bool> follow({
    required String uid,
    required String name,
    String? avatar,
    DateTime? at,
    int? lastTid,
  }) async {
    final id = UserBlockIndex.normalizeUid(uid);
    if (id == null) return false;
    final started = epoch;
    await load();
    final state = activeState;
    if (started != epoch || state == null) return false;
    if (state.entries.containsKey(id)) return flush();
    state.hasEverFollowed = true;
    state.entries[id] = FollowedUser(
      uid: id,
      name: name.trim().isEmpty ? 'UID $id' : name.trim(),
      avatar: avatar,
      at: at ?? DateTime.now(),
      lastTid: lastTid != null && lastTid > 0 ? lastTid : null,
    );
    return changed(state);
  }

  Future<bool> unfollow(String uid) async {
    final id = UserBlockIndex.normalizeUid(uid);
    if (id == null) return false;
    final started = epoch;
    if (activeState?.loaded != true) await load();
    final state = activeState;
    if (started != epoch || state == null) return false;
    if (state.entries.remove(id) == null) return flush();
    state.activities.removeWhere((_, e) => e.thread.authorUid == id);
    return changed(state);
  }

  /// A sighting above the user's high-water mark increments their count once.
  /// Lists with several new threads for one user can supply them oldest first.
  Future<bool> sight({
    required String? uid,
    required int tid,
    required int fid,
  }) async {
    if (tid <= 0 || fid <= 0) return true;
    final started = epoch;
    await load();
    final state = activeState;
    if (started != epoch || state == null) return false;
    final entry = state.entries[UserBlockIndex.normalizeUid(uid)];
    if (entry == null || tid <= (entry.lastTid ?? 0)) return flush();
    _advance(state, entry, tid, unseen: true);
    return changed(state);
  }

  /// List sightings share the same watermark as individual sightings and checks.
  Future<bool> sightThreads(Iterable<ThreadSummary> threads) async {
    final started = epoch;
    await load();
    final state = activeState;
    if (started != epoch || state == null) return false;
    final ordered = threads.toList()..sort((a, b) => a.tid.compareTo(b.tid));
    final now = DateTime.now();
    var captured = false;
    for (final thread in ordered) {
      final entry =
          state.entries[UserBlockIndex.normalizeUid(thread.authorUid)];
      if (entry == null || thread.tid <= 0 || (thread.forumFid ?? 0) <= 0) {
        continue;
      }
      if (thread.tid <= (entry.lastTid ?? 0) &&
          !state.activities.containsKey(thread.tid)) {
        continue;
      }
      captured =
          _capture(state, entry, thread, now, undatedUnseen: false) || captured;
    }
    return captured ? _activitiesChanged(state) : true;
  }

  /// A first successful check establishes the baseline for undated topics.
  Future<bool> recordThreadCheck(
    FollowedUser user,
    Iterable<ThreadSummary> threads, {
    required DateTime at,
    bool Function()? shouldContinue,
  }) async {
    final started = epoch;
    await load();
    final state = activeState;
    if (started != epoch || state == null) return false;
    final entry = state.entries[user.uid];
    if (entry == null ||
        entry._generation != user._generation ||
        shouldContinue?.call() == false) {
      return true;
    }
    final ordered = threads.toList()..sort((a, b) => a.tid.compareTo(b.tid));
    final baseline = entry.lastCheck == null && entry.lastTid == null;
    for (final thread in ordered) {
      if (thread.tid <= 0 || (thread.forumFid ?? 0) <= 0) continue;
      _capture(
        state,
        state.entries[entry.uid]!,
        thread,
        at,
        undatedUnseen: !baseline,
      );
    }
    state.entries[entry.uid] = state.entries[entry.uid]!._withActivity(
      lastCheck: at,
    );
    return _activitiesChanged(state);
  }

  bool _capture(
    FollowIndexState state,
    FollowedUser entry,
    ThreadSummary thread,
    DateTime now, {
    required bool undatedUnseen,
  }) {
    final previous = state.activities[thread.tid];
    final createdAt =
        thread.createdAt ??
        parseSiteTime(thread.createdAtRaw ?? '', now: now) ??
        previous?.thread.createdAt;
    final newer = thread.tid > (entry.lastTid ?? 0);
    final unseen = newer && (createdAt?.isAfter(entry.at) ?? undatedUnseen);
    if (newer) {
      _advance(state, entry, thread.tid, unseen: unseen);
    }
    final at = createdAt ?? previous?.at ?? now;
    if (previous != null &&
        previous.thread.title == thread.title &&
        previous.thread.createdAt == createdAt &&
        previous.thread.forumName ==
            (thread.forumName ?? previous.thread.forumName) &&
        previous.thread.forumFid == thread.forumFid &&
        previous.thread.observedReplies ==
            (thread.observedReplies ?? previous.thread.observedReplies)) {
      return newer;
    }
    state.activities[thread.tid] = FollowActivity(
      ThreadSummary(
        tid: thread.tid,
        author: entry.name,
        authorUid: entry.uid,
        title: thread.title,
        forumFid: thread.forumFid,
        forumName: thread.forumName ?? previous?.thread.forumName,
        createdAt: createdAt,
        replies: thread.observedReplies ?? previous?.thread.observedReplies,
        views: 0,
      ),
      at,
      unseen: previous?.unseen ?? unseen,
    );
    return true;
  }

  void _advance(
    FollowIndexState state,
    FollowedUser entry,
    int tid, {
    required bool unseen,
  }) {
    state.entries[entry.uid] = entry._withActivity(
      lastTid: tid,
      unseen: entry.unseen + (unseen ? 1 : 0),
    );
  }

  void _trimActivities(FollowIndexState state) {
    for (final result in _sortedActivities(state).skip(_maxActivities)) {
      state.activities.remove(result.thread.tid);
    }
  }

  Future<bool> _activitiesChanged(FollowIndexState state) {
    _trimActivities(state);
    return changed(state);
  }

  /// Records a successful check; passive sightings do not affect frequency.
  Future<bool> recordCheck(String uid, {DateTime? at}) async {
    final started = epoch;
    await load();
    final state = activeState;
    if (started != epoch || state == null) return false;
    final entry = state.entries[UserBlockIndex.normalizeUid(uid)];
    final checkedAt = at ?? DateTime.now();
    if (entry == null || entry.lastCheck?.isBefore(checkedAt) == false) {
      return flush();
    }
    state.entries[entry.uid] = entry._withActivity(lastCheck: checkedAt);
    return changed(state);
  }

  Future<bool> markAllSeen() async {
    final started = epoch;
    await load();
    final state = activeState;
    if (started != epoch || state == null) return false;
    if (_unseenCount(state) == 0) return flush();
    state.entries.updateAll(
      (_, entry) => entry.unseen == 0 ? entry : entry._withActivity(unseen: 0),
    );
    state.activities.updateAll(
      (_, item) => item.unseen
          ? FollowActivity(item.thread, item.at, unseen: false)
          : item,
    );
    return changed(state);
  }

  @override
  String encode(FollowIndexState state) => jsonEncode({
    'version': 1,
    'hasEverFollowed': state.hasEverFollowed,
    'activities': [
      for (final item in state.activities.values)
        {
          'tid': item.thread.tid,
          'uid': item.thread.authorUid,
          'fid': item.thread.forumFid,
          'forum': item.thread.forumName,
          'title': item.thread.title,
          'at': item.at.millisecondsSinceEpoch,
          'createdAt': item.thread.createdAt?.millisecondsSinceEpoch,
          'replies': item.thread.observedReplies,
          'unseen': item.unseen,
        },
    ],
    'users': [
      for (final e in state.entries.values)
        {
          'uid': e.uid,
          'name': e.name,
          'avatar': e.avatar,
          'at': e.at.millisecondsSinceEpoch,
          'lastTid': e.lastTid,
          'lastCheck': e.lastCheck?.millisecondsSinceEpoch,
          'unseen': e.unseen,
        },
    ],
  });
}
