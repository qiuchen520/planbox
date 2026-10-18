import 'dart:async';

import 'package:flutter/material.dart';

import '../services/update_checker.dart';
import '../theme.dart';
import 'agreement.dart';

/// 检查更新的完整流程：查询 → 测速 → 下载 → 拉起安装器。
///
/// 全程一个对话框，状态自己推着走，用户只需要在「要不要下」和
/// 最后安装系统弹窗上点两下。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const UpdateDialog(),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _Stage { checking, latest, failed, found, probing, downloading, ready }

class _UpdateDialogState extends State<UpdateDialog> {
  _Stage _stage = _Stage.checking;
  String _error = '';
  UpdateInfo? _info;
  List<Mirror> _mirrors = const [];
  int _mirrorIndex = 0;
  int _got = 0;
  int _total = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _stage = _Stage.checking;
      _error = '';
    });
    String? err;
    final info = await UpdateChecker.latest(error: (e) => err = e);
    if (!mounted) return;
    if (info == null) {
      setState(() {
        if (err == null) {
          _stage = _Stage.latest;
        } else {
          _stage = _Stage.failed;
          _error = err!;
        }
      });
      return;
    }
    setState(() {
      _info = info;
      _stage = _Stage.found;
    });
  }

  /// 开始下载：先测所有线路，挑最快的那个下；失败了换下一名
  Future<void> _startDownload() async {
    final info = _info;
    if (info == null) return;
    setState(() {
      _stage = _Stage.probing;
      _mirrors = const [];
      _mirrorIndex = 0;
      _got = 0;
      _total = info.size;
    });
    final ranked = await UpdateChecker.rank(info.url);
    if (!mounted) return;
    setState(() {
      _mirrors = ranked;
      _stage = _Stage.downloading;
    });
    await _enqueueAt(0);
  }

  Future<void> _enqueueAt(int index) async {
    final info = _info;
    if (info == null) return;
    final usable = _mirrors.where((m) => m.ok).toList();
    final list = usable.isEmpty ? _mirrors : usable;
    if (index >= list.length) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = '所有线路都下不动，过会儿再试，或者去 GitHub 页面手动下';
      });
      return;
    }
    setState(() => _mirrorIndex = index);
    final m = list[index];
    final name = 'PlanBox-${info.version}-${m.name}.apk'.replaceAll('/', '_');
    final id = await UpdateChecker.enqueue(m.url, name);
    if (id < 0) {
      await _enqueueAt(index + 1);
      return;
    }
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 800), (_) async {
      final st = await UpdateChecker.status();
      if (!mounted) return;
      final state = '${st['state'] ?? ''}';
      final got = (st['bytes'] as num?)?.toInt() ?? 0;
      final total = (st['total'] as num?)?.toInt() ?? _total;
      if (total > 0) _total = total;
      if (got > 0) _got = got;
      setState(() {});
      if (state == 'ok') {
        _poll?.cancel();
        setState(() => _stage = _Stage.ready);
      } else if (state == 'failed') {
        _poll?.cancel();
        // 这条线断了（限速、被墙、404），换下一条
        await _enqueueAt(index + 1);
      }
    });
  }

  Future<void> _install() async {
    final r = await UpdateChecker.install();
    if (!mounted) return;
    if (r == 'ok') {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _error = r == 'perm'
          ? '刚才跳到了系统设置，把「允许安装未知应用」给计划盒打开，回来再点一次安装。'
          : '系统没让安装器起来，去「计划盒/Download」目录里手动点那个 apk。';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kCard,
      title: Text(_title, style: TextStyle(color: kFg, fontSize: 15.5)),
      content: SizedBox(width: 320, child: _body()),
      actions: _actions(),
    );
  }

  String get _title => switch (_stage) {
        _Stage.checking => '正在检查更新',
        _Stage.latest => '已是最新版本',
        _Stage.failed => '检查失败',
        _Stage.found => '发现新版本',
        _Stage.probing => '正在测速',
        _Stage.downloading => '正在下载',
        _Stage.ready => '下载完成',
      };

  Widget _body() {
    switch (_stage) {
      case _Stage.checking:
        return Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text('问一下 GitHub…', style: TextStyle(color: kDim)),
          ],
        );
      case _Stage.latest:
        return Text('当前 v${About.version} 已经是最新的了。',
            style: TextStyle(color: kDim, height: 1.6));
      case _Stage.failed:
        return Text(_error, style: TextStyle(color: kDanger, height: 1.6));
      case _Stage.found:
        final i = _info!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('新版本 v${i.version} · ${i.sizeText}',
                style: TextStyle(color: kFg, fontSize: 13, height: 1.6)),
            const SizedBox(height: 8),
            Text(
              _trimNotes(i.notes),
              style: TextStyle(color: kDim, fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: 10),
            Text('会用几条加速线路里最快的那条下载，都不通就直连。',
                style: TextStyle(color: kFaint, fontSize: 11.5, height: 1.6)),
          ],
        );
      case _Stage.probing:
        return Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text('给 5 条线路测速…', style: TextStyle(color: kDim)),
          ],
        );
      case _Stage.downloading:
        final pct =
            _total <= 0 ? 0.0 : (_got / _total).clamp(0.0, 1.0).toDouble();
        final line = _mirrors.isEmpty
            ? ''
            : _currentLine;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: _total <= 0 ? null : pct,
              minHeight: 5,
              backgroundColor: kLine.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 10),
            Text(
              _total <= 0
                  ? '已下载 ${(_got / 1024 / 1024).toStringAsFixed(1)} MB'
                  : '${(pct * 100).toStringAsFixed(0)}% · '
                      '${(_got / 1024 / 1024).toStringAsFixed(1)} / '
                      '${(_total / 1024 / 1024).toStringAsFixed(1)} MB',
              style: TextStyle(color: kDim, fontSize: 12),
            ),
            if (line.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('线路：$line', style: TextStyle(color: kFaint, fontSize: 11.5)),
            ],
          ],
        );
      case _Stage.ready:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('下载好了，点「安装」交给系统安装器。',
                style: TextStyle(color: kDim, height: 1.6)),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_error,
                  style: TextStyle(color: kDanger, fontSize: 12, height: 1.6)),
            ],
          ],
        );
    }
  }

  String get _currentLine {
    final usable = _mirrors.where((m) => m.ok).toList();
    final list = usable.isEmpty ? _mirrors : usable;
    if (_mirrorIndex >= list.length) return '';
    final m = list[_mirrorIndex];
    return '${m.name}（约 ${m.kbps.toStringAsFixed(0)} KB/s）';
  }

  List<Widget> _actions() {
    switch (_stage) {
      case _Stage.checking:
      case _Stage.probing:
      case _Stage.downloading:
        return [
          TextButton(
            onPressed: () {
              _poll?.cancel();
              Navigator.of(context).pop();
            },
            child: Text('取消', style: TextStyle(color: kDim)),
          ),
        ];
      case _Stage.latest:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('好', style: TextStyle(color: kAcc)),
          ),
        ];
      case _Stage.failed:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('关闭', style: TextStyle(color: kDim)),
          ),
          TextButton(
            onPressed: _check,
            child: Text('重试', style: TextStyle(color: kAcc)),
          ),
        ];
      case _Stage.found:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('以后再说', style: TextStyle(color: kDim)),
          ),
          FilledButton(
            onPressed: _startDownload,
            child: const Text('下载'),
          ),
        ];
      case _Stage.ready:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('稍后', style: TextStyle(color: kDim)),
          ),
          FilledButton(
            onPressed: _install,
            child: const Text('安装'),
          ),
        ];
    }
  }

  /// release notes 经常很长，只摘前几行给对话框
  String _trimNotes(String raw) {
    final lines = raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(6)
        .toList();
    if (lines.isEmpty) return '（这个版本没写说明）';
    return lines.join('\n');
  }
}