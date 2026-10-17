import 'package:flutter_test/flutter_test.dart';
import 'package:planbox/models.dart';

void main() {
  Task make({
    int? startAt,
    int? dueAt,
    int repeatKind = 0,
    int repeatDays = 0,
    int? repeatUntil,
    bool done = false,
  }) {
    return Task(
      title: 't',
      startAt: startAt,
      dueAt: dueAt,
      repeatKind: repeatKind,
      repeatDays: repeatDays,
      repeatUntil: repeatUntil,
      done: done,
    );
  }

  int ms(DateTime d) => d.millisecondsSinceEpoch;

  group('Task.occursOn —— 日历按天聚合', () {
    test('没有时间的待办不出现在任何一天', () {
      final t = make();
      expect(t.occursOn(DateTime(2026, 10, 17)), false);
    });

    test('一次性任务只出现在开始日，前后一天都不在', () {
      final t = make(startAt: ms(DateTime(2026, 10, 17, 20, 0)));
      expect(t.occursOn(DateTime(2026, 10, 17)), true);
      expect(t.occursOn(DateTime(2026, 10, 16)), false);
      expect(t.occursOn(DateTime(2026, 10, 18)), false);
    });

    test('同一天不同时刻仍算同一天', () {
      final t = make(startAt: ms(DateTime(2026, 10, 17, 0, 1)));
      expect(t.occursOn(DateTime(2026, 10, 17, 23, 59)), true);
    });

    test('只有截止日、没有开始日 → 落在截止日', () {
      final t = make(dueAt: ms(DateTime(2026, 10, 20, 22, 0)));
      expect(t.occursOn(DateTime(2026, 10, 20)), true);
      expect(t.occursOn(DateTime(2026, 10, 19)), false);
    });

    test('每天重复：开始日到截止日之间每天都出现', () {
      final t = make(
        startAt: ms(DateTime(2026, 10, 17, 8, 0)),
        repeatKind: 1,
      );
      expect(t.occursOn(DateTime(2026, 10, 16)), false);
      expect(t.occursOn(DateTime(2026, 10, 17)), true);
      expect(t.occursOn(DateTime(2026, 11, 3)), true);
    });

    test('工作日重复：周六周日不出现', () {
      final t = make(
        // 2026-10-16 是周五
        startAt: ms(DateTime(2026, 10, 16, 8, 0)),
        repeatKind: 2,
      );
      expect(t.occursOn(DateTime(2026, 10, 16)), true); // 周五
      expect(t.occursOn(DateTime(2026, 10, 17)), false); // 周六
      expect(t.occursOn(DateTime(2026, 10, 18)), false); // 周日
      expect(t.occursOn(DateTime(2026, 10, 19)), true); // 周一
    });

    test('每周指定日：只在掩码命中的星期出现', () {
      // 2026-10-17 是周六 → 位掩码 bit5
      final t = make(
        startAt: ms(DateTime(2026, 10, 17, 8, 0)),
        repeatKind: 3,
        repeatDays: 1 << 5,
      );
      expect(t.occursOn(DateTime(2026, 10, 17)), true);
      expect(t.occursOn(DateTime(2026, 10, 18)), false);
      expect(t.occursOn(DateTime(2026, 10, 24)), true);
    });

    test('repeatUntil 之后不再出现', () {
      final t = make(
        startAt: ms(DateTime(2026, 10, 17, 8, 0)),
        repeatKind: 1,
        // 截止到 10-20 当天结束
        repeatUntil: ms(DateTime(2026, 10, 20, 23, 59)),
      );
      expect(t.occursOn(DateTime(2026, 10, 20)), true);
      expect(t.occursOn(DateTime(2026, 10, 21)), false);
    });
  });

  group('Task.advanceAfterDone —— 打卡推进', () {
    test('非重复任务勾完就结束', () {
      final t = make(startAt: ms(DateTime(2026, 10, 17, 8, 0)));
      final over = t.advanceAfterDone(now: DateTime(2026, 10, 17, 9, 0));
      expect(over, true);
      expect(t.done, true);
      expect(t.doneCount, 1);
    });

    test('每天重复的任务推进到第二天，且完成状态不置位', () {
      final t = make(
        startAt: ms(DateTime(2026, 10, 17, 8, 0)),
        repeatKind: 1,
      );
      final over = t.advanceAfterDone(now: DateTime(2026, 10, 17, 9, 0));
      expect(over, false);
      expect(t.done, false);
      expect(DateTime.fromMillisecondsSinceEpoch(t.startAt!).day, 18);
      expect(t.doneCount, 1);
    });

    test('截止时间与开始时间的间隔会被保留', () {
      final start = DateTime(2026, 10, 17, 8, 0);
      final t = make(startAt: ms(start), dueAt: ms(start.add(Duration(hours: 2))),
          repeatKind: 1);
      t.advanceAfterDone(now: DateTime(2026, 10, 17, 9, 0));
      final ns = DateTime.fromMillisecondsSinceEpoch(t.startAt!);
      final nd = DateTime.fromMillisecondsSinceEpoch(t.dueAt!);
      expect(nd.difference(ns), Duration(hours: 2));
    });

    test('超过 repeatUntil 之后算彻底结束', () {
      final t = make(
        startAt: ms(DateTime(2026, 10, 20, 8, 0)),
        repeatKind: 1,
        repeatUntil: ms(DateTime(2026, 10, 20, 23, 0)),
      );
      final over = t.advanceAfterDone(now: DateTime(2026, 10, 20, 9, 0));
      expect(over, true);
      expect(t.done, true);
    });
  });
}