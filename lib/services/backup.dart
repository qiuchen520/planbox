import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/db.dart';
import 'notify.dart';

/// 备份 / 导出 / 导入。
///
/// 文件就是一个 JSON：`{app, version, exportedAt, lessons, overrides, tasks, settings}`。
/// 不用 SQLite 文件本身，是因为 db 文件在不同版本的 schema 上可能不兼容，
/// 而 JSON 能带着「缺字段补默认值」的逻辑一起升级。
class Backup {
  Backup._();

  static const formatVersion = 1;

  static const _fileNameTag = 'planbox-backup';

  // ── 生成 ──────────────────────────────────────────
  static Future<Map<String, dynamic>> snapshot() async {
    final data = await DB.i.dumpAll();
    return {
      'app': 'planbox',
      'format': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      ...data,
    };
  }

  static String encode(Map<String, dynamic> m) =>
      const JsonEncoder.withIndent('  ').convert(m);

  static String stamp([DateTime? now]) {
    final d = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}-'
        '${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }

  static String defaultFileName([DateTime? now]) =>
      '$_fileNameTag-${stamp(now)}.json';

  /// 本机备份目录：Android/data/top.planbox/files/backups
  /// 用「应用私有外部目录」的原因：不用申请存储权限，用户又能用文件管理器找到。
  static Future<Directory> localDir() async {
    final base = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'backups'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 写一份到本机备份目录，返回文件
  static Future<File> writeLocal([Map<String, dynamic>? data]) async {
    final dir = await localDir();
    final map = data ?? await snapshot();
    final f = File(p.join(dir.path, defaultFileName()));
    await f.writeAsString(encode(map), flush: true);
    return f;
  }

  /// 列出本机备份（新的在前）
  static Future<List<File>> listLocal() async {
    final dir = await localDir();
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  // ── 导出 / 导入 ───────────────────────────────────
  /// 导出：先落一份文件，再拉起系统分享，用户可以存到网盘 / 发给自己
  static Future<File> exportAndShare() async {
    final f = await writeLocal();
    await Share.shareXFiles(
      [XFile(f.path, mimeType: 'application/json')],
      subject: 'PlanBox 备份 ${stamp()}',
      text: 'PlanBox 备份文件，重装后可在「我的 → 数据 → 从文件导入」恢复',
    );
    return f;
  }

  /// 从本机备份文件恢复
  static Future<int> restoreFromFile(File f) async {
    final raw = await f.readAsString();
    final data = jsonDecode(raw);
    if (data is! Map) throw const FormatException('备份文件格式不对');
    return restore(data.cast<String, dynamic>());
  }

  /// 让用户挑一个 json 文件，返回内容；用户取消则返回 null
  static Future<Map<String, dynamic>?> pickAndRead() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return null;
    final file = res.files.first;
    String raw;
    if (file.bytes != null) {
      raw = utf8.decode(file.bytes!, allowMalformed: true);
    } else if (file.path != null) {
      raw = await File(file.path!).readAsString();
    } else {
      throw const FormatException('读不到文件内容');
    }
    final data = jsonDecode(raw);
    if (data is! Map) throw const FormatException('不是 PlanBox 备份文件');
    return data.cast<String, dynamic>();
  }

  // ── 恢复 ──────────────────────────────────────────
  /// 覆盖式恢复：先清空现有数据，再写入备份内容。
  /// 返回恢复的计划条数（给界面报数用）。
  static Future<int> restore(Map<String, dynamic> data) async {
    if (data['app'] != null && data['app'] != 'planbox') {
      throw const FormatException('这不是 PlanBox 的备份');
    }
    final lessons = _rows(data['lessons']);
    final overrides = _rows(data['overrides']);
    final tasks = _rows(data['tasks']);
    final settings = <String, String>{};
    final raw = data['settings'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v != null) settings['$k'] = '$v';
      });
    }

    await DB.i.replaceAll(
      lessons: lessons,
      overrides: overrides,
      tasks: tasks,
      settings: settings,
    );

    // 恢复后通知配置变了，重新读一遍并整体排期
    await Notify.i.load();
    await Notify.i.resyncAll();
    return tasks.length;
  }

  static List<Map<String, Object?>> _rows(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => e.cast<String, Object?>())
        .toList();
  }
}