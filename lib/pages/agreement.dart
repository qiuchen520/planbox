import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/db.dart';
import '../theme.dart';

/// 作者与联系方式。集中放这里，别在界面里到处硬编码字符串。
class About {
  About._();
  static const author = '汁原';
  static const qq = '2190462784';
  static const xhs = 'TsssT';
  static const qqGroup = '860358771';
  static const repo = 'github.com/qiuchen520/planbox';
  static const license = 'GPL-3.0';
  static const version = '0.6.3';
}

/// 协议版本号。以后改了协议正文就 +1，老用户会重新看到一次确认。
const int kAgreementVersion = 1;

const String kAgreementTitle = '使用协议与隐私说明';

const String kAgreementText = '''
本应用（PlanBox / 计划盒）由个人开发者「汁原」独立开发并免费发布。开始使用前，请花一分钟看完下面几条，它们同时是给你的承诺，也是作者的责任边界。

一、数据只在你本机
课表、计划、备份全部保存在你设备的本地数据库与应用私有目录中。应用不联网、不注册账号、不收集、不上传任何个人信息，也没有统计、广告或第三方 SDK 上报。

二、数据安全由你掌握
卸载应用、清空数据或更换设备都会导致数据丢失；导出的备份文件由你自行保管。作者无法访问你的设备，因此也无法替你恢复任何数据，请定期导出备份。

三、提醒不保证绝对准时
提醒依赖系统闹钟与通知权限。省电策略、后台限制、权限被关、静音或设备重启，都可能让提醒延迟或没有发出。请勿把本应用作为考试、吃药、乘车等关键场景的唯一提醒手段。

四、开源与署名
本应用按 GNU GPL-3.0 协议开源，仓库：${About.repo}。你可以自由使用、修改与分发，但请保留原作者署名与协议。

五、免责声明
本应用按「现状」提供，不附带任何明示或暗示的担保。因使用或无法使用本应用造成的任何直接或间接损失（包括但不限于数据丢失、提醒未生效、成绩或事务受影响），作者不承担法律责任。若你不接受这一点，请不要继续使用。

六、联系方式
作者：${About.author}　QQ：${About.qq}　小红书：${About.xhs}
官方 QQ 群：${About.qqGroup}

点击「同意并继续」表示你已阅读并接受以上全部内容；若不同意，请点「退出」。
''';

/// 是否已经同意过当前版本的协议
Future<bool> hasAgreed() async =>
    await DB.i.getSetting('agreed_v') == '$kAgreementVersion';

Future<void> setAgreed() => DB.i.setSetting('agreed_v', '$kAgreementVersion');

/// 弹出协议正文。返回 true = 同意。
Future<bool> showAgreementDialog(BuildContext context,
    {bool mustAgree = true}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: !mustAgree,
    builder: (ctx) => AlertDialog(
      title: Text(kAgreementTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420, maxWidth: 520),
        child: SingleChildScrollView(
          child: Text(
            kAgreementText,
            style: TextStyle(fontSize: 13, height: 1.65, color: kFg),
          ),
        ),
      ),
      actions: [
        if (mustAgree)
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('不同意', style: TextStyle(color: kFg)),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(mustAgree ? '同意并继续' : '知道了'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 首次启动的同意门。没同意过就挡在协议上，不让进主界面。
class AgreementGate extends StatefulWidget {
  final Widget child;
  const AgreementGate({super.key, required this.child});

  @override
  State<AgreementGate> createState() => _AgreementGateState();
}

class _AgreementGateState extends State<AgreementGate> {
  bool _checked = false;
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final ok = await hasAgreed();
    if (!mounted) return;
    if (ok) {
      setState(() {
        _agreed = true;
        _checked = true;
      });
      return;
    }
    setState(() => _checked = true);
    // 等首帧画完再弹，否则没有可用的 Navigator
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  Future<void> _ask() async {
    final ok = await showAgreementDialog(context);
    if (!mounted) return;
    if (ok) {
      await setAgreed();
      if (!mounted) return;
      setState(() => _agreed = true);
    } else {
      // 不同意就退出，别留一个半死不活的界面
      SystemNavigator.pop();
      if (mounted) setState(() => _agreed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_agreed) return widget.child;
    if (!_checked) {
      return Scaffold(
        backgroundColor: kBg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    // 已经弹过但用户拒绝了（有些机型 pop 不生效），给一个重试入口
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gavel_outlined, size: 40, color: kDim),
            const SizedBox(height: 14),
            Text('需要先同意使用协议才能继续',
                style: TextStyle(fontSize: 14, color: kFg)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _ask, child: const Text('查看并同意')),
          ],
        ),
      ),
    );
  }
}
