import 'package:flutter/material.dart';

import '../data/db.dart';
import '../models.dart';
import '../theme.dart';

class _Slot {
  final int period;
  final String subject;
  final String room;
  final Color color;
  final bool cancelled;
  _Slot(this.period, this.subject, this.room, this.color, this.cancelled);
}

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  static const List<String> _cn = ['一', '二', '三', '四', '五', '六', '日'];

  int _week = 1;
  List<Lesson> _lessons = [];
  List<Override> _ovs = [];
  List<Task> _tasks = [];
  List<PeriodTime> _pt = kDefaultPeriodTimes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await DB.i.currentWeek();
    final l = await DB.i.lessons();
    final o = await DB.i.overrides();
    final t = await DB.i.tasks();
    final pt = await DB.i.periodTimes();
    if (!mounted) return;
    setState(() {
      _week = w;
      _lessons = l;
      _ovs = o;
      _tasks = t;
      _pt = pt;
      _loading = false;
    });
  }

  int get _wd => DateTime.now().weekday;

  Override? _ovFor(int? id) {
    if (id == null) return null;
    for (final o in _ovs) {
      if (o.lessonId == id && o.weekNo == _week) return o;
    }
    return null;
  }

  List<_Slot> _todaySlots() {
    final out = <_Slot>[];
    for (var p = 1; p <= _pt.length; p++) {
      final cands =
          _lessons.where((l) => l.weekday == _wd && l.period == p).toList();
      if (cands.isEmpty) continue;
      final active = cands.where((l) => l.activeInWeek(_week)).toList();
      if (active.isEmpty) continue;
      final base = active.first;
      final ov = _ovFor(base.id);
      if (ov != null && ov.cancelled) {
        out.add(_Slot(p, '${base.subject}（停课）', '', kDim, true));
        continue;
      }
      final s = (ov != null && ov.subject.isNotEmpty) ? ov.subject : base.subject;
      final r = (ov != null && ov.room.isNotEmpty) ? ov.room : base.room;
      out.add(_Slot(p, s, r, Color(base.color), false));
    }
    return out;
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
    final today = DateTime(now.year, now.month, now.day);
    final nowMin = now.hour * 60 + now.minute;

    final slots = _todaySlots();
    final real = slots.where((s) => !s.cancelled).toList();

    // 今日有时间点的计划
    final timed = _tasks
        .where((t) => !t.done && t.inPool == 0 && t.startDt != null)
        .where((t) {
      final d = t.startDt!;
      return d.year == today.year && d.month == today.month && d.day == today.day;
    }).toList();

    // 无时间点的待办（含计划池）
    final untimed = _tasks.where((t) => !t.done && t.startDt == null).toList();
    final pool = untimed.where((t) => t.inPool == 1).toList();
    final loose = untimed.where((t) => t.inPool != 1).toList();

    final doneCount = _tasks.where((t) => t.done).length;

    final lastEnd = real.isEmpty
        ? 0
        : real
            .map((s) => _pt[s.period - 1].endMin)
            .reduce((a, b) => a > b ? a : b);
    final firstStart = real.isEmpty
        ? 0
        : real
            .map((s) => _pt[s.period - 1].startMin)
            .reduce((a, b) => a < b ? a : b);

    // 找一段 >=2 小时的空档
    String? freeHint;
    if (real.isNotEmpty) {
      final blocks = <List<int>>[
        for (final s in real)
          [_pt[s.period - 1].startMin, _pt[s.period - 1].endMin]
      ]..sort((a, b) => a[0].compareTo(b[0]));
      final merged = <List<int>>[];
      for (final b in blocks) {
        if (merged.isNotEmpty && b[0] <= merged.last[1] + 15) {
          merged.last[1] = b[1] > merged.last[1] ? b[1] : merged.last[1];
        } else {
          merged.add([b[0], b[1]]);
        }
      }
      for (var i = 0; i < merged.length - 1; i++) {
        final gap = merged[i + 1][0] - merged[i][1];
        if (gap >= 120) {
          freeHint = '${PeriodTime.hhmm(merged[i][1])} - '
              '${PeriodTime.hhmm(merged[i + 1][0])} 空闲 '
              '(${gap ~/ 60} 小时)，适合集中处理难题';
          break;
        }
      }
      if (freeHint == null && merged.isNotEmpty && merged.last[1] <= 14 * 60) {
        freeHint = '${PeriodTime.hhmm(merged.last[1])} 之后没课，早点开始今天的计划';
      }
    }

    // 时间轴条目
    final items = <Widget>[];

    for (final s in slots) {
      final pt = _pt[s.period - 1];
      final running = nowMin >= pt.startMin && nowMin <= pt.endMin;
      items.add(_tlRow(
        '${pt.s}-${pt.e}',
        s.subject,
        s.room,
        s.color,
        Icons.menu_book_outlined,
        strike: s.cancelled,
        highlight: running,
        tag: running ? '上课中' : null,
      ));
    }

    // 放学线 + 计划
    final laterTasks = timed
        .where((t) => t.startDt!.hour * 60 + t.startDt!.minute >= lastEnd)
        .toList()
      ..sort((a, b) => a.startAt!.compareTo(b.startAt!));

    var schoolLineAdded = false;
    for (final t in laterTasks) {
      final d = t.startDt!;
      final m = d.hour * 60 + d.minute;
      if (!schoolLineAdded && real.isNotEmpty && m >= lastEnd) {
        items.add(_schoolEndRow(lastEnd));
        schoolLineAdded = true;
      }
      items.add(_tlRow(
        '${d.hour.toString().padLeft(2, '0')}:'
            '${d.minute.toString().padLeft(2, '0')}',
        t.title,
        _taskSub(t),
        t.subject.isEmpty ? kAcc : colorForSubject(t.subject),
        Icons.check_circle_outline,
        onTap: () => _toggle(t),
      ));
    }
    if (real.isNotEmpty && !schoolLineAdded) {
      items.add(_schoolEndRow(lastEnd));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
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
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _stat('今日课程', '${real.length} 节')),
            const SizedBox(width: 10),
            Expanded(
                child:
                    _stat('放学到点', lastEnd == 0 ? '—' : PeriodTime.hhmm(lastEnd))),
            const SizedBox(width: 10),
            Expanded(child: _stat('完成', '$doneCount 项')),
          ],
        ),
        if (freeHint != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: kAcc.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kAcc.withValues(alpha: 0.28)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 16, color: kAcc),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(freeHint,
                      style: const TextStyle(fontSize: 12.5, color: kAcc)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (items.isEmpty)
          _emptyCard('今天没有课，也没有带时间的计划\n可以到「计划」里排两件事')
        else
          ...items,
        if (loose.isNotEmpty) ...[
          const SizedBox(height: 10),
          _sectionTitle('待办', '${loose.length} 项'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < loose.length; i++) ...[
                  _taskTile(loose[i]),
                  if (i != loose.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        ],
        if (pool.isNotEmpty) ...[
          const SizedBox(height: 18),
          _sectionTitle('计划池', '${pool.length} 项待安排'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in pool)
                ActionChip(
                  avatar: Icon(Icons.inbox_outlined,
                      size: 15,
                      color:
                          t.subject.isEmpty ? kDim : colorForSubject(t.subject)),
                  label: Text(t.title, style: const TextStyle(fontSize: 12)),
                  onPressed: () => _toggle(t),
                ),
            ],
          ),
        ],
        const SizedBox(height: 26),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('共 ${real.length} 节课',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF5C6474))),
              const SizedBox(width: 8),
              if (firstStart != 0)
                Text('第一节 ${PeriodTime.hhmm(firstStart)}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF5C6474))),
            ],
          ),
        ),
      ],
    );
  }

  String _taskSub(Task t) {
    final parts = <String>[];
    if (t.subject.isNotEmpty) parts.add(t.subject);
    if (t.dueDt != null) {
      parts.add('截止 ${t.dueDt!.month}/${t.dueDt!.day} '
          '${t.dueDt!.hour.toString().padLeft(2, '0')}:'
          '${t.dueDt!.minute.toString().padLeft(2, '0')}');
    }
    return parts.join(' · ');
  }

  Widget _tlRow(
    String time,
    String title,
    String sub,
    Color color,
    IconData icon, {
    bool strike = false,
    bool highlight = false,
    String? tag,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(time,
                  style: TextStyle(
                      fontSize: 11,
                      color: highlight ? kAcc : kDim,
                      fontWeight:
                          highlight ? FontWeight.w700 : FontWeight.w400)),
            ),
          ),
          Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: highlight ? color : color.withValues(alpha: 0.55),
                  boxShadow: highlight
                      ? [
                          BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 8)
                        ]
                      : null,
                ),
              ),
              Container(width: 2, height: 40, color: kLine),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 14, color: color),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: strike ? kDim : null,
                            decoration:
                                strike ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (tag != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(tag,
                              style: TextStyle(fontSize: 10, color: color)),
                        ),
                      ],
                    ],
                  ),
                  if (sub.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 20, top: 2),
                      child: Text(sub,
                          style: const TextStyle(fontSize: 11, color: kDim)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _schoolEndRow(int minute) => Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(PeriodTime.hhmm(minute),
                style: const TextStyle(fontSize: 11, color: kDim)),
          ),
          const Icon(Icons.flag_outlined, size: 13, color: kAcc),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text('放学啦  ${PeriodTime.hhmm(minute)}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: kAcc,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  const Expanded(child: Divider(color: kLine, height: 1)),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _taskTile(Task t) => ListTile(
        dense: true,
        leading: Checkbox(
          value: false,
          activeColor: kAcc,
          onChanged: (_) => _toggle(t),
        ),
        title: Text(t.title, style: const TextStyle(fontSize: 14)),
        subtitle: t.dueDt == null
            ? null
            : Text(
                '${t.overdue ? "已逾期 · " : "截止 "}${t.dueDt!.month}/${t.dueDt!.day} '
                '${t.dueDt!.hour.toString().padLeft(2, '0')}:'
                '${t.dueDt!.minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                    fontSize: 11,
                    color: t.overdue ? const Color(0xFFFF5D6C) : kDim),
              ),
      );

  Widget _sectionTitle(String a, String b) => Row(
        children: [
          Text(a,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text(b, style: const TextStyle(fontSize: 12, color: kDim)),
        ],
      );

  Widget _emptyCard(String s) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
          child: Center(
            child: Text(s,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: kDim, height: 1.6)),
          ),
        ),
      );

  Widget _stat(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: kDim)),
            const SizedBox(height: 6),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
