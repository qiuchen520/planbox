import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/db.dart';
import '../models.dart';

/// 能响应悬浮窗「暂停 / 继续」的那一方（目前只有 FocusPage）。
abstract class HudTimerHost {
  Future<void> hudToggleTimer();
}

/// 桌面悬浮窗的 Flutter 侧。
///
/// 分工是刻意的：Dart 只下发**数据**（今日任务、番茄钟锚点），
/// 渲染、计时、手势全在原生侧做。这样 App 被压到后台、Dart 的 Timer
/// 被系统降频时，悬浮窗上的时间仍然在走。
class Hud {
  Hud._();

  static const MethodChannel _ch = MethodChannel('planbox/hud');
  static const String settingKey = 'hud_on';

  static bool _nativeOk = true;

  /// 悬浮窗上的一次点击。action: focus / checkin / newTask / toggleTimer /
  /// alreadyDone / hudOff / launch
  static Future<void> Function(String action, int taskId)? onAction;
  /// 悬浮窗开 / 关状态变了（自己关、被系统回收、App 里关）→ 页面刷新按钮
  static void Function()? onRunningChanged;

  /// 当前正在跑的番茄钟页面（用于「暂停 / 继续」透传）
  static HudTimerHost? timerHost;

  static void init() {
    _ch.setMethodCallHandler((call) async {
      if (call.method != 'action') return null;
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      final a = '${args['action'] ?? ''}';
      if (a == 'launch') {
        await _handleLaunch('${args['payload'] ?? ''}');
        return null;
      }
      final id = (args['taskId'] as num?)?.toInt() ?? -1;
      if (a == 'hudOff') _notify();
      await onAction?.call(a, id);
      return null;
    });
  }

  static Future<void> _handleLaunch(String payload) async {
    if (payload.isEmpty) return;
    try {
      final m = jsonDecode(payload) as Map<String, dynamic>;
      final a = '${m['action'] ?? ''}';
      final id = (m['taskId'] as num?)?.toInt() ?? -1;
      await onAction?.call(a, id);
    } catch (_) {
      // 坏 payload 直接忽略，别让悬浮窗把人卡住
    }
  }

  static void _notify() {
    try {
      onRunningChanged?.call();
    } catch (_) {
      // 页面已经没了就当没听见
    }
  }

  static Future<T?> _call<T>(String method, [Map<String, dynamic>? args]) async {
    if (!_nativeOk) return null;
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on MissingPluginException {
      _nativeOk = false;
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> canShow() async => (await _call<bool>('canShow')) ?? false;

  static Future<bool> isRunning() async => (await _call<bool>('isRunning')) ?? false;

  static Future<bool> start() async {
    final ok = (await _call<bool>('start')) ?? false;
    if (ok) _notify();
    return ok;
  }

  static Future<void> stop() async {
    await _call('stop');
    _notify();
  }

  static Future<void> raise() async {
    await _call('raise');
  }

  /// 上次 App 不在时点悬浮窗留下的动作，进来先补一遍
  static Future<void> takeLaunch() async {
    final p = await _call<String>('takeLaunch');
    if (p != null && p.isNotEmpty) await _handleLaunch(p);
  }

  static Future<void> pushPayload(Map<String, dynamic> m) async {
    await _call('push', {'json': jsonEncode(m)});
  }

  /// 推当前这一轮番茄钟；null 表示这一轮结束了
  static Future<void> pushSession({
    required String title,
    required int total,
    required int remain,
    required bool running,
  }) async {
    if (total <= 0) {
      await _call('clearSession');
      return;
    }
    await _call('pushSession', {
      'json': jsonEncode({
        'title': title,
        'total': total,
        'remain': remain,
        'running': running,
        // 原生按这个锚点自己算剩余，免得两边时钟飘
        'anchorMs': DateTime.now().millisecondsSinceEpoch,
      }),
    });
  }

  static Future<void> clearSession() async {
    await _call('clearSession');
  }

  static bool _busy = false;
  static bool _again = false;

  /// 重算今日清单并下发（任务增删改、打卡、跨天都会走它）
  static Future<void> refresh() async {
    if (!_nativeOk) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      await pushPayload(await todayPayload());
    } catch (_) {
      // 悬浮窗拿不到数据不影响主界面
    } finally {
      _busy = false;
      if (_again) {
        _again = false;
        unawaited(refresh());
      }
    }
  }

  /// 今日清单：重复计划按规则展开到今天，普通计划看今天有没有排
  static Future<Map<String, dynamic>> todayPayload() async {
    final now = DateTime.now();
    final today = dayKeyOf(now);
    final tasks = await DB.i.tasks();
    final marks = <int>{};
    for (final r in await DB.i.checkins(sinceDay: today)) {
      final d = (r['day'] as int?) ?? 0;
      final id = (r['task_id'] as num?)?.toInt();
      if (d == today && id != null) marks.add(id);
    }
    final rows = <Map<String, dynamic>>[];
    for (final t in tasks) {
      if (t.id == null) continue;
      final done = marks.contains(t.id!) ||
          (t.lastDone != null &&
              sameDay(
                DateTime.fromMillisecondsSinceEpoch(t.lastDone!),
                now,
              ));
      DateTime? at;
      var due = false;
      if (t.isRepeating) {
        at = t.occurrenceOn(now);
        due = at != null || done;
      } else if (t.startDt != null && sameDay(t.startDt!, now)) {
        at = t.startDt;
        due = true;
      } else if (done) {
        due = true;
      }
      if (!due) continue;
      rows.add({
        'id': t.id,
        'title': t.title,
        'done': done,
        'time': at == null ? '' : _hhmm(at),
      });
    }
    // 没做的排前面，同组按时间
    rows.sort((a, b) {
      final da = a['done'] == true ? 1 : 0;
      final db = b['done'] == true ? 1 : 0;
      if (da != db) return da.compareTo(db);
      return '${a['time']}'.compareTo('${b['time']}');
    });
    return {
      'date': '${now.month} 月 ${now.day} 日 · ${_weekday(now.weekday)}',
      'tasks': rows,
    };
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _weekday(int w) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][(w - 1) % 7];
}