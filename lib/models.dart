// PlanBox 数据模型 v0.4
// Lesson 课程 / Override 临时调课 / Task 计划 / Subtask 子步骤 / PeriodTime 节次时刻

import 'dart:convert';

class Lesson {
  int? id;
  int weekday; // 1=周一 ... 7=周日
  int period; // 1..12
  String subject;
  String room;
  String teacher;
  int weekType; // 0=全周 1=单周 2=双周
  int startWeek; // 起始周
  int endWeek; // 结束周
  int color;

  Lesson({
    this.id,
    required this.weekday,
    required this.period,
    required this.subject,
    this.room = '',
    this.teacher = '',
    this.weekType = 0,
    this.startWeek = 1,
    this.endWeek = 20,
    this.color = 0xFF5B9CFF,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'weekday': weekday,
        'period': period,
        'subject': subject,
        'room': room,
        'teacher': teacher,
        'week_type': weekType,
        'start_week': startWeek,
        'end_week': endWeek,
        'color': color,
      };

  static Lesson fromMap(Map<String, Object?> m) => Lesson(
        id: m['id'] as int?,
        weekday: m['weekday'] as int,
        period: m['period'] as int,
        subject: (m['subject'] ?? '') as String,
        room: (m['room'] ?? '') as String,
        teacher: (m['teacher'] ?? '') as String,
        weekType: (m['week_type'] ?? 0) as int,
        startWeek: (m['start_week'] ?? 1) as int,
        endWeek: (m['end_week'] ?? 20) as int,
        color: (m['color'] ?? 0xFF5B9CFF) as int,
      );

  /// 该课在「第 w 周」是否要上（周区间 + 单双周）
  bool activeInWeek(int w) {
    if (w < startWeek || w > endWeek) return false;
    if (weekType == 1) return w.isOdd;
    if (weekType == 2) return w.isEven;
    return true;
  }

  String get typeLabel =>
      weekType == 1 ? '单周' : (weekType == 2 ? '双周' : '全周');

  /// 角标：单 / 双 / 全周不显示
  String get badge => weekType == 1 ? '单' : (weekType == 2 ? '双' : '');

  String get rangeLabel => '$typeLabel $startWeek-$endWeek';
}

/// 临时调课：只影响某一周
class Override {
  int? id;
  int lessonId;
  int weekNo;
  bool cancelled; // 本周不上
  String subject; // 覆盖后的科目（空=沿用原课）
  String room;
  String teacher;

  Override({
    this.id,
    required this.lessonId,
    required this.weekNo,
    this.cancelled = false,
    this.subject = '',
    this.room = '',
    this.teacher = '',
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'lesson_id': lessonId,
        'week_no': weekNo,
        'cancelled': cancelled ? 1 : 0,
        'subject': subject,
        'room': room,
        'teacher': teacher,
      };

  static Override fromMap(Map<String, Object?> m) => Override(
        id: m['id'] as int?,
        lessonId: m['lesson_id'] as int,
        weekNo: m['week_no'] as int,
        cancelled: (m['cancelled'] ?? 0) == 1,
        subject: (m['subject'] ?? '') as String,
        room: (m['room'] ?? '') as String,
        teacher: (m['teacher'] ?? '') as String,
      );
}

/// 计划里的一个可勾选步骤
class Subtask {
  String title;
  bool done;

  Subtask(this.title, [this.done = false]);

  Map<String, Object?> toJson() => {'t': title, 'd': done};

  static Subtask fromJson(Map<String, Object?> m) =>
      Subtask((m['t'] ?? '') as String, (m['d'] ?? false) == true);
}

class Task {
  int? id;
  String title;
  String subject;
  int? startAt; // 开始时间（可为空 → 待办）
  int? dueAt; // 截止时间（可为空）
  int priority; // 0低 1中 2高
  bool done;
  int inPool; // 1 = 周末/自习池（无固定时间）
  int createdAt;

