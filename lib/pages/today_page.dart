import 'package:flutter/material.dart';

import '../data/db.dart';
import '../models.dart';
import '../theme.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  static const List<String> _cn = ['一', '二', '三', '四', '五', '六', '日'];

  int _week = 1;
  List<Lesson> _lessons = [];
  List<Task> _tasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await DB.i.weekNo();
    final l = await DB.i.lessons();
    final t = await DB.i.tasks();
    if (!mounted) return;
    setState(() {
      _week = w;
      _lessons = l;
      _tasks = t;
      _loading = false;
    });
  }

  int get _wd => DateTime.now().weekday;

  /// 今天第 p 节的课
  Lesson? _todayLesson(int p) {
    final list = _lessons.where((l) => l.weekday == _wd && l.period == p);
    if (list.isEmpty) return null;
    final spec = list.where((l) => l.weekType != 0 && l.matchesWeek(_week));
    if (spec.isNotEmpty) return spec.first;
    final every = list.where((l) => l.weekType == 0);
    return every.isEmpty ? null : every.first;
  }

  Future<void> _toggle(Task t) async {
    t.done = !t.done;
    await DB.i.saveTask(t);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final now = DateTime.now();
    final classes = <MapEntry<int, Lesson>>[];
    for (var p = 1; p <= 12; p++) {
      final l = _todayLesson(p);
      if (l != null) classes.add(MapEntry(p, l));
    }
    final todo = _tasks.where((t) => !t.done).toList();
    final doneCount = _tasks.length - todo.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${now.month} 月 ${now.day} 日',
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('星期${_cn[now.weekday - 1]} · 第 $_week 周',
                  style: const TextStyle(fontSize: 13, color: kDim)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _stat('今日课程', '${classes.length} 节')),
            const SizedBox(width: 10),
            Expanded(
                child: _stat('待完成', '${todo.length} 项')),
            const SizedBox(width: 10),
            Expanded(
                child: _stat('已完成', '$doneCount 项')),
          ],
        ),
        const SizedBox(height: 18),
        _sectionTitle('今日课程', '周${_cn[_wd - 1]}'),
        const SizedBox(height: 8),
        if (classes.isEmpty)
          _empty('今天没有课，休息一下 🎉')
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < classes.length; i++) ...[
                  Builder(builder: (ctx) {
                    final p = classes[i].key;
                    final l = classes[i].value;
                    final c = Color(l.color);
                    return ListTile(
                      dense: true,
                      leading: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text('$p',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: c)),
                      ),
                      title: Text(l.subject,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      subtitle: (l.room.isEmpty && l.teacher.isEmpty)
                          ? null
                          : Text(
                              [
                                if (l.room.isNotEmpty) l.room,
                                if (l.teacher.isNotEmpty) l.teacher,
                              ].join(' · '),
                              style: const TextStyle(fontSize: 12),
                            ),
                      trailing: l.weekType == 0
                          ? null
                          : Text(l.weekLabel,
                              style: const TextStyle(fontSize: 11, color: kDim)),
                    );
                  }),
                  if (i != classes.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        const SizedBox(height: 18),
        _sectionTitle('待办', '点一下勾掉'),
        const SizedBox(height: 8),
        if (todo.isEmpty)
          _empty('全部完成，漂亮 ✨')
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < (todo.length > 6 ? 6 : todo.length); i++) ...[
                  ListTile(
                    dense: true,
                    leading: Checkbox(
                      value: false,
                      onChanged: (_) => _toggle(todo[i]),
                    ),
                    title: Text(todo[i].title,
                        style: const TextStyle(fontSize: 15)),
                    subtitle: todo[i].dueAt == null
                        ? null
                        : Text(
                            _dueText(todo[i]),
                            style: TextStyle(
                              fontSize: 12,
                              color: todo[i].overdue ? kBad : kDim,
                            ),
                          ),
                  ),
                  if (i != (todo.length > 6 ? 6 : todo.length) - 1)
                    const Divider(height: 1),
                ],
              ],
            ),
          ),
        const SizedBox(height: 24),
        const Center(
          child: Text('数据全在本机 · 不联网',
              style: TextStyle(fontSize: 11, color: Color(0xFF5C6474))),
        ),
      ],
    );
  }

  static const Color kBad = Color(0xFFFF5D6C);

  String _dueText(Task t) {
    final d = DateTime.fromMillisecondsSinceEpoch(t.dueAt!);
    final s = '${d.month}/${d.day} ${d.hour.toString().padLeft(2, "0")}:'
        '${d.minute.toString().padLeft(2, "0")}';
    return t.overdue ? '已逾期 · $s' : '截止 $s';
  }

  Widget _sectionTitle(String a, String b) => Row(
        children: [
          Text(a,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text(b, style: const TextStyle(fontSize: 12, color: kDim)),
        ],
      );

  Widget _empty(String s) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 26),
          child: Center(
            child: Text(s, style: const TextStyle(fontSize: 14, color: kDim)),
          ),
        ),
      );

  Widget _stat(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: kDim)),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
