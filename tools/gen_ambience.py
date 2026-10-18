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
"""
import math
import os
import struct
import sys
import wave

RATE = 22050
XFADE = 0.6          # 接缝交叉淡化秒数

# 每个音源截多长、要不要再压一点高频（白噪音原样太刺耳）
SPEC = {
    'white': dict(raw='white_raw.wav', keep=15.0, lowpass=0.25, target_rms_db=-21.0),
    'pink':  dict(raw='pink_raw.wav',  keep=10.0, lowpass=1.00, target_rms_db=-21.0),
    'rain':  dict(raw='rain_raw.wav',  keep=20.0, lowpass=1.00, target_rms_db=-19.0),
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


def lowpass(sig, alpha):
    """一阶低通，alpha=1 表示不动"""
    if alpha >= 1.0:
        return sig
    out = []
    last = sig[0] if sig else 0.0
    for x in sig:
        last += alpha * (x - last)
        out.append(last)
    return out


def dc_block(sig):
    """去掉直流偏置，否则扬声器会被一直顶着"""
    n = len(sig)
    if not n:
        return sig
    mean = sum(sig) / n
    return [x - mean for x in sig]


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
        sig = lowpass(sig, cfg['lowpass'])
        sig = dc_block(sig)
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