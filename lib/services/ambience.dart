import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// 专注时播放的循环环境音。
///
/// 音频是用 tools/gen_ambience.py 现算出来的（三个 6 秒的循环 WAV），
/// 加起来不到 1MB，不依赖网络，也不带任何第三方素材的版权问题。
enum NoiseKind { none, white, pink, rain }

extension NoiseKindX on NoiseKind {
  String get label => switch (this) {
        NoiseKind.none => '安静',
        NoiseKind.white => '白噪音',
        NoiseKind.pink => '粉噪',
        NoiseKind.rain => '雨声',
      };

  String get asset => switch (this) {
        NoiseKind.none => '',
        NoiseKind.white => 'assets/audio/white.wav',
        NoiseKind.pink => 'assets/audio/pink.wav',
        NoiseKind.rain => 'assets/audio/rain.wav',
      };
}

class Ambience {
  Ambience._();
  static final Ambience i = Ambience._();

  final AudioPlayer _player = AudioPlayer();
  NoiseKind kind = NoiseKind.none;

  /// 0~1，默认偏小一点，别盖过耳朵
  double volume = 0.45;

  /// 播放失败（解码不支持、音频设备被占用等）时记下来，界面可以提示
  String? lastError;

  Future<void> setKind(NoiseKind k, {bool resume = true}) async {
    if (k == kind && _player.playing) return;
    kind = k;
    lastError = null;
    try {
      if (k == NoiseKind.none) {
        await _player.stop();
        return;
      }
      await _player.setAsset(k.asset);
      await _player.setLoopMode(LoopMode.one);
      await _player.setVolume(volume);
      if (resume) await _player.play();
    } catch (e) {
      lastError = '$e';
      debugPrint('环境音播放失败：$e');
      kind = NoiseKind.none;
    }
  }

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, 1.0);
    try {
      await _player.setVolume(volume);
    } catch (_) {
      // 播放器还没加载过音频时设音量会抛异常，忽略即可，下次播放会带上
    }
  }

  /// 暂停但不卸载，切后台再回来能接着响
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (_) {}
  }

  Future<void> resume() async {
    if (kind == NoiseKind.none) return;
    try {
      await _player.play();
    } catch (e) {
      debugPrint('恢复环境音失败：$e');
    }
  }

  Future<void> stop() async {
    kind = NoiseKind.none;
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}