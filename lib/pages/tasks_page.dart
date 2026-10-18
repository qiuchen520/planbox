import 'package:flutter/material.dart';

import '../data/db.dart';
import '../models.dart';
import '../palette.dart';
import '../responsive.dart';
import '../theme.dart';
import 'focus_page.dart';

// ══════════════════════════════════════════════════════
// 筛选 / 排序 / 分组
// ══════════════════════════════════════════════════════

enum _F { all, today, week, overdue, pool, done }

enum _S { smart, priority, due, created }

enum _B { overdue, today, week, later, todo, pool, done }

_B _bucketOf(Task t) {
  if (t.done) return _B.done;
  if (t.inPool == 1) return _B.pool;
  if (t.overdue) return _B.overdue;
  final d = t.startDt ?? t.dueDt;
  if (d == null) return _B.todo;
  final off = dayOffsetFromToday(d);
  if (off <= 0) return _B.today;
  if (off <= 7) return _B.week;
  return _B.later;
}

Map<_B, String> _bucketTitle = {
  _B.overdue: '已逾期',
  _B.today: '今天',
  _B.week: '本周内',
  _B.later: '以后',
  _B.todo: '待办 · 没排时间',
  _B.pool: '计划池 · 有空再做',
  _B.done: '已完成',
};

class TasksPage extends StatefulWidget {
  TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final _quick = TextEditingController();
  final _search = TextEditingController();
  final _quickFocus = FocusNode();

  List<Task> _tasks = [];
  bool _loading = true;
  _F _f = _F.all;
  _S _s = _S.smart;
  bool _showSearch = false;
  bool _ascending = true;

  @override
  void initState() {
    super.initState();
    Pal.rev.addListener(_onPalette);
    _load();
  }

