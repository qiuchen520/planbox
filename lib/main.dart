import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/db.dart';
import 'models.dart';
import 'pages/agreement.dart';
import 'pages/focus_page.dart';
import 'pages/home_shell.dart';
import 'pages/penalty_page.dart';
import 'palette.dart';
import 'services/focus_guard.dart';
import 'services/ambience.dart';
import 'services/hud.dart';
import 'services/notify.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先读回用户选的配色，避免启动瞬间闪一下默认色
  await Pal.load();

  // 通知：初始化失败（缺权限 / 插件异常）不能影响 App 启动，内部已吞异常
  await Notify.i.init();
  DB.taskHook = (task, op) async {
    switch (op) {
      case 'delete':
        if (task.id != null) await Notify.i.cancelTask(task.id!);
        break;
      case 'clear':
        await Notify.i.resyncAll();
        break;
      default:
        await Notify.i.syncTask(task);
    }
    // 任务增删改 → 悬浮窗上的今日清单跟着变
    unawaited(Hud.refresh());
  };

  // 手机重启、系统清理闹钟之后，靠启动时重排一遍补回来
  unawaited(Notify.i.resyncAll());
  // 桌面悬浮窗：先把通道挂好，再补数据 / 补上次没处理完的动作
  Hud.init();
  Hud.onAction = (action, taskId) => _hudAction(action, taskId);
  unawaited(_bootHud());
  runApp(PlanBoxApp());
}

/// 当前 navigator，悬浮窗点过来的动作靠它弹页面 / 弹提示
GlobalKey<NavigatorState>? _appNav;

/// 启动 / 回到前台时对齐悬浮窗：补动作、刷新清单、把开关状态对齐
Future<void> _bootHud() async {
  final on = (await DB.i.getSetting(Hud.settingKey)) == '1';
  final running = await Hud.isRunning();
  if (on && !running) {
    // 被系统清理过 / 刚开机：按开关自动拉起来；没悬浮窗权限就先落下来
    final ok = await Hud.start();
    if (!ok) await DB.i.setSetting(Hud.settingKey, '0');
  } else if (!on && running) {
    await Hud.stop();
  }
  if (await Hud.isRunning()) await Hud.refresh();
  await Hud.takeLaunch();
}

/// 悬浮窗上的一次点击
Future<void> _hudAction(String action, int taskId) async {
  final ctx = _appNav?.currentContext;
  switch (action) {
    case 'focus':
    case 'checkin':
      final tasks = await DB.i.tasks();
      Task? t;
      for (final x in tasks) {
        if (x.id == taskId) {
          t = x;
          break;
        }
      }
      if (t == null || ctx == null) return;
      if (action == 'focus') {
        final done = await FocusPage.open(ctx, t);
        if (done == true) await Hud.refresh();
        return;
      }
      final doneToday = t.lastDone != null &&
          sameDay(
            DateTime.fromMillisecondsSinceEpoch(t.lastDone!),
            DateTime.now(),
          );
      if (doneToday) {
        _hudToast(ctx, '「${t.title}」今天已经打过卡了');
        return;
      }
      await DB.i.toggleTask(t);
      await Hud.refresh();
      _hudToast(ctx, '已打卡「${t.title}」');
      break;
    case 'toggleTimer':
      final host = Hud.timerHost;
      if (host == null) {
        if (ctx != null) _hudToast(ctx, '先在 App 里打开番茄钟，悬浮窗才控得住它');
        return;
      }
      await host.hudToggleTimer();
      break;
    case 'newTask':
      HomeShell.goto(4);
      break;
    case 'alreadyDone':
      if (ctx != null) _hudToast(ctx, '今天已经打过卡了');
      break;
    case 'openToday':
    case 'focusPage':
      HomeShell.goto(0);
      break;
    case 'openCheckin':
      HomeShell.goto(1);
      break;
    case 'openTimetable':
      HomeShell.goto(2);
      break;
    case 'openCalendar':
      HomeShell.goto(3);
      break;
    case 'settings':
      HomeShell.goto(5);
      break;
    case 'ambience':
      if (Ambience.i.playing) {
        await Ambience.i.pause();
        if (ctx != null) _hudToast(ctx, '白噪音已暂停');
      } else {
        if (Ambience.i.kind == NoiseKind.none) {
          await Ambience.i.setKind(
            NoiseKind.values.firstWhere((k) => k != NoiseKind.none),
          );
        } else {
          await Ambience.i.resume();
        }
        if (ctx != null) _hudToast(ctx, '白噪音已开');
      }
      break;
    case 'hudOff':
      await DB.i.setSetting(Hud.settingKey, '0');
      if (ctx != null) _hudToast(ctx, '悬浮窗已关掉，需要时点番茄钟左上角再开');
      break;
  }
}

