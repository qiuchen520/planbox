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
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''CREATE TABLE lesson(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          weekday INTEGER NOT NULL,
          period INTEGER NOT NULL,
          subject TEXT NOT NULL,
          room TEXT,
          teacher TEXT,
          week_type INTEGER NOT NULL DEFAULT 0,
          color INTEGER NOT NULL DEFAULT 4284194815)''');
        await db.execute('''CREATE TABLE task(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          subject TEXT,
          due_at INTEGER,
          priority INTEGER NOT NULL DEFAULT 1,
          done INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL)''');
        await db.execute(
            'CREATE TABLE setting(key TEXT PRIMARY KEY, value TEXT)');
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

  /// 同一 (weekday, period, week_type) 视为同一格，存在则更新
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
      await db.update('lesson', l.toMap(),
          where: 'id=?', whereArgs: [exist.first['id']]);
    }
  }

  Future<void> deleteLesson(int id) async {
    final db = await _open();
    await db.delete('lesson', where: 'id=?', whereArgs: [id]);
  }

  Future<void> deleteLessonCell(int weekday, int period, int weekType) async {
    final db = await _open();
    await db.delete('lesson',
        where: 'weekday=? AND period=? AND week_type=?',
        whereArgs: [weekday, period, weekType]);
  }

  // ── 任务 ──────────────────────────────────────────
  Future<List<Task>> tasks() async {
    final db = await _open();
    final rows = await db.query('task',
        orderBy: 'done ASC, due_at IS NULL, due_at ASC, priority DESC');
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

  Future<int> weekNo() async =>
      int.tryParse(await getSetting('week_no') ?? '1') ?? 1;

  Future<void> setWeekNo(int v) => setSetting('week_no', '$v');

  Future<void> wipe() async {
    final db = await _open();
    await db.delete('lesson');
    await db.delete('task');
    await db.delete('setting');
  }
}