  void _onPalette() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Pal.rev.removeListener(_onPalette);
    _quick.dispose();
    _search.dispose();
    _quickFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final t = await DB.i.tasks();
    if (!mounted) return;
    setState(() {
      _tasks = t;
      _loading = false;
    });
  }

  // ── 提示 ───────────────────────────────────────────
  void _toast(String msg) {
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    m?.clearSnackBars();
    m?.showSnackBar(SnackBar(
      content: Text(msg),
      duration: Duration(milliseconds: 1800),
    ));
  }

  String _when(DateTime d) {
    final off = dayOffsetFromToday(d);
    String day;
    if (off == 0) {
      day = '今天';
    } else if (off == 1) {
      day = '明天';
    } else if (off == 2) {
      day = '后天';
    } else if (off == -1) {
      day = '昨天';
    } else if (off < 0) {
      day = '${-off} 天前';
    } else if (off <= 7) {
      const cn = ['一', '二', '三', '四', '五', '六', '日'];
      day = '周${cn[d.weekday - 1]}';
    } else {
      day = '${d.month}/${d.day}';
    }
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$day $hh:$mm';
  }

  // ── 勾选 ───────────────────────────────────────────
  /// 进番茄钟。点任务不等于完成 —— 只有专注页里确认过才写库。
  Future<void> _openFocus(Task t) async {
    final done = await FocusPage.open(context, t);
    if (!mounted || done != true) return;
    await _load();
    _toast('完成「${t.title}」');
  }

  Future<void> _toggle(Task t) async {
    final wasRepeat = t.repeatActive;
    await DB.i.toggleTask(t);
    await _load();
    if (wasRepeat && !t.done && t.startAt != null) {
      final d = DateTime.fromMillisecondsSinceEpoch(t.startAt!);
      _toast('已打卡 · 下次 ${_when(d)}');
    } else if (t.done) {
      _toast('完成「${t.title}」');
    }
  }

  // ── 快速添加 ───────────────────────────────────────
  /// 支持：#科目 @20:30 @今天 @明天 结尾 ! 表示高优先级
  Future<void> _quickAdd() async {
    var txt = _quick.text.trim();
    if (txt.isEmpty) return;

    var subject = '';
    var priority = 1;
    DateTime? start;

    final mSub = RegExp(r'#([^\s#@!]+)').firstMatch(txt);
    if (mSub != null) {
      subject = mSub.group(1)!;
      txt = txt.replaceRange(mSub.start, mSub.end, '');
    }

    final mTime = RegExp(r'@(\d{1,2})[:：](\d{2})').firstMatch(txt);
    if (mTime != null) {
      final h = int.tryParse(mTime.group(1)!) ?? -1;
      final mi = int.tryParse(mTime.group(2)!) ?? -1;
      if (h >= 0 && h <= 23 && mi >= 0 && mi <= 59) {
        final now = DateTime.now();
        var d = DateTime(now.year, now.month, now.day, h, mi);
        if (d.isBefore(now)) d = d.add(Duration(days: 1));
        start = d;
      }
      txt = txt.replaceRange(mTime.start, mTime.end, '');
    } else if (txt.contains('@明天')) {
      txt = txt.replaceAll('@明天', '');
      final n = DateTime.now().add(Duration(days: 1));
      start = DateTime(n.year, n.month, n.day, 20, 0);
    } else if (txt.contains('@今天')) {
      txt = txt.replaceAll('@今天', '');
      final n = DateTime.now();
      start = DateTime(n.year, n.month, n.day, 20, 0);
    }

    if (txt.endsWith('!')) {
      priority = 2;
      txt = txt.substring(0, txt.length - 1).trim();
    }

    txt = txt.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (txt.isEmpty) return;

    final t = Task(
      title: txt,
      subject: subject,
      priority: priority,
      startAt: start?.millisecondsSinceEpoch,
    );
    await DB.i.saveTask(t);
    _quick.clear();
    _quickFocus.requestFocus();
    await _load();
    _toast('已添加「${t.title}」');
  }

  // ── 编辑 / 新建 ────────────────────────────────────
  Future<void> _edit([Task? t]) async {
    final res = await showDialog<_Res>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TaskEditor(task: t),
    );
    if (res == null) return;
    if (res.deleted && t?.id != null) {
      await DB.i.deleteTask(t!.id!);
      await _load();
      _toast('已删除');
      return;
    }
    final out = res.task;
    if (out == null) return;
    await DB.i.saveTask(out);
    await _load();
  }

  Future<void> _quickMenu(Task t) async {
    final act = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: Icon(Icons.check_circle_outline),
              title: Text('标记完成'),
              onTap: () => Navigator.pop(ctx, 'done'),
            ),
            ListTile(
              leading: Icon(Icons.today_outlined),
              title: Text('挪到今天 20:00'),
              onTap: () => Navigator.pop(ctx, 'today'),
            ),
            ListTile(
              leading: Icon(Icons.inbox_outlined),
              title: Text('丢进计划池'),
              onTap: () => Navigator.pop(ctx, 'pool'),
            ),
            ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('编辑详情'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: kDanger),
              title: Text('删除', style: TextStyle(color: kDanger)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || act == null) return;
    switch (act) {
      case 'done':
        await _toggle(t);
        break;
      case 'today':
        final n = DateTime.now();
        t.startAt = DateTime(n.year, n.month, n.day, 20, 0)
            .millisecondsSinceEpoch;
        t.inPool = 0;
        await DB.i.saveTask(t);
        await _load();
        _toast('已挪到今天 20:00');
        break;
      case 'pool':
        t.inPool = 1;
        t.startAt = null;
        await DB.i.saveTask(t);
        await _load();
        _toast('已放进计划池');
        break;
      case 'edit':
        await _edit(t);
        break;
      case 'delete':
        if (t.id != null) await DB.i.deleteTask(t.id!);
        await _load();
        _toast('已删除');
        break;
    }
  }

  Future<void> _clearDone() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('清理已完成？'),
        content: Text('已完成的计划会被永久删除，重复类计划不受影响。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('清理')),
        ],
      ),
    );
    if (ok != true) return;
    final n = await DB.i.clearDoneTasks();
    await _load();
    _toast('清理了 $n 条');
  }

  // ── 过滤 + 排序 ────────────────────────────────────
  List<Task> _sorted(List<Task> src) {
    final list = List<Task>.from(src);
    list.sort((a, b) {
      if (_s == _S.priority) {
        final c = b.priority.compareTo(a.priority);
        if (c != 0) return c;
      }
      if (_s == _S.due) {
        final c = (a.dueAt ?? a.startAt ?? 1 << 62)
            .compareTo(b.dueAt ?? b.startAt ?? 1 << 62);
        if (c != 0) return _ascending ? c : -c;
      }
      if (_s == _S.created) {
        return b.createdAt.compareTo(a.createdAt);
      }
      // smart：先时间，再优先级
      final ta = a.startAt ?? a.dueAt ?? 1 << 62;
      final tb = b.startAt ?? b.dueAt ?? 1 << 62;
      if (ta != tb) return ta.compareTo(tb);
      final c = b.priority.compareTo(a.priority);
      if (c != 0) return c;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  bool _matchSearch(Task t) {
    final q = _search.text.trim();
    if (q.isEmpty) return true;
    return t.title.contains(q) ||
        t.subject.contains(q) ||
        t.note.contains(q);
  }

  List<Task> _forBucket(_B b) => _sorted(
      _tasks.where((t) => _bucketOf(t) == b && _matchSearch(t)).toList());

  // ── 构建 ───────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final undone = _tasks.where((t) => !t.done).toList();
    final overdue = undone.where((t) => t.overdue).length;
    final doneAll = _tasks.where((t) => t.done).length;

    final todayLoad = _tasks
        .where((t) => !t.done && _bucketOf(t) == _B.today && t.estimate > 0)
        .fold<int>(0, (s, t) => s + t.estimate);
    final weekLoad = _tasks
        .where((t) => !t.done && _bucketOf(t) == _B.week && t.estimate > 0)
        .fold<int>(0, (s, t) => s + t.estimate);
    final streaks = _tasks.fold<int>(0, (s, t) => s + t.doneCount);

    final List<_B> order;
    switch (_f) {
      case _F.all:
        order = [
          _B.overdue,
          _B.today,
          _B.week,
          _B.later,
          _B.todo,
          _B.pool,
        ];
        break;
      case _F.today:
        order = [_B.overdue, _B.today];
        break;
      case _F.week:
        order = [_B.overdue, _B.today, _B.week];
        break;
      case _F.overdue:
        order = [_B.overdue];
        break;
      case _F.pool:
        order = [_B.pool];
        break;
      case _F.done:
        order = [_B.done];
        break;
    }

    final body = <Widget>[];

    // 头部
    body.add(Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('计划',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        SizedBox(width: 10),
        Padding(
          padding: EdgeInsets.only(bottom: 3),
          child: Text('${undone.length} 项待做',
              style: TextStyle(fontSize: 13, color: kDim)),
        ),
        Spacer(),
        if (_showSearch)
          SizedBox(
            width: 200,
            height: 36,
            child: TextField(
              controller: _search,
              autofocus: true,
              style: TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜索标题 / 科目 / 备注',
                prefixIcon: Icon(Icons.search, size: 17),
                contentPadding: EdgeInsets.symmetric(horizontal: 10),
                suffixIcon: IconButton(
                  icon: Icon(Icons.close, size: 15),
                  onPressed: () {
                    _search.clear();
                    setState(() => _showSearch = false);
                  },
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          )
        else
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _showSearch = true),
            icon: Icon(Icons.search, size: 21, color: kDim),
            tooltip: '搜索',
          ),
      ],
    ));
    body.add(SizedBox(height: 14));

    // 统计
    body.add(Row(
      children: [
        Expanded(
            child: _StatCard(
                label: '今日待做',
                value: '${_tasks.where((t) => !t.done && _bucketOf(t) == _B.today).length} 项',
                color: kAcc)),
        SizedBox(width: 10),
        Expanded(
            child: _StatCard(
                label: '今天预计',
                value: todayLoad == 0 ? '—' : _mins(todayLoad),
                color: kWarn)),
        SizedBox(width: 10),
        Expanded(
            child: _StatCard(
                label: '本周预计',
                value: weekLoad == 0 ? '—' : _mins(weekLoad),
                color: kOk)),
        SizedBox(width: 10),
        Expanded(
            child: _StatCard(
                label: overdue > 0 ? '逾期 / 打卡' : '累计打卡',
                value: overdue > 0 ? '$overdue / $streaks' : '$streaks 次',
                color: overdue > 0 ? kDanger : kDim)),
      ],
    ));
    body.add(SizedBox(height: 14));

    // 快速添加
    body.add(Card(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 4, 6, 4),
        child: Row(
          children: [
            Icon(Icons.bolt, size: 18, color: kAcc),
            SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _quick,
                focusNode: _quickFocus,
                textInputAction: TextInputAction.done,
                style: TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: '一句话添加：#数学 卷子P32 @20:30',
                  hintStyle: TextStyle(fontSize: 13),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                onSubmitted: (_) => _quickAdd(),
              ),
            ),
            IconButton(
              onPressed: _quickAdd,
              icon: Icon(Icons.arrow_upward, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: kAcc.withValues(alpha: 0.16),
                foregroundColor: kAcc,
                visualDensity: VisualDensity.compact,
              ),
              tooltip: '添加',
            ),
          ],
        ),
      ),
    ));
    body.add(SizedBox(height: 10));

    // 筛选 + 排序
    body.add(SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in _F.values) ...[
            _FilterChip2(
              label: switch (f) {
                _F.all => '全部',
                _F.today => '今天',
                _F.week => '本周',
                _F.overdue => '逾期',
                _F.pool => '计划池',
                _F.done => '已完成',
              },
              selected: _f == f,
              count: switch (f) {
                _F.done => _tasks.where((t) => t.done).length,
                _F.pool => _tasks.where((t) => !t.done && t.inPool == 1).length,
                _F.overdue => overdue,
                _ => null,
              },
              onTap: () => setState(() => _f = f),
            ),
            SizedBox(width: 8),
          ],
          SizedBox(width: 4),
          PopupMenuButton<_S>(
            initialValue: _s,
            color: kCard2,
            tooltip: '排序',
            onSelected: (v) => setState(() => _s = v),
            itemBuilder: (ctx) => [
              PopupMenuItem(value: _S.smart, child: Text('智能排序')),
              PopupMenuItem(value: _S.priority, child: Text('按优先级')),
              PopupMenuItem(value: _S.due, child: Text('按截止时间')),
              PopupMenuItem(value: _S.created, child: Text('按创建时间')),
            ],
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kLine),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort, size: 15, color: kDim),
                  SizedBox(width: 5),
                  Text(
                    switch (_s) {
                      _S.smart => '智能',
                      _S.priority => '优先级',
                      _S.due => '截止',
                      _S.created => '创建',
                    },
                    style: TextStyle(fontSize: 12, color: kDim),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
    body.add(SizedBox(height: 16));

    // 分组列表
    var shown = 0;
    for (final b in order) {
      final items = _forBucket(b);
      if (items.isEmpty) continue;
      shown += items.length;
      body.add(Row(
        children: [
          Text(
            _bucketTitle[b]!,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: b == _B.overdue ? kDanger : kDim,
            ),
          ),
          SizedBox(width: 8),
          Text('${items.length}',
              style: TextStyle(fontSize: 12, color: kFaint)),
          Spacer(),
          if (b == _B.done && items.isNotEmpty)
            TextButton(
              onPressed: _clearDone,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: kDim,
                textStyle: TextStyle(fontSize: 12),
              ),
              child: Text('清理'),
            ),
        ],
      ));
      body.add(SizedBox(height: 8));
      body.add(Card(
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              _taskRow(items[i]),
              if (i != items.length - 1)
                Divider(height: 1, indent: 16, endIndent: 16),
            ],
          ],
        ),
      ));
      body.add(SizedBox(height: 18));
    }

    if (shown == 0) {
      body.add(Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.inbox_outlined,
                  size: 40, color: kDim.withValues(alpha: 0.6)),
              SizedBox(height: 10),
              Text(
                _search.text.isNotEmpty
                    ? '没有匹配「${_search.text}」的计划'
                    : (_f == _F.done ? '还没有完成的计划' : '这一栏是空的，休息一下'),
                style: TextStyle(fontSize: 13, color: kDim),
              ),
            ],
          ),
        ),
      ));
    } else {
      body.add(Center(
        child: Text('共 ${_tasks.length} 条计划 · 已完成 $doneAll',
            style: TextStyle(fontSize: 11, color: kFaint)),
      ));
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: Icon(Icons.add),
        label: Text('新建',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : ContentWidth(
              maxWidth: 860,
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 100),
                children: body,
              ),
            ),
    );
  }

  String _mins(int m) {
    if (m < 60) return '$m 分';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '$h 小时' : '$h时$r分';
  }

  // ── 一行计划 ───────────────────────────────────────
  Widget _taskRow(Task t) {
    final c = t.subject.isEmpty ? kDim : colorForSubject(t.subject);
    final tags = <Widget>[];

    final st = t.startDt;
    final du = t.dueDt;
    if (st != null) {
      tags.add(_Tag(icon: Icons.play_arrow_rounded, text: _when(st), color: c));
    }
    if (du != null) {
      tags.add(_Tag(
        icon: t.overdue ? Icons.error_outline : Icons.flag_outlined,
        text: '${t.overdue ? "逾期 " : "截止 "}${_when(du)}',
        color: t.overdue ? kDanger : kFaint,
      ));
    }
    if (t.estimate > 0) {
      tags.add(_Tag(
          icon: Icons.timer_outlined, text: t.estimateLabel, color: kFaint));
    }
    if (t.repeatActive) {
      tags.add(_Tag(
          icon: Icons.repeat_rounded, text: t.repeatLabel, color: kAcc));
    }
    if (t.subTotal > 0) {
      tags.add(_Tag(
        icon: Icons.checklist_rounded,
        text: '${t.subDone}/${t.subTotal}',
        color: t.subDone == t.subTotal ? kOk : kFaint,
      ));
    }
    if (t.doneCount > 1) {
      tags.add(_Tag(
          icon: Icons.local_fire_department_outlined,
          text: '${t.doneCount}',
          color: kWarn));
    }
    if (t.note.isNotEmpty) {
      tags.add(_Tag(icon: Icons.notes_rounded, text: '', color: kFaint));
    }

    return InkWell(
      onTap: () => _openFocus(t),
      onLongPress: () => _quickMenu(t),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: t.subTotal > 0 ? 52 : 34,
              margin: EdgeInsets.only(top: 3, right: 10),
              decoration: BoxDecoration(
                color: t.done ? kLine : c,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            SizedBox(
              width: 30,
              height: 30,
              child: Checkbox(
                value: t.done,
                activeColor: kAcc,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) => _toggle(t),
              ),
            ),
            SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          t.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: t.done ? kDim : null,
                            decoration: t.done
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      if (t.priority == 2) ...[
                        SizedBox(width: 6),
                        Icon(Icons.priority_high_rounded,
                            size: 15, color: kDanger),
                      ] else if (t.priority == 0) ...[
                        SizedBox(width: 6),
                        Icon(Icons.keyboard_arrow_down_rounded,
                            size: 15, color: kFaint),
                      ],
                    ],
                  ),
                  if (tags.isNotEmpty) ...[
                    SizedBox(height: 5),
                    Wrap(
                        spacing: 10, runSpacing: 3, children: tags),
                  ],
                  if (t.subTotal > 0) ...[
                    SizedBox(height: 6),
                    Padding(
                      padding: EdgeInsets.only(right: 8),
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
            Icon(Icons.chevron_right, size: 16, color: kFaint),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// 编辑弹窗
// ══════════════════════════════════════════════════════

class _Res {
  final Task? task;
  final bool deleted;
  _Res(this.task, {this.deleted = false});
}

class _TaskEditor extends StatefulWidget {
  final Task? task;
  _TaskEditor({this.task});

  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _subInput;

  late String _subject;
  late int _priority;
  late bool _inPool;
  late int _estimate;
  late int _repeatKind;
  late int _repeatDays;
  late int _repeatInterval;
  late List<Subtask> _subs;
  DateTime? _start;
  DateTime? _due;
  DateTime? _repeatUntil;

  bool get _isNew => widget.task == null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? '');
    _note = TextEditingController(text: t?.note ?? '');
    _subInput = TextEditingController();
    _subject = t?.subject ?? '';
    _priority = t?.priority ?? 1;
    _inPool = (t?.inPool ?? 0) == 1;
    _estimate = t?.estimate ?? 0;
    _repeatKind = t?.repeatKind ?? 0;
    _repeatDays = t?.repeatDays ?? 0;
    _repeatInterval = t?.repeatInterval ?? 1;
    _subs = (t?.subtasks ?? <Subtask>[])
        .map((s) => Subtask(s.title, s.done))
        .toList();
    _start = t?.startDt;
    _due = t?.dueDt;
    _repeatUntil = t?.repeatUntil == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(t!.repeatUntil!);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _subInput.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) {
    final off = dayOffsetFromToday(d);
    final day = off == 0
        ? '今天'
        : off == 1
            ? '明天'
            : '${d.month}/${d.day}';
    return '$day ${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  Future<DateTime?> _pickDateTime(DateTime? init) async {
    final d = await showDatePicker(
      context: context,
      initialDate: init ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (!mounted || d == null) return null;
    final t = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: init?.hour ?? 20, minute: init?.minute ?? 0),
    );
    if (!mounted) return null;
    return DateTime(d.year, d.month, d.day, t?.hour ?? 20, t?.minute ?? 0);
  }

  /// 重复锚点：新建时就是开始时间；改过的开始时间要跟着换锚点，
  /// 否则「每 2 周」会从旧的锚点算，日期看着对不上。
  String get _repeatUnitCn => switch (_repeatKind) {
        1 => '天',
        3 => '周',
        4 => '个月',
        5 => '年',
        _ => '',
      };
  int? _repeatAnchorOf(Task? base) {
    if (_inPool || _repeatKind == 0) return null;
    final start = _start?.millisecondsSinceEpoch;
    if (start == null) return base?.repeatAnchor;
    if (base == null) return start;
    if (base.startAt == start && base.repeatAnchor != null) {
      return base.repeatAnchor;
    }
    return start;
  }
  void _save() {
    final name = _title.text.trim();
    if (name.isEmpty) {
      setState(() {});
      return;
    }
    final base = widget.task;
    final t = base ?? Task(title: name);
    var mask = _repeatDays;
    if (_repeatKind == 3 && mask == 0 && _start != null) {
      mask = 1 << (_start!.weekday - 1);
    }
    t
      ..title = name
      ..subject = _subject
      ..note = _note.text.trim()
      ..priority = _priority
      ..inPool = _inPool ? 1 : 0
      ..estimate = _estimate
      ..startAt = _inPool ? null : _start?.millisecondsSinceEpoch
      ..dueAt = _due?.millisecondsSinceEpoch
      ..repeatKind = _inPool ? 0 : _repeatKind
      ..repeatDays = _repeatKind == 3 ? mask : 0
      ..repeatInterval = _repeatKind == 0 ? 1 : _repeatInterval
      ..repeatAnchor = _repeatAnchorOf(base)
      ..repeatUntil = _repeatKind == 0 ? null : _repeatUntil?.millisecondsSinceEpoch
      ..subtasks = _subs.where((s) => s.title.trim().isNotEmpty).toList();
    Navigator.pop(context, _Res(t));
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: h * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头部
            Padding(
              padding: EdgeInsets.fromLTRB(18, 14, 8, 6),
              child: Row(
                children: [
                  Text(_isNew ? '新建计划' : '编辑计划',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, size: 19),
                  ),
                ],
              ),
            ),
            Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    TextField(
                      controller: _title,
                      autofocus: _isNew,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        labelText: '要做什么',
                        hintText: '数学卷子 P32-35',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_isNew && _title.text.trim().isEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 4, left: 2),
                        child: Text('标题不能为空',
                            style: TextStyle(fontSize: 11, color: kDanger)),
                      ),
                    SizedBox(height: 16),

                    // 科目
                    _Label('科目', trailing: _subject.isEmpty ? null : '点击取消'),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in kSubjects)
                          _PickChip(
                            label: s,
                            selected: _subject == s,
                            color: colorForSubject(s),
                            onTap: () => setState(
                                () => _subject = _subject == s ? '' : s),
                          ),
                      ],
                    ),
                    SizedBox(height: 16),

                    // 优先级
                    _Label('优先级'),
                    SizedBox(height: 8),
                    SegmentedButton<int>(
                      segments: [
                        ButtonSegment(
                            value: 0,
                            label: Text('低'),
                            icon: Icon(Icons.south, size: 14)),
                        ButtonSegment(
                            value: 1,
                            label: Text('中'),
                            icon: Icon(Icons.remove, size: 14)),
                        ButtonSegment(
                            value: 2,
                            label: Text('高'),
                            icon: Icon(Icons.priority_high, size: 14)),
                      ],
                      selected: {_priority},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) =>
                          setState(() => _priority = s.first),
                    ),
                    SizedBox(height: 16),

                    // 时间
                    _Label('时间'),
                    SizedBox(height: 4),
                    _SwitchRow(
                      title: '放进计划池',
                      sub: '不排具体时间，有空再挑出来做',
                      value: _inPool,
                      onChanged: (v) => setState(() {
                        _inPool = v;
                        if (v) {
                          _start = null;
                          _repeatKind = 0;
                        }
                      }),
                    ),
                    if (!_inPool) ...[
                      _TimeRow(
                        icon: Icons.play_circle_outline,
                        label: '开始',
                        text: _start == null ? '未安排' : _fmt(_start!),
                        active: _start != null,
                        onPick: () async {
                          final d = await _pickDateTime(_start);
                          if (d != null) setState(() => _start = d);
                        },
                        onClear: _start == null
                            ? null
                            : () => setState(() {
                                  _start = null;
                                  _repeatKind = 0;
                                  _repeatUntil = null;
                                }),
                      ),
                      _TimeRow(
                        icon: Icons.flag_outlined,
                        label: '截止',
                        text: _due == null ? '未设置' : _fmt(_due!),
                        active: _due != null,
                        onPick: () async {
                          final d = await _pickDateTime(_due);
                          if (d != null) setState(() => _due = d);
                        },
                        onClear: _due == null
                            ? null
                            : () => setState(() => _due = null),
                      ),
                    ],
                    SizedBox(height: 16),

                    // 用时
                    _Label('预计用时',
                        trailing: _estimate == 0 ? null : '点一下取消'),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final m in [10, 15, 20, 30, 45, 60, 90, 120])
                          _PickChip(
                            label: m < 60 ? '$m 分' : '${m ~/ 60} 小时',
                            selected: _estimate == m,
                            color: kWarn,
                            onTap: () =>
                                setState(() => _estimate = _estimate == m ? 0 : m),
                          ),
                      ],
                    ),
                    SizedBox(height: 16),

                    // 重复
                    _Label('重复',
                        trailing: _start == null ? '需先设置开始时间' : null),
                    SizedBox(height: 8),
                    IgnorePointer(
                      ignoring: _inPool || _start == null,
                      child: Opacity(
                        opacity: (_inPool || _start == null) ? 0.45 : 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final e in const [
                                  MapEntry(0, '不重复'),
                                  MapEntry(1, '每天'),
                                  MapEntry(2, '工作日'),
                                  MapEntry(3, '每周'),
                                  MapEntry(4, '每月'),
                                  MapEntry(5, '每年'),
                                ])
                                  _PickChip(
                                    label: e.value,
                                    selected: _repeatKind == e.key,
                                    color: kAcc,
                                    onTap: () => setState(() {
                                      _repeatKind = e.key;
                                      _repeatInterval = 1;
                                      if (_repeatKind == 3 && _start != null) {
                                        _repeatDays = 1 <<
                                            (_start!.weekday - 1);
                                      }
                                    }),
                                  ),
                              ],
                            ),
                            // 每 N 天 / 周 / 月 / 年
                            if (_repeatKind == 1 ||
                                _repeatKind == 3 ||
                                _repeatKind == 4 ||
                                _repeatKind == 5) ...[
                              SizedBox(height: 10),
                              Row(
                                children: [
                                  Text('间隔',
                                      style: TextStyle(
                                          fontSize: 12.5, color: kDim)),
                                  SizedBox(width: 8),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _repeatInterval <= 1
                                        ? null
                                        : () => setState(
                                            () => _repeatInterval -= 1),
                                    icon: Icon(Icons.remove_circle_outline,
                                        size: 18),
                                  ),
                                  Text(
                                    '每 $_repeatInterval${_repeatUnitCn}',
                                    style: TextStyle(
                                        fontSize: 13, color: kFg),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _repeatInterval >= 30
                                        ? null
                                        : () => setState(
                                            () => _repeatInterval += 1),
                                    icon: Icon(Icons.add_circle_outline,
                                        size: 18),
                                  ),
                                ],
                              ),
                            ],
                            if (_repeatKind == 3) ...[
                              SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                children: [
                                  _PickChip(
                                    label: '周末',
                                    selected: _repeatDays == 0x60,
                                    color: kWarn,
                                    onTap: () => setState(
                                        () => _repeatDays = 0x60),
                                  ),
                                  _PickChip(
                                    label: '工作日',
                                    selected: _repeatDays == 0x1F,
                                    color: kWarn,
                                    onTap: () => setState(
                                        () => _repeatDays = 0x1F),
                                  ),
                                  _PickChip(
                                    label: '全都选',
                                    selected: _repeatDays == 0x7F,
                                    color: kWarn,
                                    onTap: () => setState(
                                        () => _repeatDays = 0x7F),
                                  ),
                                  _PickChip(
                                    label: '清空',
                                    selected: false,
                                    color: kDim,
                                    onTap: () =>
                                        setState(() => _repeatDays = 0),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (var i = 0; i < 7; i++)
                                    _PickChip(
                                      label:
                                          '周${['一', '二', '三', '四', '五', '六', '日'][i]}',
                                      selected: _repeatDays & (1 << i) != 0,
                                      color: kAcc,
                                      onTap: () => setState(() {
                                        _repeatDays =
                                            _repeatDays ^ (1 << i);
                                      }),
                                    ),
                                ],
                              ),
                            ],
                            if (_repeatKind != 0) ...[
                              SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(Icons.event_repeat,
                                      size: 16, color: kDim),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _repeatUntil == null
                                          ? '一直重复到手动停止'
                                          : '重复到 ${_repeatUntil!.month}/${_repeatUntil!.day}',
                                      style: TextStyle(
                                          fontSize: 12.5, color: kDim),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      final d = await showDatePicker(
                                        context: context,
                                        initialDate: _repeatUntil ??
                                            DateTime.now()
                                                .add(Duration(days: 60)),
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime(2100),
                                      );
                                      if (d != null) {
                                        setState(() => _repeatUntil = d);
                                      }
                                    },
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      textStyle:
                                          TextStyle(fontSize: 12),
                                    ),
                                    child: Text('设置结束'),
                                  ),
                                  if (_repeatUntil != null)
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () =>
                                          setState(() => _repeatUntil = null),
                                      icon: Icon(Icons.close, size: 15),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 16),

                    // 子任务
                    _Label('拆解步骤',
                        trailing: _subs.isEmpty ? null : '${_subs.where((s) => s.done).length}/${_subs.length}'),
                    SizedBox(height: 6),
                    if (_subs.isNotEmpty)
                      Container(
                        decoration: BoxDecoration(
                          color: kCard2,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            for (var i = 0; i < _subs.length; i++)
                              Row(
                                children: [
                                  SizedBox(
                                    width: 34,
                                    height: 34,
                                    child: Checkbox(
                                      value: _subs[i].done,
                                      activeColor: kAcc,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      onChanged: (v) => setState(() =>
                                          _subs[i].done = v ?? false),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      _subs[i].title,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: _subs[i].done ? kDim : null,
                                        decoration: _subs[i].done
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        setState(() => _subs.removeAt(i)),
                                    icon: Icon(Icons.close,
                                        size: 15, color: kFaint),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: _subInput,
                      style: TextStyle(fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: '＋ 加一个步骤，回车确认',
                        hintStyle: TextStyle(fontSize: 13),
                        isDense: true,
                      ),
                      onSubmitted: (v) {
                        final s = v.trim();
                        if (s.isEmpty) return;
                        setState(() => _subs.add(Subtask(s)));
                        _subInput.clear();
                      },
                    ),
                    SizedBox(height: 16),

                    // 备注
                    _Label('备注'),
                    SizedBox(height: 6),
                    TextField(
                      controller: _note,
                      maxLines: 3,
                      minLines: 2,
                      style: TextStyle(fontSize: 13.5, height: 1.4),
                      decoration: InputDecoration(
                        hintText: '记点什么：老师强调的重点、要问的问题…',
                        hintStyle: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  if (!_isNew)
                    TextButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, _Res(null, deleted: true)),
                      icon: Icon(Icons.delete_outline,
                          size: 17, color: kDanger),
                      label: Text('删除',
                          style: TextStyle(color: kDanger, fontSize: 13)),
                    ),
                  Spacer(),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('取消')),
                  SizedBox(width: 6),
                  FilledButton(
                    onPressed: _title.text.trim().isEmpty ? null : _save,
                    child: Text('保存'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════
// 小组件
// ══════════════════════════════════════════════════════

class _Label extends StatelessWidget {
  final String text;
  final String? trailing;
  _Label(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(text,
              style: TextStyle(
                  fontSize: 12,
                  color: kDim,
                  fontWeight: FontWeight.w600)),
          if (trailing != null) ...[
            SizedBox(width: 8),
            Text(trailing!,
                style: TextStyle(fontSize: 11, color: kFaint)),
          ],
        ],
      );
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  _Tag({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12.5, color: color),
          if (text.isNotEmpty) ...[
            SizedBox(width: 3),
            Text(text, style: TextStyle(fontSize: 11.5, color: color)),
          ],
        ],
      );
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  _StatCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: kLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: kDim)),
            SizedBox(height: 5),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );
}

class _FilterChip2 extends StatelessWidget {
  final String label;
  final bool selected;
  final int? count;
  final VoidCallback onTap;
  _FilterChip2({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 140),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? kAcc.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? kAcc : kLine),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    color: selected ? kAcc : kDim,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
            if (count != null && count! > 0) ...[
              SizedBox(width: 5),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 5, vertical: 0.5),
                decoration: BoxDecoration(
                  color: (selected ? kAcc : kDim).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$count',
                    style: TextStyle(
                        fontSize: 10, color: selected ? kAcc : kDim)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PickChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  _PickChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 130),
          padding: EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color : kLine,
              width: selected ? 1.3 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: selected ? color : kDim,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      );
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  _SwitchRow({
    required this.title,
    required this.sub,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13.5)),
                  Text(sub,
                      style: TextStyle(fontSize: 11, color: kFaint)),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      );
}

class _TimeRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String text;
  final bool active;
  final Future<void> Function() onPick;
  final VoidCallback? onClear;
  _TimeRow({
    required this.icon,
    required this.label,
    required this.text,
    required this.active,
    required this.onPick,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onPick(),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 16, color: active ? kAcc : kDim),
              SizedBox(width: 10),
              SizedBox(
                width: 34,
                child: Text(label,
                    style: TextStyle(fontSize: 12.5, color: kDim)),
              ),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 13,
                        color: active ? null : kFaint,
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.w400)),
              ),
              if (onClear != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onClear,
                  icon: Icon(Icons.close, size: 15, color: kFaint),
                )
              else
                Icon(Icons.chevron_right, size: 16, color: kFaint),
            ],
          ),
        ),
      );
}