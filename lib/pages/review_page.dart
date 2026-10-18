import 'dart:async';

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../models.dart';
import '../responsive.dart';
import '../theme.dart';

/// 打卡与复盘。
///
/// 打卡：今天该做的计划点一下就记一次（写 checkin 流水），
/// 复盘：每天留一句 + 一个心情，攒着看这段时间到底怎么过的。
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  bool _loading = true;
  List<Task> _tasks = const [];
  List<Map<String, Object?>> _checkins = const [];
  List<Map<String, Object?>> _reviews = const [];

  int _streak = 0;
  int _weekCount = 0;
  int _totalCount = 0;

  // 复盘草稿
  int _mood = 3;
  final _ctrl = TextEditingController();
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int get _todayKey => dayKeyOf(DateTime.now());

  Future<void> _load() async {
    final tasks = await DB.i.tasks();
    // 全部流水：热力格只画最近 30 天，但「累计次数」要的是历史总量
    final checkins = await DB.i.checkins();
    final reviews = await DB.i.reviews(limit: 20);
    final todayReview = await DB.i.reviewOf(_todayKey);
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _checkins = checkins;
      _reviews = reviews;
      _loading = false;
      _computeStats();
      if (!_dirty) {
        _mood = (todayReview?['mood'] as int?) ?? 3;
        _ctrl.text = (todayReview?['text'] ?? '') as String;
      }
    });
  }

  /// 连续天数 / 本周次数 / 累计次数
  void _computeStats() {
    final days = <int>{};
    for (final r in _checkins) {
      days.add((r['day'] as int?) ?? 0);
    }
    _totalCount = _checkins.length;
    // 本周（周一起算）
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final mondayKey = dayKeyOf(monday);
    _weekCount =
        _checkins.where((r) => ((r['day'] as int?) ?? 0) >= mondayKey).length;
    // 连续天数：今天没打卡就从昨天往回算，别因为「今天还没开始」就断掉
    final cursor = days.contains(_todayKey)
        ? DateTime(now.year, now.month, now.day)
        : DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 1));
    var n = 0;
    var d = cursor;
    while (days.contains(dayKeyOf(d))) {
      n++;
      d = d.subtract(const Duration(days: 1));
      if (n > 999) break;
    }
    _streak = n;
  }

  /// 今天该打卡的：重复任务按规则展开到今天，普通任务看今天有没有排
  List<Task> get _todayList {
    final now = DateTime.now();
    final out = <Task>[];
    for (final t in _tasks) {
      if (t.id == null) continue;
      final doneToday = _isDoneToday(t);
      if (t.isRepeating) {
        if (doneToday || t.occurrenceOn(now) != null) out.add(t);
      } else if (!t.done && t.startDt != null && sameDay(t.startDt!, now)) {
        out.add(t);
      } else if (doneToday) {
        out.add(t);
      }
    }
    // 没打的排前面
    out.sort((a, b) {
      final da = _isDoneToday(a) ? 1 : 0;
      final db = _isDoneToday(b) ? 1 : 0;
      if (da != db) return da.compareTo(db);
      final oa = a.occurrenceOn(now);
      final ob = b.occurrenceOn(now);
      if (oa != null && ob != null) return oa.compareTo(ob);
      return oa == null ? 1 : -1;
    });
    return out;
  }

  bool _isDoneToday(Task t) {
    if (t.lastDone == null) return false;
    final d = DateTime.fromMillisecondsSinceEpoch(t.lastDone!);
    return sameDay(d, DateTime.now());
  }

  Future<void> _toggle(Task t) async {
    // 重复计划打完卡后 done 会被推进到下一次（重新变回 false），
    // 所以这里只能靠 lastDone 判断「今天是不是已经打过了」。
    if (_isDoneToday(t)) {
      _toast('「${t.title}」今天已经打过卡了');
      return;
    }
    await DB.i.toggleTask(t);
    await _load();
    if (!mounted) return;
    _toast('已打卡「${t.title}」');
  }

  Future<void> _saveReview() async {
    if (_saving) return;
    setState(() => _saving = true);
    await DB.i.saveReview(day: _todayKey, mood: _mood, text: _ctrl.text.trim());
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
    });
    await _load();
    if (!mounted) return;
    _toast('复盘已保存');
  }

  void _toast(String msg) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.clearSnackBars();
    m?.showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(milliseconds: 1500),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final wide = isWideScreen(context);
    final now = DateTime.now();
    final list = _todayList;

    final stats = Row(
      children: [
        _statBox('连续', '$_streak 天', Icons.local_fire_department_rounded, kWarn),
        SizedBox(width: 10),
        _statBox('本周', '$_weekCount 次', Icons.date_range_rounded, kAcc),
        SizedBox(width: 10),
        _statBox('累计', '$_totalCount 次', Icons.emoji_events_outlined, kOk),
      ],
    );

    final checkinCard = _card(
      '今天打卡',
      subtitle: '${now.month} 月 ${now.day} 日 · 点一下记一次',
      child: list.isEmpty
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('今天没有排定的计划，休息一下也不错。',
                  style: TextStyle(fontSize: 12.5, color: kFaint)),
            )
          : Column(
              children: [for (final t in list) _checkRow(t, now)],
            ),
    );

    final heat = _card(
      '最近 30 天',
      subtitle: '颜色越深，那天打的卡越多',
      child: _heatGrid(now),
    );

    final reviewCard = _card(
      '今天复盘',
      subtitle: '写一句话就够，攒下来回头看很有用',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < 5; i++)
                GestureDetector(
                  onTap: () => setState(() {
                    _mood = i + 1;
                    _dirty = true;
                  }),
                  child: Container(
                    margin: EdgeInsets.only(right: 8),
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: _mood == i + 1
                          ? kAcc.withValues(alpha: 0.16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: _mood == i + 1 ? kAcc : kLine),
                    ),
                    child: Text(DB.moodIcons[i], style: TextStyle(fontSize: 16)),
                  ),
                ),
            ],
          ),
          SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            minLines: 3,
            maxLines: 8,
            onChanged: (_) {
              if (!_dirty) setState(() => _dirty = true);
            },
            style: TextStyle(fontSize: 13.5, height: 1.55),
            decoration: InputDecoration(
              hintText: '今天做了什么 / 哪里卡住了 / 明天怎么改',
              hintStyle: TextStyle(fontSize: 12.5, color: kFaint),
              filled: true,
              fillColor: kCard.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: kLine),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: kLine),
              ),
            ),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Text(_dirty ? '还没保存' : '今天已保存',
                  style: TextStyle(fontSize: 11.5, color: kFaint)),
              Spacer(),
              FilledButton(
                onPressed: _saving ? null : _saveReview,
                child: Text(_saving ? '保存中…' : '保存复盘'),
              ),
            ],
          ),
        ],
      ),
    );

    final history = _card(
      '最近复盘',
      subtitle: _reviews.isEmpty ? '还是一条都没有' : '点开能看到当天的全文',
      child: _reviews.isEmpty
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('坚持几天再回来看，这里会攒出一串。',
                  style: TextStyle(fontSize: 12.5, color: kFaint)),
            )
          : Column(
              children: [
                for (final r in _reviews)
                  _reviewRow(
                    (r['day'] as int?) ?? 0,
                    (r['mood'] as int?) ?? 3,
                    '${r['text'] ?? ''}',
                  ),
              ],
            ),
    );

    final content = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(children: [
                  stats,
                  SizedBox(height: 12),
                  checkinCard,
                  SizedBox(height: 12),
                  heat,
                ]),
              ),
              SizedBox(width: 14),
              Expanded(
                flex: 5,
                child: Column(children: [
                  reviewCard,
                  SizedBox(height: 12),
                  history,
                ]),
              ),
            ],
          )
        : Column(
            children: [
              stats,
              SizedBox(height: 12),
              checkinCard,
              SizedBox(height: 12),
              reviewCard,
              SizedBox(height: 12),
              heat,
              SizedBox(height: 12),
              history,
            ],
          );

    return ListView(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 26),
      children: [
        Row(
          children: [
            Icon(Icons.local_fire_department_rounded, size: 20, color: kWarn),
            SizedBox(width: 8),
            Text('打卡与复盘',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        SizedBox(height: 12),
        content,
      ],
    );
  }

  Widget _checkRow(Task t, DateTime now) {
    final done = _isDoneToday(t);
    final c = t.subject.isEmpty ? kDim : colorForSubject(t.subject);
    final at = t.occurrenceOn(now);
    final when = at == null
        ? ''
        : '${at.hour.toString().padLeft(2, '0')}:'
            '${at.minute.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: () => _toggle(t),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 22,
              color: done ? kOk : kFaint,
            ),
            SizedBox(width: 10),
            Container(
              width: 3,
              height: 22,
              margin: EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                  color: done ? kLine : c,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: Text(
                t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: done ? kDim : null,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (when.isNotEmpty)
              Text(when, style: TextStyle(fontSize: 11.5, color: kFaint)),
            SizedBox(width: 6),
            if (done)
              Text('已打卡', style: TextStyle(fontSize: 11, color: kOk))
            else if (t.doneCount > 0)
              Text('累计 ${t.doneCount}',
                  style: TextStyle(fontSize: 11, color: kFaint)),
          ],
        ),
      ),
    );
  }

  /// 最近 30 天的热力格（7 列一行，周一起算）
  Widget _heatGrid(DateTime now) {
    final counts = <int, int>{};
    for (final r in _checkins) {
      final k = (r['day'] as int?) ?? 0;
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: 29 + (today.weekday - 1)));
    // 一行一周，从周一到周日；末尾超出的位置留空
    final rows = <Widget>[];
    for (var w = 0; w < 5; w++) {
      final cells = <Widget>[];
      for (var i = 0; i < 7; i++) {
        final d = start.add(Duration(days: w * 7 + i));
        if (d.isAfter(today)) {
          cells.add(SizedBox(width: 16, height: 16));
          continue;
        }
        final n = counts[dayKeyOf(d)] ?? 0;
        final color = n == 0
            ? kLine.withValues(alpha: 0.35)
            : n == 1
                ? kAcc.withValues(alpha: 0.35)
                : n <= 2
                    ? kAcc.withValues(alpha: 0.6)
                    : kAcc;
        cells.add(Container(
          width: 16,
          height: 16,
          margin: EdgeInsets.only(right: 4, bottom: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ));
      }
      rows.add(Row(children: cells));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...rows,
        SizedBox(height: 4),
        Row(
          children: [
            Text('少', style: TextStyle(fontSize: 10.5, color: kFaint)),
            SizedBox(width: 6),
            for (final a in [0.35, 0.6, 1.0])
              Container(
                width: 12,
                height: 12,
                margin: EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: kAcc.withValues(alpha: a),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            Text('多', style: TextStyle(fontSize: 10.5, color: kFaint)),
          ],
        ),
      ],
    );
  }

  Widget _reviewRow(int day, int mood, String text) {
    final d = day == 0 ? null : dayOfKey(day);
    final title = d == null ? '—' : '${d.month} 月 ${d.day} 日 周${_wd(d.weekday)}';
    final emoji = (mood >= 1 && mood <= 5) ? DB.moodIcons[mood - 1] : '🙂';
    if (text.isEmpty) {
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Text(emoji, style: TextStyle(fontSize: 16)),
        title: Text(title, style: TextStyle(fontSize: 12.5, color: kDim)),
        subtitle: Text('只有心情，没写字',
            style: TextStyle(fontSize: 11, color: kFaint)),
      );
    }
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Text(emoji, style: TextStyle(fontSize: 16)),
      title: Text(title, style: TextStyle(fontSize: 12.5, color: kDim)),
      subtitle: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.5, height: 1.5),
      ),
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title, style: TextStyle(fontSize: 14.5)),
          content: SingleChildScrollView(
            child: Text(text, style: TextStyle(fontSize: 13, height: 1.6)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('关闭')),
          ],
        ),
      ),
    );
  }

  static String _wd(int w) =>
      const ['一', '二', '三', '四', '五', '六', '日'][(w >= 1 && w <= 7) ? w - 1 : 0];

  Widget _card(String title, {String? subtitle, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: kCard.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            SizedBox(height: 3),
            Text(subtitle,
                style: TextStyle(fontSize: 11.5, color: kFaint, height: 1.4)),
          ],
          SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, IconData icon, Color c) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: kCard.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: c),
                SizedBox(width: 5),
                Text(label, style: TextStyle(fontSize: 11, color: kFaint)),
              ],
            ),
            SizedBox(height: 5),
            Text(value,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, color: kFg)),
          ],
        ),
      ),
    );
  }
}