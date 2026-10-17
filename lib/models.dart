// PlanBox 数据模型 v0.3
// Lesson 课程 / Override 临时调课 / Task 计划 / PeriodTime 节次时刻

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

class Task {
  int? id;
  String title;
  String subject;
  int? startAt; // 开始时间（可为空 -> 计划池）
  int? dueAt; // 截止时间（可为空）
  int priority; // 0低 1中 2高
  bool done;
  int inPool; // 1 = 周末/自习池（无固定时间）
  int createdAt;

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
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

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
      );

  bool get overdue =>
      !done && dueAt != null && dueAt! < DateTime.now().millisecondsSinceEpoch;

  DateTime? get startDt =>
      startAt == null ? null : DateTime.fromMillisecondsSinceEpoch(startAt!);

  DateTime? get dueDt =>
      dueAt == null ? null : DateTime.fromMillisecondsSinceEpoch(dueAt!);
}

/// 一节课的起止时刻，形如 "08:00"
class PeriodTime {
  final String s;
  final String e;
  const PeriodTime(this.s, this.e);

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

const List<PeriodTime> kDefaultPeriodTimes = [
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
