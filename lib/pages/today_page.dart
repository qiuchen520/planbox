import 'package:flutter/material.dart';

import '../data/db.dart';
import '../models.dart';
import '../palette.dart';
import '../responsive.dart';
import '../theme.dart';

class _Slot {
  final int period;
  final String subject;
  final String room;
  final Color color;
  final bool cancelled;
  _Slot(this.period, this.subject, this.room, this.color, this.cancelled);
}

/// 时间轴上的一个条目，用来做统一排序
class _Tl {
  final int min;
  final int order;
  final Widget w;
  _Tl(this.min, this.order, this.w);
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
    Pal.rev.addListener(_onPalette);
    _load();
  }

  void _onPalette() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    Pal.rev.removeListener(_onPalette);
    super.dispose();
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
      final active = cands.where((l) => l.activeInWeek(_week)).toList()
        ..sort((a, b) =>
            (a.weekType == 0 ? 1 : 0).compareTo(b.weekType == 0 ? 1 : 0));
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
    final wasRepeat = t.repeatActive;
    await DB.i.toggleTask(t);
    await _load();
    if (wasRepeat && !t.done && t.startAt != null) {
      final d = DateTime.fromMillisecondsSinceEpoch(t.startAt!);
      _toast('已打卡 · 下次 ${d.month}/${d.day} '
          '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    m?.clearSnackBars();
    m?.showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(milliseconds: 1600),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;

    final slots = _todaySlots();
    final real = slots.where((s) => !s.cancelled).toList();

    // 今天到点的计划
    final timed = _tasks
        .where((t) => !t.done && t.inPool == 0 && t.startDt != null)
        .where((t) => sameDay(t.startDt!, now))
        .toList()
      ..sort((a, b) => a.startAt!.compareTo(b.startAt!));

    final overdue = _tasks.where((t) => !t.done && t.overdue).toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));

    final untimed = _tasks.where((t) => !t.done && t.startAt == null).toList();
    final pool = untimed.where((t) => t.inPool == 1).toList();
    final loose = untimed.where((t) => t.inPool != 1).toList();

    // 接下来 7 天（不含今天）
    final upcoming = _tasks
        .where((t) =>
            !t.done &&
            t.startDt != null &&
            dayOffsetFromToday(t.startDt!) > 0 &&
            dayOffsetFromToday(t.startDt!) <= 7)
        .toList()
      ..sort((a, b) => a.startAt!.compareTo(b.startAt!));

    final doneToday = _tasks
        .where((t) =>
            t.done &&
            t.lastDone != null &&
            sameDay(DateTime.fromMillisecondsSinceEpoch(t.lastDone!), now))
        .length;

    final lastEnd = real.isEmpty
        ? 0
        : real.map((s) => _pt[s.period - 1].endMin).reduce((a, b) => a > b ? a : b);
    final firstStart = real.isEmpty
        ? 0
        : real.map((s) => _pt[s.period - 1].startMin).reduce((a, b) => a < b ? a : b);

    final planMin = timed.fold<int>(0, (s, t) => s + t.estimate);
    final noEstimate = timed.where((t) => t.estimate == 0).length;

    final freeHint = _freeHint(real);
    final timeline = _timeline(slots, timed, lastEnd, nowMin);

    final head = <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${now.month} 月 ${now.day} 日',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
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
          Expanded(child: _stat('今日课程', '${real.length} 节', Icons.menu_book_outlined)),
          const SizedBox(width: 10),
          Expanded(
              child: _stat('放学到点',
                  lastEnd == 0 ? '—' : PeriodTime.hhmm(lastEnd), Icons.flag_outlined)),
          const SizedBox(width: 10),
          Expanded(
              child: _stat(
                  '计划用时',
                  planMin == 0 ? '—' : _mins(planMin),
                  Icons.timer_outlined)),
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
              Icon(Icons.auto_awesome, size: 16, color: kAcc),
              const SizedBox(width: 8),
              Expanded(
                child: Text(freeHint,
                    style: TextStyle(fontSize: 12.5, color: kAcc)),
              ),
            ],
          ),
        ),
      ],
      if (noEstimate > 0 && timed.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('有 $noEstimate 项计划还没估计用时，估一下才好安排晚上',
            style: const TextStyle(fontSize: 11, color: kFaint)),
      ],
      const SizedBox(height: 16),
    ];

    final foot = <Widget>[
      const SizedBox(height: 26),
      Center(
        child: Text(
          '共 ${real.length} 节课'
          '${firstStart != 0 ? " · 第一节 ${PeriodTime.hhmm(firstStart)}" : ""}'
          '${doneToday > 0 ? " · 今天已完成 $doneToday 项" : ""}',
          style: const TextStyle(fontSize: 11, color: kFaint),
        ),
      ),
    ];

    final timelineBody = <Widget>[
      if (timeline.isEmpty)
        _emptyCard('今天没有课，也没有安排计划\n到「计划」里排两件事吧')
      else
        ...timeline,
    ];

    final sideBody = <Widget>[
      if (overdue.isNotEmpty) ...[
        _sectionTitle('逾期了', '${overdue.length} 项', kDanger),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < overdue.length; i++) ...[
                _taskTile(overdue[i], overdueMode: true),
                if (i != overdue.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
      ],
      if (loose.isNotEmpty) ...[
        _sectionTitle('待办', '${loose.length} 项', kDim),
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
        const SizedBox(height: 18),
      ],
      if (upcoming.isNotEmpty) ...[
        _sectionTitle('接下来', '${upcoming.length} 项', kDim),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in upcoming.take(6))
              _miniChip(
                t: t,
                icon: Icons.event_outlined,
                label: '${_dayLabel(t.startDt!)} ${t.title}',
              ),
          ],
        ),
        if (upcoming.length > 6)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('还有 ${upcoming.length - 6} 项…',
                style: const TextStyle(fontSize: 11, color: kFaint)),
          ),
        const SizedBox(height: 18),
      ],
      if (pool.isNotEmpty) ...[
        _sectionTitle('计划池', '${pool.length} 项待安排', kDim),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in pool)
              _miniChip(
                t: t,
                icon: Icons.inbox_outlined,
                label: t.title,
              ),
          ],
        ),
      ],
      if (loose.isEmpty && pool.isEmpty && overdue.isEmpty)
        _emptyCard('没有待办\n空闲时间由你决定'),
    ];

    // 平板 / 横屏：左边时间轴，右边待办，两边各自滚动
    if (isWideScreen(context)) {
      return ContentWidth(
        maxWidth: 1400,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 10, 12, 24),
                children: [...head, ...timelineBody, ...foot],
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1, color: kLine),
            Expanded(
              flex: 2,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 22, 24),
                children: sideBody,
              ),
            ),
          ],
        ),
      );
    }

    return ContentWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        children: [...head, ...timelineBody, ...sideBody, ...foot],
      ),
    );
  }

  String _mins(int m) {
    if (m < 60) return '$m 分';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '$h 小时' : '$h时$r分';
  }

  String _dayLabel(DateTime d) {
    final off = dayOffsetFromToday(d);
    if (off == 1) return '明天';
    if (off == 2) return '后天';
    const cn = ['一', '二', '三', '四', '五', '六', '日'];
    if (off <= 7) return '周${cn[d.weekday - 1]}';
    return '${d.month}/${d.day}';
  }

  /// ≥2 小时的空档提示
  String? _freeHint(List<_Slot> real) {
    if (real.isEmpty) return null;
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
        return '${PeriodTime.hhmm(merged[i][1])} - '
            '${PeriodTime.hhmm(merged[i + 1][0])} 空闲 '
            '(${gap ~/ 60} 小时)，适合集中处理难题';
      }
    }
    if (merged.isNotEmpty && merged.last[1] <= 14 * 60) {
      return '${PeriodTime.hhmm(merged.last[1])} 之后没课，早点开始今天的计划';
    }
    return null;
  }

  /// 课程、今日计划、放学线按时间统一排序
  List<Widget> _timeline(
      List<_Slot> slots, List<Task> timed, int lastEnd, int nowMin) {
    final entries = <_Tl>[];
    var order = 0;

    for (final s in slots) {
      final pt = _pt[s.period - 1];
      final running = nowMin >= pt.startMin && nowMin <= pt.endMin;
      entries.add(_Tl(
        pt.startMin,
        order++,
        _tlRow(
          '${pt.s}-${pt.e}',
          s.subject,
          s.room,
          s.color,
          Icons.menu_book_outlined,
          strike: s.cancelled,
          highlight: running,
          tag: running ? '上课中' : null,
        ),
      ));
    }

    for (final t in timed) {
      final d = t.startDt!;
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      final sub = <String>[];
      if (t.subject.isNotEmpty) sub.add(t.subject);
      if (t.estimate > 0) sub.add(t.estimateLabel);
      if (t.subTotal > 0) sub.add('步骤 ${t.subDone}/${t.subTotal}');
      if (t.repeatActive) sub.add(t.repeatLabel);
      entries.add(_Tl(
        d.hour * 60 + d.minute,
        order++,
        _tlRow(
          '$hh:$mm',
          t.title,
          sub.join(' · '),
          t.subject.isEmpty ? kAcc : colorForSubject(t.subject),
          Icons.check_circle_outline,
          onTap: () => _toggle(t),
          badge: t.priority == 2 ? '重要' : null,
        ),
      ));
    }

    if (lastEnd > 0) {
      entries.add(_Tl(lastEnd, 9999, _schoolEndRow(lastEnd)));
    }

    entries.sort((a, b) =>
        a.min != b.min ? a.min.compareTo(b.min) : a.order.compareTo(b.order));
    return entries.map((e) => e.w).toList();
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
    String? badge,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
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
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: kDanger.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(badge,
                              style:
                                  const TextStyle(fontSize: 9.5, color: kDanger)),
                        ),
                      ],
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
            width: 62,
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
                      style: TextStyle(
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

  Widget _taskTile(Task t, {bool overdueMode = false}) {
    final c = t.subject.isEmpty ? kDim : colorForSubject(t.subject);
    final bits = <String>[];
    if (t.subject.isNotEmpty) bits.add(t.subject);
    if (t.estimate > 0) bits.add(t.estimateLabel);
    if (t.subTotal > 0) bits.add('${t.subDone}/${t.subTotal} 步');
    if (t.repeatActive) bits.add(t.repeatLabel);
    if (overdueMode && t.dueDt != null) {
      bits.add('逾期 ${t.dueDt!.month}/${t.dueDt!.day}');
    } else if (t.dueDt != null) {
      bits.add('截止 ${t.dueDt!.month}/${t.dueDt!.day}');
    }

    return InkWell(
      onTap: () => _toggle(t),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 9, 12, 9),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 30,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                  color: overdueMode ? kDanger : c,
                  borderRadius: BorderRadius.circular(3)),
            ),
            SizedBox(
              width: 28,
              height: 28,
              child: Checkbox(
                value: false,
                activeColor: kAcc,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) => _toggle(t),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, height: 1.25)),
                  if (bits.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(bits.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: overdueMode ? kDanger : kDim)),
                  ],
                  if (t.subTotal > 0) ...[
                    const SizedBox(height: 5),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: t.subProgress ?? 0,
                          minHeight: 3,
                          backgroundColor: kLine,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              t.subDone == t.subTotal ? kOk : c),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (t.priority == 2)
              const Icon(Icons.priority_high_rounded, size: 16, color: kDanger),
          ],
        ),
      ),
    );
  }

  Widget _miniChip({
    required Task t,
    required IconData icon,
    required String label,
  }) {
    final c = t.subject.isEmpty ? kDim : colorForSubject(t.subject);
    return ActionChip(
      avatar: Icon(icon, size: 15, color: c),
      label: Text(label,
          style: const TextStyle(fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      backgroundColor: kCard,
      side: const BorderSide(color: kLine),
      visualDensity: VisualDensity.compact,
      onPressed: () => _toggle(t),
    );
  }

  Widget _sectionTitle(String a, String b, Color c) => Row(
        children: [
          Text(a,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text(b, style: TextStyle(fontSize: 12, color: c)),
        ],
      );

  Widget _emptyCard(String s) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Center(
            child: Text(s,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: kDim, height: 1.6)),
          ),
        ),
      );

  Widget _stat(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 11),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: kDim),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: kDim)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
