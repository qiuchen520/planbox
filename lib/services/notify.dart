import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/db.dart';
import '../models.dart';

/// 本地通知：给「计划」排提醒。
///
/// 设计上只有一处入口 [syncTask]，DB 每次写库后通过 [DB.taskHook] 调进来，
/// 所以界面上新增 / 修改 / 勾选 / 删除都不用各自记得去排期。
///
/// 通知 id 用任务 id 偏移得到，保证「同一条计划永远只占一个槽位」，
/// 重复排期不会堆叠出十几条一样的提醒。
class Notify {
  Notify._();
  static final Notify i = Notify._();

  static const _channelId = 'planbox_reminder';
  static const _channelName = '计划提醒';
  static const _channelDesc = '计划开始 / 截止前的提醒';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  bool enabled = false;
  int lead = 10; // 提前几分钟
  bool sound = true;
  bool vibrate = true;

  bool get ready => _ready;

  // ── 时区推断 ──────────────────────────────────────
  /// 不用 flutter_timezone 插件：那个插件的 Kotlin 目标写死 1.8，和 Java 11
  /// 冲突，会把 CI 编译直接搞挂。改成「拿系统 UTC 偏移量去库里找同时区的地方」。
  /// 偏移相同的城市很多（+8 有上海、台北、新加坡…），所以先按常用顺序试，
  /// 都对不上再扫全库兜底。对提醒而言，只要偏移和夏令时规则对得上就够了。
  static const _tzCandidates = <String>[
    'Asia/Shanghai', 'Asia/Hong_Kong', 'Asia/Taipei', 'Asia/Singapore',
    'Asia/Tokyo', 'Asia/Seoul', 'Asia/Bangkok', 'Asia/Kolkata', 'Asia/Dubai',
    'Europe/Moscow', 'Europe/Berlin', 'Europe/Paris', 'Europe/London',
    'America/New_York', 'America/Chicago', 'America/Denver',
    'America/Los_Angeles', 'Australia/Sydney', 'Pacific/Auckland', 'UTC',
  ];

  static String _guessTzName() {
    final offMin = DateTime.now().timeZoneOffset.inMinutes;
    for (final n in _tzCandidates) {
      try {
        if (tz.getLocation(n).currentTimeZone.offset ~/ 60000 == offMin) return n;
      } catch (_) {
        // 这个名字不在库里，跳过
      }
    }
    for (final loc in tz.timeZoneDatabase.locations.values) {
      if (loc.currentTimeZone.offset ~/ 60000 == offMin) return loc.name;
    }
    return 'Asia/Shanghai';
  }

