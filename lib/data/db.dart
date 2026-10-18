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
      version: 5,
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
          repeat_interval INTEGER NOT NULL DEFAULT 1,
          repeat_anchor INTEGER,
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
        await db.execute('''CREATE TABLE task_exception(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          task_id INTEGER NOT NULL,
          day INTEGER NOT NULL,
          kind INTEGER NOT NULL DEFAULT 1,
          new_at INTEGER)''');
        await db.execute('''CREATE TABLE checkin(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          task_id INTEGER NOT NULL,
          day INTEGER NOT NULL,
          at INTEGER NOT NULL)''');
        await db.execute('''CREATE TABLE review(
          day INTEGER PRIMARY KEY,
          mood INTEGER NOT NULL DEFAULT 0,
          text TEXT NOT NULL DEFAULT '',
          updated_at INTEGER NOT NULL)''');
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
        if (oldV < 4) {
          const cols = [
            'ALTER TABLE task ADD COLUMN repeat_interval INTEGER NOT NULL DEFAULT 1',
            'ALTER TABLE task ADD COLUMN repeat_anchor INTEGER',
          ];
          for (final c in cols) {
            await tryExec(c);
          }
        }
        if (oldV < 5) {
          const sqls = [
            '''CREATE TABLE IF NOT EXISTS task_exception(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              task_id INTEGER NOT NULL,
              day INTEGER NOT NULL,
              kind INTEGER NOT NULL DEFAULT 1,
              new_at INTEGER)''',
            '''CREATE TABLE IF NOT EXISTS checkin(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              task_id INTEGER NOT NULL,
              day INTEGER NOT NULL,
              at INTEGER NOT NULL)''',
            '''CREATE TABLE IF NOT EXISTS review(
              day INTEGER PRIMARY KEY,
              mood INTEGER NOT NULL DEFAULT 0,
              text TEXT NOT NULL DEFAULT '',
              updated_at INTEGER NOT NULL)''',
          ];
          for (final c in sqls) {
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
    final list = rows.map(Task.fromMap).toList();
    // 单次例外单独一张表，一次全捞出来按 task_id 挂回去，
    // 免得每条任务再查一次库。
    final exRows = await db.query('task_exception');
    if (exRows.isNotEmpty) {
      final byTask = <int, List<TaskException>>{};
      for (final r in exRows) {
        final e = TaskException.fromMap(r);
        byTask.putIfAbsent(e.taskId, () => <TaskException>[]).add(e);
      }
      for (final t in list) {
        if (t.id != null) t.exceptions = byTask[t.id!] ?? <TaskException>[];
      }
    }
    return list;
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
    final db = await _open();
    if (t.done) {
      t.done = false;
      // 取消勾选：把最近一条打卡记录撤掉，别让打卡日历虚高
      if (t.id != null) {
        final rows = await db.query('checkin',
            where: 'task_id=?', whereArgs: [t.id], orderBy: 'at DESC', limit: 1);
        if (rows.isNotEmpty) {
          await db.delete('checkin', where: 'id=?', whereArgs: [rows.first['id']]);
        }
      }
    } else {
      final today = dayKeyOf(DateTime.now());
      // 同一天只算一次：重复计划打完卡后 done 会被重新置 false，
      // 这时候再点一下就会被当成「又打了一次」，不拦住的话
      // 流水会虚高、startAt 还会被连续往后推好几次。
      if (t.id != null) {
        final dup = await db.query('checkin',
            where: 'task_id=? AND day=?',
            whereArgs: [t.id, today],
            limit: 1);
        if (dup.isNotEmpty) return;
      }
      t.advanceAfterDone();
      // 打卡流水：复盘页的「连续 N 天」「这周几次」都靠它
      if (t.id != null) {
        await db.insert('checkin', {
          'task_id': t.id,
          'day': today,
          'at': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }
    await saveTask(t);
  }

  // ── 单次例外（跳过某一次 / 这一次改时间） ──────────────
  /// 同一天同一任务只留一条，后写的覆盖先写的
  Future<void> saveException(TaskException e) async {
    final db = await _open();
    final exist = await db.query('task_exception',
        where: 'task_id=? AND day=?',
        whereArgs: [e.taskId, e.day],
        limit: 1);
    if (exist.isEmpty) {
      await db.insert('task_exception', e.toMap());
    } else {
      final m = e.toMap()..remove('id');
      await db.update('task_exception', m,
          where: 'id=?', whereArgs: [exist.first['id']]);
    }
  }

  /// 撤掉某一天的例外，恢复成规则原本的样子
  Future<void> deleteException(int taskId, int day) async {
    final db = await _open();
    await db.delete('task_exception',
        where: 'task_id=? AND day=?', whereArgs: [taskId, day]);
  }

  Future<List<TaskException>> exceptionsOf(int taskId) async {
    final db = await _open();
    final rows = await db.query('task_exception',
        where: 'task_id=?', whereArgs: [taskId], orderBy: 'day ASC');
    return rows.map(TaskException.fromMap).toList();
  }

  // ── 打卡流水 ──────────────────────────────────────
  /// [sinceDay] 之后的打卡记录（yyyyMMdd）；不传就是全部
  Future<List<Map<String, Object?>>> checkins({int? sinceDay}) async {
    final db = await _open();
    return db.query('checkin',
        where: sinceDay == null ? null : 'day>=?',
        whereArgs: sinceDay == null ? null : [sinceDay],
        orderBy: 'at ASC');
  }

  /// 某一天打过几次卡
  Future<int> checkinCountOn(int day) async {
    final db = await _open();
    final r = await db
        .rawQuery('SELECT COUNT(*) AS n FROM checkin WHERE day=?', [day]);
    return (r.first['n'] as int?) ?? 0;
  }

  /// 某任务累计打卡次数（以流水为准，比 done_count 更准）
  Future<Map<int, int>> checkinTotals() async {
    final db = await _open();
    final rows = await db
        .rawQuery('SELECT task_id, COUNT(*) AS n FROM checkin GROUP BY task_id');
    final out = <int, int>{};
    for (final r in rows) {
      out[(r['task_id'] as int?) ?? 0] = (r['n'] as int?) ?? 0;
    }
    return out;
  }

  // ── 每日复盘 ──────────────────────────────────────
  static const moodIcons = ['😞', '😐', '🙂', '😄', '🤩'];

  Future<Map<String, Object?>?> reviewOf(int day) async {
    final db = await _open();
    final rows = await db
        .query('review', where: 'day=?', whereArgs: [day], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveReview({
    required int day,
    required int mood,
    required String text,
  }) async {
    final db = await _open();
    await db.insert(
      'review',
      {
        'day': day,
        'mood': mood,
        'text': text,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> reviews({int limit = 14}) async {
    final db = await _open();
    return db.query('review', orderBy: 'day DESC', limit: limit);
  }

  Future<void> deleteTask(int id) async {
    final db = await _open();
    await db.delete('task', where: 'id=?', whereArgs: [id]);
    // 例外和打卡流水跟着走，别在库里留孤儿行
    await db.delete('task_exception', where: 'task_id=?', whereArgs: [id]);
    await db.delete('checkin', where: 'task_id=?', whereArgs: [id]);
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
    // 新增的三张表也要一起清，否则「清空数据」后会残留幽灵打卡
    await db.delete('task_exception');
    await db.delete('checkin');
    await db.delete('review');
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
      'task_exceptions': await db.query('task_exception'),
      'checkins': await db.query('checkin'),
      'reviews': await db.query('review'),
    };
  }

  /// 覆盖式写入（恢复备份）。整个过程放在一个事务里，
  /// 中途出错就整体回滚，不会出现「清空了但没写进去」的空库。
  Future<void> replaceAll({
    required List<Map<String, Object?>> lessons,
    required List<Map<String, Object?>> overrides,
    required List<Map<String, Object?>> tasks,
    required Map<String, String> settings,
    List<Map<String, Object?>> taskExceptions = const [],
    List<Map<String, Object?>> checkins = const [],
    List<Map<String, Object?>> reviews = const [],
  }) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn.delete('lesson');
      await txn.delete('lesson_override');
      await txn.delete('task');
      await txn.delete('setting');
      await txn.delete('task_exception');
      await txn.delete('checkin');
      await txn.delete('review');
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
      for (final m in taskExceptions) {
        await txn.insert('task_exception', m,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final m in checkins) {
        await txn.insert('checkin', m,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final m in reviews) {
        await txn.insert('review', m,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final e in settings.entries) {
        await txn.insert('setting', {'key': e.key, 'value': e.value},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}