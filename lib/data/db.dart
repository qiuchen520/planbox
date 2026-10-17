import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models.dart';

class DB {
  DB._();
  static final DB i = DB._();
  static Database? _db;

  /// 计划增删改后的回调，由 main 里挂到通知服务上。
  /// 用回调而不是直接 import notify，是为了避免 db ↔ notify 互相 import。
  static Future<void> Function(Task task, String op)? taskHook;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'planbox.db'),
      version: 3,
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
          created_at INTEGER NOT NULL,
          note TEXT NOT NULL DEFAULT '',
          estimate INTEGER NOT NULL DEFAULT 0,
          repeat_kind INTEGER NOT NULL DEFAULT 0,
          repeat_days INTEGER NOT NULL DEFAULT 0,
          repeat_until INTEGER,
          subtasks TEXT NOT NULL DEFAULT '',
          done_count INTEGER NOT NULL DEFAULT 0,
          last_done INTEGER)''');
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
        Future<void> tryExec(String sql) async {
          try {
            await db.execute(sql);
          } catch (_) {}
        }

        if (oldV < 2) {
          const cols = [
            'ALTER TABLE lesson ADD COLUMN start_week INTEGER NOT NULL DEFAULT 1',
            'ALTER TABLE lesson ADD COLUMN end_week INTEGER NOT NULL DEFAULT 20',
            'ALTER TABLE task ADD COLUMN start_at INTEGER',
            'ALTER TABLE task ADD COLUMN in_pool INTEGER NOT NULL DEFAULT 0',
            '''CREATE TABLE IF NOT EXISTS lesson_override(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              lesson_id INTEGER NOT NULL,
              week_no INTEGER NOT NULL,
              cancelled INTEGER NOT NULL DEFAULT 0,
              subject TEXT,
              room TEXT,
              teacher TEXT)''',
          ];
          for (final c in cols) {
            await tryExec(c);
          }
        }

        if (oldV < 3) {
          const cols = [
            "ALTER TABLE task ADD COLUMN note TEXT NOT NULL DEFAULT ''",
            'ALTER TABLE task ADD COLUMN estimate INTEGER NOT NULL DEFAULT 0',
            'ALTER TABLE task ADD COLUMN repeat_kind INTEGER NOT NULL DEFAULT 0',
            'ALTER TABLE task ADD COLUMN repeat_days INTEGER NOT NULL DEFAULT 0',
            'ALTER TABLE task ADD COLUMN repeat_until INTEGER',
            "ALTER TABLE task ADD COLUMN subtasks TEXT NOT NULL DEFAULT ''",
            'ALTER TABLE task ADD COLUMN done_count INTEGER NOT NULL DEFAULT 0',
            'ALTER TABLE task ADD COLUMN last_done INTEGER',
          ];
          for (final c in cols) {
            await tryExec(c);
          }
        }
      },
    );
    return _db!;
  }

  // ── 课表 ──────────────────────────────────────────
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

  /// 按科目重算颜色（切换科目色板后调用，让旧课表也变色）
  Future<int> recolorLessons({required int Function(String) colorOf}) async {
    final db = await _open();
    final rows = await db.query('lesson');
    var n = 0;
    for (final r in rows) {
      final l = Lesson.fromMap(r);
      final c = colorOf(l.subject);
      if (c != l.color) {
        await db.update('lesson', {'color': c},
            where: 'id=?', whereArgs: [l.id]);
        n++;
      }
    }
    return n;
  }

  // ── 临时调课 ──────────────────────────────────────
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

  // ── 计划 ──────────────────────────────────────────
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
    await taskHook?.call(t, 'save');
  }

  /// 勾选 / 取消勾选。重复计划会就地推进到下一次，而不是消失。
  Future<void> toggleTask(Task t) async {
    if (t.done) {
      t.done = false;
    } else {
      t.advanceAfterDone();
    }
    await saveTask(t);
  }

  Future<void> deleteTask(int id) async {
    final db = await _open();
    await db.delete('task', where: 'id=?', whereArgs: [id]);
    await taskHook?.call(Task(id: id, title: ''), 'delete');
  }

  /// 清理所有已完成的计划，返回删除条数
  Future<int> clearDoneTasks() async {
    final db = await _open();
    final n = await db.delete('task', where: 'done=1');
    await taskHook?.call(Task(title: ''), 'clear');
    return n;
  }

  // ── 设置 ──────────────────────────────────────────
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

  Future<void> setPeriodTimes(List<PeriodTime> list) =>
      setSetting('period_times', jsonEncode(list.map((e) => e.toJson()).toList()));

  /// 当前周次：优先按开学日期自动算，否则用手动值
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

  // ── 备份 / 恢复 ───────────────────────────────────
  /// 导出全部数据（给 Backup 用）。原样吐出表里的行，不做模型转换，
  /// 这样以后加字段也不会因为 fromMap 忽略掉而丢数据。
  Future<Map<String, dynamic>> dumpAll() async {
    final db = await _open();
    return {
      'lessons': await db.query('lesson'),
      'overrides': await db.query('lesson_override'),
      'tasks': await db.query('task'),
      'settings': await db.query('setting'),
    };
  }

  /// 覆盖式写入（恢复备份）。整个过程放在一个事务里，
  /// 中途出错就整体回滚，不会出现「清空了但没写进去」的空库。
  Future<void> replaceAll({
    required List<Map<String, Object?>> lessons,
    required List<Map<String, Object?>> overrides,
    required List<Map<String, Object?>> tasks,
    required Map<String, String> settings,
  }) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete('lesson');
      await txn.delete('lesson_override');
      await txn.delete('task');
      await txn.delete('setting');
      for (final m in lessons) {
        await txn.insert('lesson', m, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final m in overrides) {
        await txn.insert('lesson_override', m,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final m in tasks) {
        await txn.insert('task', m, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final e in settings.entries) {
        await txn.insert('setting', {'key': e.key, 'value': e.value},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}