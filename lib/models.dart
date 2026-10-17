class Lesson {
  int? id;
  int weekday; // 1=周一 ... 7=周日
  int period; // 1..12
  String subject;
  String room;
  String teacher;
  int weekType; // 0=每周 1=单周 2=双周
  int color;

  Lesson({
    this.id,
    required this.weekday,
    required this.period,
    required this.subject,
    this.room = '',
    this.teacher = '',
    this.weekType = 0,
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
        color: (m['color'] ?? 0xFF5B9CFF) as int,
      );

  /// 给定当前是第几周，判断这节课本周是否上
  bool matchesWeek(int weekNo) {
    final odd = weekNo.isOdd;
    if (weekType == 1) return odd;
    if (weekType == 2) return !odd;
    return true;
  }

  String get weekLabel => switch (weekType) {
        1 => '单周',
        2 => '双周',
        _ => '每周',
      };
}

class Task {
  int? id;
  String title;
  String subject;
  int? dueAt; // epoch millis
  int priority; // 0低 1中 2高
  bool done;
  int createdAt;

  Task({
    this.id,
    required this.title,
    this.subject = '',
    this.dueAt,
    this.priority = 1,
    this.done = false,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'subject': subject,
        'due_at': dueAt,
        'priority': priority,
        'done': done ? 1 : 0,
        'created_at': createdAt,
      };

  static Task fromMap(Map<String, Object?> m) => Task(
        id: m['id'] as int?,
        title: (m['title'] ?? '') as String,
        subject: (m['subject'] ?? '') as String,
        dueAt: m['due_at'] as int?,
        priority: (m['priority'] ?? 1) as int,
        done: (m['done'] ?? 0) == 1,
        createdAt: (m['created_at'] ?? 0) as int,
      );

  bool get overdue =>
      !done && dueAt != null && dueAt! < DateTime.now().millisecondsSinceEpoch;
}
