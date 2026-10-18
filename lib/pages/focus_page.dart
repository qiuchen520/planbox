import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/db.dart';
import '../models.dart';
import '../palette.dart';
import '../services/ambience.dart';
import '../services/focus_guard.dart';
import '../theme.dart';
import 'permission_page.dart';
import 'whitelist_page.dart';

/// 番茄钟 / 专注倒计时。
///
/// 规矩很简单，也是用户明确要的：**点开任务不等于完成**。
/// 只有在这个页面里点「完成」并二次确认，才算真的把这条计划勾掉；
/// 计时中途退出只会丢掉这次专注，不会动数据。
class FocusPage extends StatefulWidget {
  final Task task;

  FocusPage({super.key, required this.task});

  /// 打开专注页。返回 true 表示这条任务被标记完成了，调用方据此刷新列表。
  static Future<bool?> open(BuildContext context, Task task) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FocusPage(task: task),
      ),
    );
  }

  @override
  State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _bg = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  Timer? _ticker;
  int _totalSec = 0; // 0 = 还没定时长
  int _remainSec = 0;
  bool _running = false;
  /// 这一轮是否已经把「专注守护」点着了（暂停/继续不重复拉起）
  bool _guardOn = false;
  /// 只自动提醒一次权限，别每次继续都弹
  bool _permAsked = false;
  /// 计时锚点：剩余秒数只在 anchor 那一刻是准的，之后按墙钟推算。
  /// 这样切后台、页面被系统回收重建，都不会让倒计时凭空跳走或归零。
  DateTime? _anchor;
  int _remainAtAnchor = 0;

  bool get _hasPlan => _totalSec > 0;
  double get _progress => _totalSec == 0
      ? 0
      : (1 - _remainSec / _totalSec).clamp(0.0, 1.0).toDouble();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restore());
  }

  /// 先看有没有上一轮的进度（切后台/被回收后回来），没有就按预估用时开跑
  Future<void> _restore() async {
    final sess = await FocusGuard.loadSession(widget.task.id);
    if (!mounted) return;
    if (sess != null) {
      final total = sess['total'] as int;
      final remain = sess['remain'] as int;
      final wasRunning = sess['running'] as bool;
      setState(() {
        _totalSec = total;
        _remainSec = remain > 0 ? remain : total;
        _running = false;
      });
      if (wasRunning && remain > 0) _start();
      return;
    }
    final est = widget.task.estimate;
    if (est > 0) {
      setState(() {
        _totalSec = est * 60;
        _remainSec = _totalSec;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台回来时按墙钟把剩余时间对齐一次，别停在旧数字上
    if (state == AppLifecycleState.resumed && _running) setState(_syncRemain);
  }

  /// 把 _remainSec 按墙钟对齐到「现在」
  void _syncRemain() {
    final a = _anchor;
    if (a == null) return;
    final passed = DateTime.now().difference(a).inMilliseconds ~/ 1000;
    final left = _remainAtAnchor - passed;
    _remainSec = left > 0 ? left : 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _bg.dispose();
    // 离开页面就别让噪音一直响着
    Ambience.i.stop();
    // 只是切页面/按返回键离开，不等于这一轮结束：守护继续、进度存着，
    // 回来能接着数。真正的收尾在 _markDone() / 到点 / 用户点「就这样结束」。
    if (_running) {
      _syncRemain();
      unawaited(FocusGuard.saveSession(
        taskId: widget.task.id,
        totalSec: _totalSec,
        remainSec: _remainSec,
        running: true,
      ));
    }
    super.dispose();
  }

  // ── 计时 ──────────────────────────────────────────
  void _start() {
    if (!_hasPlan) return;
    if (_remainSec <= 0) _remainSec = _totalSec;
    _anchor = DateTime.now();
    _remainAtAnchor = _remainSec;
    setState(() => _running = true);
    Ambience.i.resume();
    unawaited(_ensureGuard());
    unawaited(FocusGuard.saveSession(
      taskId: widget.task.id,
      totalSec: _totalSec,
      remainSec: _remainSec,
      running: true,
    ));
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _syncRemain();
      if (_remainSec <= 0) {
        _ticker?.cancel();
        setState(() => _running = false);
        unawaited(FocusGuard.clearSession());
        _onTimeUp();
        return;
      }
      setState(() {});
    });
  }

  void _pause() {
    _syncRemain();
    _ticker?.cancel();
    _anchor = null;
    Ambience.i.pause();
    setState(() => _running = false);
    unawaited(FocusGuard.saveSession(
      taskId: widget.task.id,
      totalSec: _totalSec,
      remainSec: _remainSec,
      running: false,
    ));
  }

  /// 把原生守护点起来。权限不齐就先问一句，不强行开始。
  Future<void> _ensureGuard() async {
    if (_guardOn) return;
    final minutes = _totalSec ~/ 60;
    if (await FocusGuard.begin(minutes)) {
      if (mounted) setState(() => _guardOn = true);
      return;
    }
    if (!mounted) return;
    if (!_permAsked) await _askPermissions();
    // 用户补完权限回来，再试一次
    if (!mounted) return;
    if (await FocusGuard.hasAllPermissions()) {
      if (await FocusGuard.begin(minutes) && mounted) {
        setState(() => _guardOn = true);
      }
    }
  }

  Future<void> _askPermissions() async {
    _permAsked = true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Text('开启专注守护？', style: TextStyle(color: kFg)),
        content: Text(
          '守护需要两个系统权限：\n'
          '· 使用情况访问 —— 才知道你切到了哪个应用\n'
          '· 显示在其他应用上层 —— 才能在跑神时盖一层提醒\n\n'
          '不授权也能用番茄钟，只是拦不住你切走。',
          style: TextStyle(color: kDim, height: 1.6, fontSize: 12.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('先不用', style: TextStyle(color: kDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('去开启', style: TextStyle(color: kAcc)),
          ),
        ],
      ),
    );
    if (go == true) await PermissionPage.open(context);
  }

  void _reset() {
    _ticker?.cancel();
    setState(() {
      _running = false;
      _remainSec = _totalSec;
    });
  }

  void _chooseMinutes(int m) {
    setState(() {
      _totalSec = m * 60;
      _remainSec = _totalSec;
    });
    _start();
  }

  Future<void> _chooseCustom() async {
    final ctrl = TextEditingController(
      text: _hasPlan ? '${_totalSec ~/ 60}' : '30',
    );
    final m = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('这次的专注时长'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '分钟',
            helperText: '1 ~ 240 之间',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('取消', style: TextStyle(color: kDim)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)),
            child: const Text('开始'),
          ),
        ],
      ),
    );
    final v = (m ?? 0).clamp(0, 240);
    if (v > 0 && mounted) _chooseMinutes(v);
  }

  // ── 结束 / 完成 ────────────────────────────────────
  void _onTimeUp() {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.mediumImpact();
    _showDoneSheet(
      title: '这一轮结束了 🎉',
      body: '专注 ${_totalSec ~/ 60} 分钟，把「${widget.task.title}」标记完成吗？',
      confirm: '标记完成',
      keepGoing: '再来 5 分钟',
    );
  }

  Future<void> _onFinishPressed() async {
    if (!_hasPlan) {
      await _markDone();
      return;
    }
    final left = _remainSec;
    if (left > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('提前结束？'),
          content: Text('还剩 ${_fmt(left)}。确认已经做完了吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('继续专注', style: TextStyle(color: kDim)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认完成'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _markDone();
  }

  void _showDoneSheet({
    required String title,
    required String body,
    required String confirm,
    String? keepGoing,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () {
              // 就这样结束也算收工，别让守护和通知继续挂着
              unawaited(FocusGuard.end());
              Navigator.pop(ctx);
              Navigator.pop(context, false); // 不标记完成，直接退出
            },
            child: Text('就这样结束', style: TextStyle(color: kDim)),
          ),
          if (keepGoing != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _totalSec += 5 * 60;
                _remainSec += 5 * 60;
                _start();
              },
              child: Text(keepGoing),
            ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _markDone();
            },
            child: Text(confirm),
          ),
        ],
      ),
    );
  }

  Future<void> _markDone() async {
    _ticker?.cancel();
    _anchor = null;
    // 这一轮真正结束了：清标记 + 清会话 + 停服务
    unawaited(FocusGuard.end());
    await Ambience.i.stop();
    if (!widget.task.done) {
      // toggleTask 会把重复计划推进到下一次，和列表里手动勾选的行为保持一致
      await DB.i.toggleTask(widget.task);
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<bool> _onWillPop() async {
    if (!_running) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('还在专注中'),
        content: Text('现在退出会丢掉这一轮，计划不会被标记完成。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('继续', style: TextStyle(color: kDim)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  static String _fmt(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── 界面 ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    return PopScope(
      // 计时中先拦住返回键，问一句再走（Flutter 3.47 已移除 WillPopScope）
      canPop: !_running,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _onWillPop();
        if (ok && mounted) Navigator.pop(context, false);
      },
      child: Scaffold(
        body: Stack(
          children: [
            // 动态背景
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _bg,
                  builder: (_, __) => CustomPaint(
                    painter: _BlobPainter(_bg.value, _running),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _topBar(t),
                  Expanded(child: _centerRing(t)),
                  _bottomPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(Task t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 14, 0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.close, color: kFg),
            tooltip: '退出',
            onPressed: () async {
              if (await _onWillPop() && mounted) Navigator.pop(context, false);
            },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: kFg),
                ),
                if (t.subject.isNotEmpty || t.estimate > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        if (t.subject.isNotEmpty) t.subject,
                        if (t.estimate > 0) '预估 ${t.estimateLabel}',
                      ].join(' · '),
                      style: TextStyle(fontSize: 11.5, color: kDim),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              _guardOn ? Icons.shield : Icons.shield_outlined,
              size: 20,
              color: _guardOn ? kAcc : kDim,
            ),
            tooltip: _guardOn ? '守护中（点查权限）' : '守护未开启（点去开启）',
            onPressed: () => PermissionPage.open(context),
          ),
          IconButton(
            icon: Icon(Icons.playlist_add_check, color: kDim, size: 20),
            tooltip: '专注白名单',
            onPressed: () => WhitelistPage.open(context),
          ),
        ],
      ),
    );
  }

  Widget _centerRing(Task t) {
    final label = !_hasPlan
        ? '选个时长开始'
        : _running
            ? '专注中'
            : (_remainSec == 0 ? '已结束' : '已暂停');
    final shown = !_hasPlan ? '--:--' : _fmt(_remainSec);
    return Center(
      child: LayoutBuilder(
        builder: (context, box) {
          final side = math.min(box.maxWidth, box.maxHeight) * 0.82;
          final d = side.clamp(200.0, 460.0).toDouble();
          return SizedBox(
            width: d,
            height: d,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: _progress),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOut,
                  builder: (_, v, __) => CustomPaint(
                    size: Size(d, d),
                    painter: _RingPainter(v),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      shown,
                      style: TextStyle(
                        fontSize: d * 0.21,
                        fontWeight: FontWeight.w300,
                        color: kFg,
                        letterSpacing: 2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(label,
                        style: TextStyle(fontSize: 12.5, color: kDim)),
                    if (_hasPlan && _running)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('已完成 ${(_progress * 100).round()}%',
                            style: TextStyle(fontSize: 11, color: kAcc)),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _bottomPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 没定时长：给一组常用值
          if (!_hasPlan) ...[
            Text('这次打算做多久？',
                style: TextStyle(fontSize: 12.5, color: kDim)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final m in [10, 15, 25, 45])
                  _chip('$m 分钟', () => _chooseMinutes(m)),
                _chip('自定义', _chooseCustom, icon: Icons.edit_outlined),
              ],
            ),
            const SizedBox(height: 18),
          ] else ...[
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _big(
                  _running ? '暂停' : (_remainSec == 0 ? '重新开始' : '继续'),
                  _running ? _pause : _start,
                  primary: true,
                  icon: _running ? Icons.pause : Icons.play_arrow,
                ),
                _big('重置', _reset, icon: Icons.refresh),
                _big('完成', _onFinishPressed,
                    icon: Icons.check_circle_outline, danger: true),
              ],
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _chooseCustom,
              child: Text('改时长', style: TextStyle(fontSize: 12, color: kDim)),
            ),
          ],
          _noiseBar(),
        ],
      ),
    );
  }

  Widget _noiseBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: kCard.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kLine.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq, size: 15, color: kDim),
              const SizedBox(width: 8),
              for (final k in NoiseKind.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _chip(
                    k.label,
                    () async {
                      await Ambience.i.setKind(k);
                      setState(() {});
                    },
                    active: Ambience.i.kind == k,
                    dense: true,
                  ),
                ),
            ],
          ),
          Row(
            children: [
              Icon(Icons.volume_down_outlined, size: 15, color: kFaint),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: Ambience.i.volume,
                    onChanged: (v) {
                      Ambience.i.setVolume(v);
                      setState(() {});
                    },
                  ),
                ),
              ),
              Icon(Icons.volume_up_outlined, size: 15, color: kFaint),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, VoidCallback onTap,
      {bool active = false, IconData? icon, bool dense = false}) {
    return Material(
      color: active ? kAcc.withValues(alpha: 0.18) : kCard.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: dense ? 9 : 14, vertical: dense ? 5 : 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? kAcc : kLine.withValues(alpha: 0.7),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: dense ? 12 : 14,
                    color: active ? kAcc : kDim),
                const SizedBox(width: 4),
              ],
              Text(
                text,
                style: TextStyle(
                  fontSize: dense ? 11.5 : 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? kAcc : kFg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _big(String text, VoidCallback onTap,
      {bool primary = false,
      bool danger = false,
      IconData? icon}) {
    final bg = primary
        ? kAcc
        : danger
            ? kDanger.withValues(alpha: 0.14)
            : kCard.withValues(alpha: 0.6);
    final fg = primary ? kOnAcc : (danger ? kDanger : kFg);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: primary ? Colors.transparent : kLine.withValues(alpha: 0.7)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 6),
              ],
              Text(text,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 背景：几个缓慢漂移的色团，专注时动得稍微快一点。
/// 用渐变色块而不是模糊图，老平板上也不会掉帧。
class _BlobPainter extends CustomPainter {
  final double t;
  final bool active;
  _BlobPainter(this.t, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(kBg, BlendMode.src);
    final acc = kAcc;
    final base = active ? 1.0 : 0.55;
    final blobs = <List<double>>[
      [0.30, 0.22, 0.55],
      [0.74, 0.32, 0.48],
      [0.52, 0.78, 0.62],
    ];
    for (var i = 0; i < blobs.length; i++) {
      final ph = t * 2 * math.pi + i * 2.1;
      final cx = size.width * (blobs[i][0] + 0.10 * math.sin(ph));
      final cy = size.height * (blobs[i][1] + 0.08 * math.cos(ph * 0.8));
      final r = size.shortestSide * blobs[i][2] * (0.9 + 0.08 * math.sin(ph * 1.3));
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            acc.withValues(alpha: 0.20 * base),
            acc.withValues(alpha: 0.05 * base),
            acc.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.t != t || old.active != active;
}

/// 进度环：底圈 + 主色弧 + 端点小圆
class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 - 6;
    final stroke = size.shortestSide * 0.035;
    final rect = Rect.fromCircle(center: c, radius: r);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = kLine.withValues(alpha: 0.55);
    canvas.drawCircle(c, r, track);

    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = kAcc;
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);

    // 端点亮点
    final end = Offset(
      c.dx + r * math.cos(-math.pi / 2 + sweep),
      c.dy + r * math.sin(-math.pi / 2 + sweep),
    );
    canvas.drawCircle(
      end,
      stroke * 0.55,
      Paint()..color = kAcc.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}