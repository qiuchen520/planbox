import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models.dart';

class DB {
  DB._();
  static final DB i = DB._();
  static Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'planbox.db'),
      version: 2,
      onCreate: (db, v) async {
        await db.execute('''CREATE TABLE lesson(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          weekday INTEGER NOT NULL,
          period INTEGER NOT NULL,
          subject TEXT NOT NULL,
          room TEXT,
          teacher TEXT,
          week_type INTEGER NOT NULL DEFAULT 0,
          start_week INTEGER NOT NULL DEFAULT 1,
          end_week INTEGER NOT NULL DEFAULT 20,
          color INTEGER NOT NULL DEFAULT 4284194815)''');
        await db.execute('''CREATE TABLE task(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          subject TEXT,
          start_at INTEGER,
          due_at INTEGER,
          priority INTEGER NOT NULL DEFAULT 1,
          done INTEGER NOT NULL DEFAULT 0,
          in_pool INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL)''');
        await db.execute('''CREATE TABLE lesson_override(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          lesson_id INTEGER NOT NULL,
          week_no INTEGER NOT NULL,
          cancelled INTEGER NOT NULL DEFAULT 0,
          subject TEXT,
          room TEXT,
          teacher TEXT)''');
        await db.execute(
            'CREATE TABLE setting(key TEXT PRIMARY KEY, value TEXT)');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          Future<void> addCol(String t, String c) async {
            try {
              await db.execute('ALTER TABLE $t ADD COLUMN $c');
            } catch (_) {}
          }

          await addCol('lesson', 'start_week INTEGER NOT NULL DEFAULT 1');
          await addCol('lesson', 'end_week INTEGER NOT NULL DEFAULT 20');
          await addCol('task', 'start_at INTEGER');
          await addCol('task', 'in_pool INTEGER NOT NULL DEFAULT 0');
          await db.execute('''CREATE TABLE IF NOT EXISTS lesson_override(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            lesson_id INTEGER NOT NULL,
            week_no INTEGER NOT NULL,
            cancelled INTEGER NOT NULL DEFAULT 0,
            subject TEXT,
            room TEXT,
            teacher TEXT)''');
        }
      },
    );
    return _db!;
  }

  // 课表
  Future<List<Lesson>> lessons() async {
    final db = await _open();
    final rows = await db.query('lesson', orderBy: 'weekday, period');
    return rows.map(Lesson.fromMap).toList();
  }

  /// 同一 (weekday, period, week_type) 视为同一格：存在则更新
  Future<void> saveLesson(Lesson l) async {
    final db = await _open();
    final exist = await db.query(
      'lesson',
      where: 'weekday=? AND period=? AND week_type=?',
      whereArgs: [l.weekday, l.period, l.weekType],
      limit: 1,
    );
    if (exist.isEmpty) {
      await db.insert('lesson', l.toMap());
    } else {
      final m = l.toMap()..remove('id');
      await db.update('lesson', m,
          where: 'id=?', whereArgs: [exist.first['id']]);
    }
  }

  /// 写入一段连堂课：periodStart..periodEnd 每节各一行
  Future<void> saveSpan(Lesson base, int periodStart, int periodEnd) async {
    for (var p = periodStart; p <= periodEnd; p++) {
      final l = Lesson(
        weekday: base.weekday,
        period: p,
        subject: base.subject,
        room: base.room,
        teacher: base.teacher,
        weekType: base.weekType,
        startWeek: base.startWeek,
        endWeek: base.endWeek,
        color: base.color,
      );
      await saveLesson(l);
    }
  }

  Future<void> deleteLesson(int id) async {
    final db = await _open();
    await db.delete('lesson', where: 'id=?', whereArgs: [id]);
    await db.delete('lesson_override', where: 'lesson_id=?', whereArgs: [id]);
  }

  Future<void> deleteLessonCell(int weekday, int period, int weekType) async {
    final db = await _open();
    await db.delete('lesson',
        where: 'weekday=? AND period=? AND week_type=?',
        whereArgs: [weekday, period, weekType]);
  }

  // 临时调课
  Future<List<Override>> overrides() async {
    final db = await _open();
    final rows = await db.query('lesson_override');
    return rows.map(Override.fromMap).toList();
  }

  Future<void> saveOverride(Override o) async {
    final db = await _open();
    final exist = await db.query('lesson_override',
        where: 'lesson_id=? AND week_no=?',
        whereArgs: [o.lessonId, o.weekNo],
        limit: 1);
    if (exist.isEmpty) {
      await db.insert('lesson_override', o.toMap());
    } else {
      final m = o.toMap()..remove('id');
      await db.update('lesson_override', m,
          where: 'id=?', whereArgs: [exist.first['id']]);
    }
  }

  Future<void> deleteOverride(int lessonId, int weekNo) async {
    final db = await _open();
    await db.delete('lesson_override',
        where: 'lesson_id=? AND week_no=?', whereArgs: [lessonId, weekNo]);
  }

  // 计划
  Future<List<Task>> tasks() async {
    final db = await _open();
    final rows = await db.query('task',
        orderBy: 'done ASC, start_at IS NULL, start_at ASC, due_at ASC');
    return rows.map(Task.fromMap).toList();
  }

  Future<void> saveTask(Task t) async {
    final db = await _open();
    if (t.id == null) {
      t.id = await db.insert('task', t.toMap());
    } else {
      await db.update('task', t.toMap(), where: 'id=?', whereArgs: [t.id]);
    }
  }

  Future<void> deleteTask(int id) async {
    final db = await _open();
    await db.delete('task', where: 'id=?', whereArgs: [id]);
  }

  // 设置
  Future<String?> getSetting(String key) async {
    final db = await _open();
    final rows =
        await db.query('setting', where: 'key=?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await _open();
    await db.insert('setting', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 手动周次（未设开学日期时的兜底）
  Future<int> weekNo() async =>
      int.tryParse(await getSetting('week_no') ?? '1') ?? 1;

  Future<void> setWeekNo(int v) => setSetting('week_no', '$v');

  /// 开学日期
  Future<DateTime?> semesterStart() async {
    final s = await getSetting('semester_start');
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  Future<void> setSemesterStart(DateTime d) => setSetting(
      'semester_start',
      '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}');

  /// 总周数
  Future<int> totalWeeks() async =>
      int.tryParse(await getSetting('total_weeks') ?? '20') ?? 20;

  Future<void> setTotalWeeks(int v) => setSetting('total_weeks', '$v');

  /// 节次时刻表
  Future<List<PeriodTime>> periodTimes() async {
    final s = await getSetting('period_times');
    if (s == null || s.isEmpty) return kDefaultPeriodTimes;
    try {
      final list = (jsonDecode(s) as List)
          .map((e) => PeriodTime.fromJson((e as Map).cast<String, Object?>()))
          .toList();
      if (list.length == kDefaultPeriodTimes.length) return list;
    } catch (_) {}
    return kDefaultPeriodTimes;
  }

  Future<void> setPeriodTimes(List<PeriodTime> list) => setSetting(
      'period_times', jsonEncode(list.map((e) => e.toJson()).toList()));

  /// 当前周次：优先按开学日期自动算，否则用存下的手动值
  Future<int> currentWeek() async {
    final start = await semesterStart();
    final total = await totalWeeks();
    if (start == null) {
      final w = await weekNo();
      return w.clamp(1, total);
    }
    return weekOfDate(semesterStart: start, totalWeeks: total);
  }

  Future<void> wipe() async {
    final db = await _open();
    await db.delete('lesson');
    await db.delete('lesson_override');
    await db.delete('task');
    await db.delete('setting');
  }
}
