import 'package:flutter/material.dart';

import '../palette.dart';
import '../services/focus_lock.dart';
import '../theme.dart';

/// 专注守护的权限引导页（后台运行 + 悬浮窗 + 使用情况访问）。
///
/// 为什么单独做一页而不是弹个对话框：定制 ROM（读书郎这种尤其）里
/// 「点了没反应 / 跳错页面 / 开关存在但读不到」太常见了，需要逐项看状态、
/// 反复重试，还能给出手动路径。
class PermissionPage extends StatefulWidget {
  const PermissionPage({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const PermissionPage()),
    );
  }

  @override
  State<PermissionPage> createState() => _PermissionPageState();
}

class _PermissionPageState extends State<PermissionPage>
    with WidgetsBindingObserver {
  bool? _usage;
  bool? _overlay;
  bool? _battery;
  bool _busy = false;
  Map<String, dynamic> _diag = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从系统设置页回来时自动刷新状态
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final usage = await FocusLock.canUsage();
    final overlay = await FocusLock.canOverlay();
    final battery = await FocusLock.ignoringBattery();
    final diag = await FocusLock.diag();
    if (!mounted) return;
    setState(() {
      _usage = usage;
      _overlay = overlay;
      _battery = battery;
      _diag = diag;
    });
  }

  /// 跳系统设置。跳完回来可能还没生效（有的 ROM 要退一层才写回），
  /// 所以延时再刷一次。
  Future<void> _go(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    await action();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) {
      _busy = false;
      return;
    }
    setState(() => _busy = false);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final allOk = _usage == true && _overlay == true;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        foregroundColor: kFg,
        title: Text('专注守护权限',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: kFg)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, size: 20, color: kDim),
            tooltip: '重新检测',
            onPressed: _refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kCard.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kLine.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(
                  allOk ? Icons.verified_user : Icons.info_outline,
                  size: 18,
                  color: allOk ? kOk : kAcc,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    allOk
                        ? '两个关键权限都到位了，专注时可以拦住你切走。'
                        : '上面两项是拦截的前提。没开也能计时，但拦不住跑神。',
                    style: TextStyle(fontSize: 12, height: 1.55, color: kDim),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            title: '使用情况访问',
            desc: '用来知道当前前台是哪个应用。这一项没有开关图标，'
                '要进列表里找到「计划盒」再打开。',
            ok: _usage,
            actionLabel: '去开启',
            onTap: () => _go(FocusLock.openUsageSettings),
          ),
          _card(
            title: '显示在其他应用上层（悬浮窗）',
            desc: '跑神时盖一层「回去学习」。'
                '如果点进去找不到开关，试试下面的「应用信息」里的权限入口。',
            ok: _overlay,
            actionLabel: '去开启',
            onTap: () => _go(FocusLock.openOverlaySettings),
          ),
          _card(
            title: '后台运行 / 电池优化',
            desc: '把计划盒从电池优化名单里去掉，否则守护服务可能被杀掉，'
                '之后就会被判成「偷跑」。',
            ok: _battery,
            actionLabel: '去设置',
            onTap: () => _go(FocusLock.openBatterySettings),
          ),
          _diagCard(),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: () => _go(FocusLock.openAppDetails),
              child: Text('打不开？直接进应用信息页',
                  style: TextStyle(fontSize: 12, color: kDim)),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kCard.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('手动路径（找不到入口时）',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: kFg)),
                const SizedBox(height: 8),
                Text(
                  '· 悬浮窗：设置 → 应用 → 特殊应用权限 → 显示在其他应用上层\n'
                  '· 使用情况访问：设置 → 安全 → 使用情况访问权限\n'
                  '· 电池优化：设置 → 电池 → 电池优化 → 计划盒 → 不优化',
                  style: TextStyle(fontSize: 11.5, height: 1.75, color: kDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 自检面板：告诉用户“服务到底卡在哪一步”。
  Widget _diagCard() {
    final running = _diag['running'] == true;
    final reason = (_diag['reason'] ?? '').toString();
    final lastFg = (_diag['lastFg'] ?? '').toString();
    final sdk = (_diag['sdk'] ?? '').toString();
    final reasonText = const {
      '': '尚未启动过',
      'paused': '处于紧急暂停期',
      'no_overlay': '没拿到悬浮窗权限，服务自己退了',
      'no_usage': '没拿到使用情况权限，服务自己退了',
      'start_failed': '系统拒绝了服务启动',
      'running': '正常运行中',
      'no_foreground': '读不到前台应用（使用情况权限可能没真生效）',
      'blocking': '正在拦截',
      'ok': '已把你拉回计划盒',
      'launch_blocked': '系统不允许后台拉起界面（读书郎常见）',
      'launch_exception': '拉起界面抛异常',
      'add_view_failed': '幕布挂不上去（悬浮窗被系统忽略）',
      'perm_lost': '运行中权限被撤了',
      'emergency': '被长按紧急退出',
    }[reason] ?? reason;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kLine.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('自检',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: kFg)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (running ? kOk : kDim).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(running ? '服务在跑' : '服务没跑',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: running ? kOk : kDim)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('当前状态：$reasonText',
              style: TextStyle(fontSize: 11.5, height: 1.6, color: kDim)),
          if (lastFg.isNotEmpty)
            Text('最近前台：$lastFg',
                style: TextStyle(fontSize: 11.5, height: 1.6, color: kDim)),
          if (sdk.isNotEmpty)
            Text('Android SDK $sdk',
                style: TextStyle(fontSize: 11, height: 1.6, color: kDim)),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    required String desc,
    required bool? ok,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    final known = ok != null;
    final on = ok == true;
    final color = !known ? kDim : (on ? kOk : kDanger);
    final label = !known ? '检测中' : (on ? '已开启' : '未开启');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
      decoration: BoxDecoration(
        color: kCard.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kLine.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: kFg)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(desc,
              style: TextStyle(fontSize: 11.5, height: 1.6, color: kDim)),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: on ? null : onTap,
              child: Text(
                on ? '已完成' : actionLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: on ? kDim : kAcc,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}