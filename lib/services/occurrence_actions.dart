import 'dart:async';

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../models.dart';
import '../theme.dart';
import 'notify.dart';

/// 重复计划里的「这一次」操作：跳过这一次 / 这一次改个时间 / 撤销这次例外。
///
/// 规则本身永远不动，只写一条 [TaskException] 挂在某一天上 ——
/// 这样「每周三 9:00」不会因为某周没做就整条变形。
class OccurrenceActions {
  OccurrenceActions._();

  /// [focusDay] 为空时操作「下一次」；给它就把范围锁在那一天。
  static Future<bool> showMenu(
    BuildContext context,
    Task t, {
    DateTime? focusDay,
  }) async {
    if (!t.isRepeating || t.id == null) return false;
    final now = DateTime.now();
    final day = focusDay ?? _nextOccurrenceDay(t, now);
    if (day == null) return false;
    final ex = t.exceptionOn(day);
    final act = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text(
                '${t.title} · ${day.month}/${day.day} 这一次',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                ex == null
                    ? '只改这一次，${t.repeatLabel}的规则不变'
                    : (ex.isSkip ? '这一次已跳过' : '这一次已改到别的时间'),
                style: TextStyle(fontSize: 12, color: kDim, height: 1.5),
              ),
            ),
            if (ex == null) ...[
              ListTile(
                leading: Icon(Icons.event_busy_outlined, color: kWarn),
                title: Text('跳过这一次'),
                subtitle: Text('规则不动，下一次照常',
                    style: TextStyle(fontSize: 11.5, color: kFaint)),
                onTap: () => Navigator.pop(ctx, 'skip'),
              ),
              ListTile(
                leading: Icon(Icons.schedule_outlined, color: kAcc),
                title: Text('这一次改时间'),
                subtitle: Text('只挪这一次，规则不动',
                    style: TextStyle(fontSize: 11.5, color: kFaint)),
                onTap: () => Navigator.pop(ctx, 'move'),
              ),
            ] else
              ListTile(
                leading: Icon(Icons.undo_rounded, color: kAcc),
                title: Text('撤销这一次的例外'),
                onTap: () => Navigator.pop(ctx, 'undo'),
              ),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || act == null) return false;

    switch (act) {
      case 'skip':
        await DB.i.saveException(TaskException(
          taskId: t.id!,
          day: dayKeyOf(day),
          kind: TaskException.kindSkip,
        ));
        t.exceptions = await DB.i.exceptionsOf(t.id!);
        unawaited(Notify.i.resyncAll());
        _toast(context, '已跳过 ${day.month}/${day.day} 这一次');
        return true;
      case 'move':
        final picked = await _pickDateTime(context, day);
        if (picked == null) return false;
        await DB.i.saveException(TaskException(
          taskId: t.id!,
          day: dayKeyOf(day),
          kind: TaskException.kindMove,
          newAt: picked.millisecondsSinceEpoch,
        ));
        t.exceptions = await DB.i.exceptionsOf(t.id!);
        unawaited(Notify.i.resyncAll());
        _toast(
          context,
          '这一次改到 ${picked.month}/${picked.day} '
          '${picked.hour.toString().padLeft(2, '0')}:'
          '${picked.minute.toString().padLeft(2, '0')}',
        );
        return true;
      case 'undo':
        await DB.i.deleteException(t.id!, dayKeyOf(day));
        t.exceptions = await DB.i.exceptionsOf(t.id!);
        unawaited(Notify.i.resyncAll());
        _toast(context, '已恢复这一次');
        return true;
    }
    return false;
  }

  /// 下一次该在哪一天（找不到就 null）
  static DateTime? _nextOccurrenceDay(Task t, DateTime from) {
    final ms = t.nextOccurrence(from.millisecondsSinceEpoch);
    if (ms == from.millisecondsSinceEpoch) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// 先选日期再选时间，默认沿用这一次原本的时分
  static Future<DateTime?> _pickDateTime(
      BuildContext context, DateTime day) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: '这一次改到哪天',
    );
    if (d == null || !context.mounted) return null;
    final tm = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: day.hour, minute: day.minute),
      helpText: '这一天几点',
    );
    if (tm == null) return null;
    return DateTime(d.year, d.month, d.day, tm.hour, tm.minute);
  }

  static void _toast(BuildContext context, String msg) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.clearSnackBars();
    m?.showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(milliseconds: 1600),
    ));
  }
}
