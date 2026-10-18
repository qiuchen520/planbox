#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把原始录音处理成可无缝循环的 WAV，放进 assets/audio/。

素材来源（全部 Public domain，见 docs/ambience-credits.md）：
  rain  : Wikimedia Commons "Rain (1).ogg"                    by Ezwa      44.9s
  white : "White-noise-sound-20sec-mono-44100Hz.ogg"          by J. Stolfi 20.0s
  pink  : "Pink.Noise.ogg"                                                 10.0s

用法：
  python3 tools/gen_ambience.py <原始wav目录>
原始文件先转成 22050Hz 单声道 16bit：
  ffmpeg -i xxx.ogg -ac 1 -ar 22050 -c:a pcm_s16le xxx_raw.wav

调音思路：
  白噪音原始是全频段平坦的，直接放出来就是「嘶——」，刺耳。
  这里用两级一阶低通把它做成「空调 / 风扇」那种气流底噪，
  再用高通削掉 100 Hz 以下的轰鸣（那部分只是让扬声器发闷，不助眠）。
"""
import math
import os
import struct
import sys
import wave

RATE = 22050
XFADE = 0.6          # 接缝交叉淡化秒数

# lowpass / highpass 都是级联的 alpha 列表，空列表表示不动
SPEC = {
    'white': dict(raw='white_raw.wav', keep=15.0,
                  lowpass=[0.22, 0.22], highpass=[0.030], target_rms_db=-20.0),
    'pink':  dict(raw='pink_raw.wav',  keep=10.0,
                  lowpass=[], highpass=[0.030], target_rms_db=-20.0),
    'rain':  dict(raw='rain_raw.wav',  keep=20.0,
                  lowpass=[], highpass=[0.020], target_rms_db=-17.5),
}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'audio')


def read_wav(path):
    with wave.open(path, 'rb') as w:
        n = w.getnframes()
        data = w.readframes(n)
        return [x / 32768.0 for x in struct.unpack('<%dh' % n, data)]


def write_wav(path, sig):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(
            struct.pack('<h', max(-32767, min(32767, int(x * 32767))))
            for x in sig
        ))


def one_pole_lp(sig, alpha):
    out = []
    last = sig[0] if sig else 0.0
    for x in sig:
        last += alpha * (x - last)
        out.append(last)
    return out


def apply_lowpass(sig, alphas):
    for a in alphas:
        sig = one_pole_lp(sig, a)
    return sig


def apply_highpass(sig, alphas):
    """x - 低通(x) 就是一阶高通"""
    for a in alphas:
        lp = one_pole_lp(sig, a)
        sig = [x - y for x, y in zip(sig, lp)]
    return sig


def rms_normalize(sig, target_db):
    """按 RMS 归一，不用峰值 —— 否则噪声听起来会忽大忽小"""
    n = len(sig)
    if not n:
        return sig
    ms = sum(x * x for x in sig) / n
    rms = ms ** 0.5
    if rms <= 1e-9:
        return sig
    k = (10 ** (target_db / 20.0)) / rms
    return [x * k for x in sig]


def make_loop(sig, keep_sec):
    """截 keep_sec 秒，把尾部 XFADE 秒等功率交叉淡入开头，消掉接缝的「咔」"""
    n = min(int(RATE * keep_sec), len(sig))
    body = sig[:n]
    x = int(RATE * XFADE)
    if len(body) <= 2 * x:
        return body
    head = []
    for i in range(x):
        t = i / x
        a = math.cos(t * math.pi / 2)
        b = math.sin(t * math.pi / 2)
        head.append(body[i] * a + body[-x + i] * b)
    return head + body[x:-x]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    for kind, cfg in SPEC.items():
        raw = os.path.join(src, cfg['raw'])
        if not os.path.exists(raw):
            print('缺少', raw)
            continue
        sig = read_wav(raw)
        sig = apply_lowpass(sig, cfg['lowpass'])
        sig = apply_highpass(sig, cfg['highpass'])
        sig = make_loop(sig, cfg['keep'])
        sig = rms_normalize(sig, cfg['target_rms_db'])
        peak = max(abs(x) for x in sig) or 1.0
        if peak > 0.95:                      # 留余量，防爆音
            sig = [x * (0.95 / peak) for x in sig]
        path = os.path.join(OUT, kind + '.wav')
        write_wav(path, sig)
        print('%-6s %6.0f KB  %4.1fs' % (kind, os.path.getsize(path) / 1024,
                                         len(sig) / float(RATE)))
    print('->', OUT)


if __name__ == '__main__':
    main()