  // ── 初始化 ────────────────────────────────────────
  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation(_guessTzName()));
      } catch (e) {
        // 拿不到时区名就退回上海，至少不会差 8 小时
        tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
        debugPrint('取时区失败，退回 Asia/Shanghai: $e');
      }
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        const InitializationSettings(android: android),
        onDidReceiveNotificationResponse: (resp) {
          // 点通知暂时只做「打开 App」，后续可以跳到对应计划
        },
      );
      _ready = true;
      await load();
      debugPrint('通知就绪：enabled=$enabled lead=$lead');
    } catch (e) {
      debugPrint('通知初始化失败（不影响其他功能）: $e');
    }
  }

  /// 从设置表读回开关
  Future<void> load() async {
    enabled = (await DB.i.getSetting('notify_enabled') ?? '0') == '1';
    lead = int.tryParse(await DB.i.getSetting('notify_lead') ?? '10') ?? 10;
    sound = (await DB.i.getSetting('notify_sound') ?? '1') == '1';
    vibrate = (await DB.i.getSetting('notify_vibrate') ?? '1') == '1';
  }

  Future<void> saveConfig({
    bool? enabled,
    int? lead,
    bool? sound,
    bool? vibrate,
  }) async {
    if (enabled != null) {
      this.enabled = enabled;
      await DB.i.setSetting('notify_enabled', enabled ? '1' : '0');
    }
    if (lead != null) {
      this.lead = lead;
      await DB.i.setSetting('notify_lead', '$lead');
    }
    if (sound != null) {
      this.sound = sound;
      await DB.i.setSetting('notify_sound', sound ? '1' : '0');
    }
    if (vibrate != null) {
      this.vibrate = vibrate;
      await DB.i.setSetting('notify_vibrate', vibrate ? '1' : '0');
    }
  }

  /// Android 13+ 需要运行时授权；老系统直接返回 true。
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return false;
      final granted = await android.requestNotificationsPermission();
      return granted ?? true;
    } catch (e) {
      debugPrint('申请通知权限失败: $e');
      return false;
    }
  }

  // ── 排期 ──────────────────────────────────────────
  int _idOf(int taskId) => 100000 + taskId;

  AndroidNotificationDetails _details(String body) =>
      AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        playSound: sound,
        enableVibration: vibrate,
        styleInformation: BigTextStyleInformation(body),
      );

  /// 一条计划该在什么时候提醒：优先开始时间，没有就用截止时间。
  DateTime? remindAtOf(Task t) {
    final base = t.startDt ?? t.dueDt;
    if (base == null) return null;
    return base.subtract(Duration(minutes: lead));
  }

  /// 单条计划的排期（增删改都走这里）。失败一律吞掉，不能让写库事务挂掉。
  Future<void> syncTask(Task t, [String op = 'save']) async {
    if (!_ready) return;
    final id = t.id;
    if (id == null) return;
    try {
      await _plugin.cancel(_idOf(id));
      if (op != 'save' || t.done || !enabled) return;

      final when = remindAtOf(t);
      if (when == null) return;
      if (!when.isAfter(DateTime.now())) return; // 已经过去的不再补

      final label = t.subject.isEmpty ? '' : '【${t.subject}】';
      final title = when.isBefore(DateTime.now()) ? '计划提醒' : '${label}${t.title}';
      final body = _body(t, when);
      await _schedule(_idOf(id), title, body, when);
    } catch (e) {
      debugPrint('排期失败 task=$id: $e');
    }
  }

  String _body(Task t, DateTime when) {
    final parts = <String>[];
    if (t.dueDt != null) {
      parts.add('截止 ${_hm(t.dueDt!)}');
      final left = t.dueDt!.difference(DateTime.now());
      if (left.inMinutes > 0 && left.inMinutes < 24 * 60) {
        parts.add('还有 ${left.inMinutes} 分钟');
      }
    } else {
      parts.add('${_hm(when)} 开始');
    }
    if (t.note.isNotEmpty) parts.add(t.note);
    if (t.subTotal > 0) parts.add('步骤 ${t.subDone}/${t.subTotal}');
    return parts.join(' · ');
  }

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _schedule(int id, String title, String body, DateTime when) async {
    final at = tz.TZDateTime.from(when, tz.local);
    final details = NotificationDetails(android: _details(body));
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        at,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'task',
      );
    } catch (_) {
      // 没拿到精确闹钟权限就退化成「容忍延迟」，宁可晚一点也别不提醒
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        at,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'task',
      );
    }
  }

  /// 开关关闭 / 恢复备份后，整体重排一遍
  Future<void> resyncAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      if (!enabled) return;
      final list = await DB.i.tasks();
      for (final t in list) {
        await syncTask(t);
      }
    } catch (e) {
      debugPrint('整体重排失败: $e');
    }
  }

  Future<void> cancelTask(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_idOf(id));
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// 设置页的「发一条试试」：立刻弹一条，用来验证声音 / 震动 / 通知权限
  Future<void> showTest() async {
    if (!_ready) return;
    await _plugin.show(
      99999,
      '计划盒提醒测试',
      sound && vibrate
          ? '如果你看到这条、听到声音、手机还震了一下，说明一切正常'
          : '如果你看到这条，说明通知能弹出来',
      NotificationDetails(android: _details('通知测试')),
    );
  }
}