void _hudToast(BuildContext ctx, String msg) {
  final m = ScaffoldMessenger.maybeOf(ctx);
  m?.clearSnackBars();
  m?.showSnackBar(SnackBar(
    content: Text(msg),
    duration: const Duration(milliseconds: 1600),
  ));
}

/// 全屏沉浸：默认把顶部状态栏（时间 / 电量那一行）藏起来。
/// 用 immersiveSticky 而不是 manual —— 从屏幕顶部下滑能临时唤出来看一眼，
/// 过几秒没人碰它自己再收回去，正是「显示一回然后删掉」的效果。
void _enterImmersive() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

class PlanBoxApp extends StatefulWidget {
  PlanBoxApp({super.key});

  @override
  State<PlanBoxApp> createState() => _PlanBoxAppState();
}

class _PlanBoxAppState extends State<PlanBoxApp> with WidgetsBindingObserver {
  Timer? _hideTimer;
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  /// 惩罚页正在显示时不要再叠加一层
  bool _penaltyShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appNav = _navKey;
    _enterImmersive();
    // 启动时先看一眼上一轮是不是被偷跑了
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkViolation());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 弹过输入法、从后台切回来之后，部分系统会把状态栏又放出来，这里补一刀。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enterImmersive();
      // 从后台回来也查一次：被杀过 / 撤过权限的话，这里就能发现
      _checkViolation();
      // 悬浮窗那边可能攒了动作，回来先补上；顺带把今日清单刷新一遍
      unawaited(_bootHud());
    }
  }

  /// 关键：immersiveSticky 在不少国产 ROM（读书郎这类定制系统尤其如此）上下滑唤出后会
  /// 一直赖着不走。这里盯着窗口 padding：一旦顶部又有了状态栏高度，就启动一个两秒的
  /// 计时器把它重新藏回去 —— 用户能看一眼时间，然后它自己消失。
  @override
  void didChangeMetrics() {
    final v = WidgetsBinding.instance.platformDispatcher.views.first;
    final top = v.viewPadding.top / v.devicePixelRatio;
    if (top > 0.5) {
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 2), () {
        _enterImmersive();
        // 有的 ROM 对单次调用不理会，隔一拍再补一次
        Future<void>.delayed(const Duration(milliseconds: 400), _enterImmersive);
      });
    }
  }

  /// 检测上一轮专注是否被「偷跑」：服务没了 = 被杀，权限没了 = 被撤。
  Future<void> _checkViolation() async {
    if (_penaltyShowing || !mounted) return;
    String? reason = await FocusGuard.pollViolation();
    if (!mounted) return;
    if (reason == null || reason.isEmpty) {
      final pending = await FocusGuard.pendingViolation();
      if (pending != null && pending.isNotEmpty) reason = pending;
    }
    if (reason == null || reason.isEmpty) return;
    final ctx = _navKey.currentState?.context;
    if (ctx == null) return;
    _penaltyShowing = true;
    await PenaltyPage.show(ctx, reason);
    _penaltyShowing = false;
  }

  @override
  Widget build(BuildContext context) {
    // 配色变化时重建 MaterialApp，让 theme 重新生成
    return ValueListenableBuilder<int>(
      valueListenable: Pal.rev,
      builder: (context, _, __) => MaterialApp(
        navigatorKey: _navKey,
        title: 'PlanBox',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: AgreementGate(child: HomeShell()),
      ),
    );
  }
}