  // ── v0.4 新增 ──
  String note; // 详情/备注
  int estimate; // 预计用时（分钟），0 = 未设
  int repeatKind; // 0 不重复 / 1 每天 / 2 工作日 / 3 每周指定日
  int repeatDays; // 位掩码：bit0=周一 … bit6=周日
  int? repeatUntil; // 重复截止（毫秒，空=一直重复）
  List<Subtask> subtasks; // 子步骤
  int doneCount; // 累计完成次数（打卡统计）
  int? lastDone; // 最近一次完成时间

  Task({
    this.id,
    required this.title,
    this.subject = '',
    this.startAt,
    this.dueAt,
    this.priority = 1,
    this.done = false,
    this.inPool = 0,
    int? createdAt,
    this.note = '',
    this.estimate = 0,
    this.repeatKind = 0,
    this.repeatDays = 0,
    this.repeatUntil,
    List<Subtask>? subtasks,
    this.doneCount = 0,
    this.lastDone,
  })  : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        subtasks = subtasks ?? <Subtask>[];

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'subject': subject,
        'start_at': startAt,
        'due_at': dueAt,
        'priority': priority,
        'done': done ? 1 : 0,
        'in_pool': inPool,
        'created_at': createdAt,
        'note': note,
        'estimate': estimate,
        'repeat_kind': repeatKind,
        'repeat_days': repeatDays,
        'repeat_until': repeatUntil,
        'subtasks': jsonEncode(subtasks.map((s) => s.toJson()).toList()),
        'done_count': doneCount,
        'last_done': lastDone,
      };

  static Task fromMap(Map<String, Object?> m) => Task(
        id: m['id'] as int?,
        title: (m['title'] ?? '') as String,
        subject: (m['subject'] ?? '') as String,
        startAt: m['start_at'] as int?,
        dueAt: m['due_at'] as int?,
        priority: (m['priority'] ?? 1) as int,
        done: (m['done'] ?? 0) == 1,
        inPool: (m['in_pool'] ?? 0) as int,
        createdAt: (m['created_at'] ?? 0) as int,
        note: (m['note'] ?? '') as String,
        estimate: (m['estimate'] ?? 0) as int,
        repeatKind: (m['repeat_kind'] ?? 0) as int,
        repeatDays: (m['repeat_days'] ?? 0) as int,
        repeatUntil: m['repeat_until'] as int?,
        subtasks: _decodeSubs(m['subtasks']),
        doneCount: (m['done_count'] ?? 0) as int,
        lastDone: m['last_done'] as int?,
      );

