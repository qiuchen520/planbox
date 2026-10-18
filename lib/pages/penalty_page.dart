import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../palette.dart';
import '../services/focus_guard.dart';
import '../theme.dart';

/// 违规惩罚页：用户偷偷关掉权限 / 强杀 App 之后，下次打开会先看到它。
///
/// 纯 Flutter 全屏层，不依赖原生。文案随机，语气是「委屈」而不是「责骂」。
class PenaltyPage extends StatefulWidget {
  /// 'killed'（App 被杀）/ 'permission'（权限被撤）
  final String reason;

  const PenaltyPage({super.key, required this.reason});

  static Future<void> show(BuildContext context, String reason) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, __, ___) => PenaltyPage(reason: reason),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<PenaltyPage> createState() => _PenaltyPageState();
}

class _PenaltyPageState extends State<PenaltyPage> {
  static const List<String> _lines = [
    '你居然为了玩手机把锁关了…我很伤心💔',
    '说好一起学习的，你怎么溜了(；′⌒`)',
    '我倒计时都数完了，你人呢？',
    '再这样，我的记录本也要跟着哭了…',
    '这一轮没守住，下次还想偷跑吗？',
    '你不是说要考好的嘛……(｡•́︿•̀｡)',
  ];

  late final String _line =
      _lines[math.Random().nextInt(_lines.length)];

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// 主按钮：认错 → 清标记 → 去补权限
  Future<void> _again() async {
    if (_busy) return;
    setState(() => _busy = true);
    await FocusGuard.clearViolation();
    await FocusGuard.end();
    if (!mounted) return;
    Navigator.of(context).pop();
    // 权限还缺就去引导，齐了就不用打扰
    await FocusGuard.openPermissionFlow();
  }

  /// 次按钮：今天不想学了（二次确认）
  Future<void> _giveUp() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: Text('真的不学了吗？', style: TextStyle(color: kFg)),
        content: Text(
          '这一轮会直接作废，今天的守护也一起关掉。\n明天想开始的时候，重新进专注就行。',
          style: TextStyle(color: kDim, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('还是学吧', style: TextStyle(color: kAcc)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('确定放弃', style: TextStyle(color: kDim)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await FocusGuard.clearViolation();
    await FocusGuard.end();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.reason == 'permission'
        ? '你把权限关掉了……我拦不住你，可我还在等。'
        : '你把我从后台清掉了……这一轮我白数了。';
    return Scaffold(
      backgroundColor: const Color(0xFF0E1220),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 20, 26, 22),
          child: Column(
            children: [
              const Spacer(flex: 2),
              // 委屈的脸
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kAcc.withValues(alpha: 0.10),
                  border: Border.all(color: kAcc.withValues(alpha: 0.28)),
                ),
                child: Icon(
                  Icons.sentiment_very_dissatisfied_rounded,
                  size: 62,
                  color: kAcc.withValues(alpha: 0.92),
                ),
              ),
              const SizedBox(height: 26),
              Text(
                _line,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  height: 1.55,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.94),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                sub,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: Colors.white.withValues(alpha: 0.46),
                ),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _busy ? null : _again,
                  style: FilledButton.styleFrom(
                    backgroundColor: kAcc,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    '我错了，重新专注',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: _busy ? null : _giveUp,
                child: Text(
                  '今天不想学了',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.30),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}