  static List<Subtask> _decodeSubs(Object? raw) {
    if (raw is! String || raw.isEmpty) return <Subtask>[];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Subtask.fromJson((e as Map).cast<String, Object?>()))
          .where((s) => s.title.isNotEmpty)
          .toList();
    } catch (_) {
      return <Subtask>[];
    }
  }

  // ── 派生属性 ────────────────────────────────────
  bool get overdue =>
      !done && dueAt != null && dueAt! < DateTime.now().millisecondsSinceEpoch;

  DateTime? get startDt =>
      startAt == null ? null : DateTime.fromMillisecondsSinceEpoch(startAt!);

  DateTime? get dueDt =>
      dueAt == null ? null : DateTime.fromMillisecondsSinceEpoch(dueAt!);

  bool get isRepeating => repeatKind > 0;

  /// 重复任务要有效推进，必须有开始时间
  bool get repeatActive => repeatKind > 0 && startAt != null;

  int get subTotal => subtasks.length;
  int get subDone => subtasks.where((s) => s.done).length;
  double? get subProgress => subTotal == 0 ? null : subDone / subTotal;

  String get estimateLabel {
    if (estimate <= 0) return '';
    if (estimate < 60) return '$estimate 分钟';
    final h = estimate ~/ 60;
    final m = estimate % 60;
    return m == 0 ? '$h 小时' : '$h 小时 $m 分';
  }

  static List<String> _wdCn = ['一', '二', '三', '四', '五', '六', '日'];

  String get repeatLabel {
    switch (repeatKind) {
      case 1:
        return '每天';
      case 2:
        return '工作日';
      case 3:
        final mask = repeatDays == 0 ? 0 : repeatDays;
        if (mask == 0) return '每周';
        final parts = <String>[];
        for (var i = 0; i < 7; i++) {
          if (mask & (1 << i) != 0) parts.add(_wdCn[i]);
        }
        if (parts.length == 7) return '每天';
        if (parts.length == 5 &&
            mask == 0x1F) {
          return '工作日';
        }
        return '周${parts.join('·')}';
      default:
        return '';
    }
  }

  /// 从 [fromMs] 推算下一次执行时刻
  int nextOccurrence(int fromMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(fromMs);
    switch (repeatKind) {
      case 1:
        return DateTime(d.year, d.month, d.day + 1, d.hour, d.minute)
            .millisecondsSinceEpoch;
      case 2:
        var t = DateTime(d.year, d.month, d.day + 1, d.hour, d.minute);
        var guard = 0;
        while (t.weekday > 5 && guard < 10) {
          t = DateTime(t.year, t.month, t.day + 1, t.hour, t.minute);
          guard++;
        }
        return t.millisecondsSinceEpoch;
      case 3:
        final mask = repeatDays == 0 ? (1 << (d.weekday - 1)) : repeatDays;
        for (var i = 1; i <= 7; i++) {
          final n = DateTime(d.year, d.month, d.day + i, d.hour, d.minute);
          if (mask & (1 << (n.weekday - 1)) != 0) {
            return n.millisecondsSinceEpoch;
          }
        }
        return DateTime(d.year, d.month, d.day + 7, d.hour, d.minute)
            .millisecondsSinceEpoch;
      default:
        return fromMs;
    }
  }

  /// 打完卡后推进到下一次；返回 true 表示这一条彻底结束了
  bool advanceAfterDone({DateTime? now}) {
    final n = now ?? DateTime.now();
    doneCount += 1;
    lastDone = n.millisecondsSinceEpoch;
    if (!repeatActive) {
      done = true;
      return true;
    }
    final base = startAt!;
    final next = nextOccurrence(base);
    if (repeatUntil != null && next > repeatUntil!) {
      done = true;
      return true;
    }
    final gap = (startAt != null && dueAt != null) ? dueAt! - startAt! : 0;
    startAt = next;
    if (dueAt != null) dueAt = next + gap;
    return false;
  }
}

/// 一节课的起止时刻，形如 "08:00"
class PeriodTime {
  final String s;
  final String e;
  PeriodTime(this.s, this.e);

  Map<String, Object?> toJson() => {'s': s, 'e': e};

  static PeriodTime fromJson(Map<String, Object?> m) =>
      PeriodTime((m['s'] ?? '08:00') as String, (m['e'] ?? '08:45') as String);

  static int minutes(String hhmm) {
    final p = hhmm.split(':');
    if (p.length != 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  static String hhmm(int minutes) {
    final m = minutes.clamp(0, 24 * 60);
    return '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }

  int get startMin => minutes(s);
  int get endMin => minutes(e);
}

List<PeriodTime> kDefaultPeriodTimes = [
  PeriodTime('08:00', '08:45'),
  PeriodTime('08:55', '09:40'),
  PeriodTime('10:00', '10:45'),
  PeriodTime('10:55', '11:40'),
  PeriodTime('11:50', '12:35'),
  PeriodTime('14:00', '14:45'),
  PeriodTime('14:55', '15:40'),
  PeriodTime('15:50', '16:35'),
  PeriodTime('16:45', '17:30'),
  PeriodTime('19:00', '19:45'),
  PeriodTime('19:55', '20:40'),
  PeriodTime('20:50', '21:35'),
];

/// 根据开学日期算当前周次（1 起，超界钳制）
int weekOfDate({
  required DateTime semesterStart,
  required int totalWeeks,
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  final s = DateTime(semesterStart.year, semesterStart.month, semesterStart.day);
  final t = DateTime(n.year, n.month, n.day);
  final days = t.difference(s).inDays;
  final w = (days < 0 ? 0 : days ~/ 7) + 1;
  return w.clamp(1, totalWeeks < 1 ? 1 : totalWeeks);
}

/// 两个时刻是否同一天
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 从今天 0 点起算的「相对天数」：0=今天 1=明天 -1=昨天
int dayOffsetFromToday(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final t = DateTime(d.year, d.month, d.day);
  return t.difference(today).inDays;
}
