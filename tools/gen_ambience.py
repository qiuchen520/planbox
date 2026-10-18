"""生成番茄钟用的循环白噪音（WAV），放进 assets/audio/。

三种：
  white.wav  白噪音 —— 像风扇，掩盖环境杂音最有效
  pink.wav   粉红噪音 —— 更「软」，接近下小雨
  rain.wav   棕噪音 —— 低频更重，像远处的雨幕 / 海浪

循环播放最怕接缝处的「咔」声，所以多生成一点尾巴再交叉淡入淡出。
6 秒 @ 22050Hz 单声道，每个约 260KB，三个加起来不到 1MB。
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 22050
SECONDS = 6.4          # 多出来的 0.4 秒用于交叉淡化
XFADE = 0.4

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "audio")


def white(n):
    return [random.uniform(-1.0, 1.0) for _ in range(n)]


def pink(n):
    """Paul Kellet 的粉红噪声近似：三个一阶低通叠加。"""
    out = []
    b0 = b1 = b2 = 0.0
    for _ in range(n):
        w = random.uniform(-1.0, 1.0)
        b0 = 0.99765 * b0 + w * 0.0990460
        b1 = 0.96300 * b1 + w * 0.2965164
        b2 = 0.57000 * b2 + w * 1.0526913
        out.append((b0 + b1 + b2 + w * 0.1848) * 0.2)
    return out


def brown(n):
    """积分白噪音 = 棕噪音，低频更厚。加一点泄漏防止直流漂移。"""
    out = []
    last = 0.0
    for _ in range(n):
        last = last * 0.998 + random.uniform(-1.0, 1.0) * 0.02
        out.append(last * 18)
    return out


def normalize(sig, peak=0.85):
    m = max(abs(x) for x in sig) or 1.0
    k = peak / m
    return [x * k for x in sig]


def lowpass(sig, alpha=0.25):
    out = []
    last = 0.0
    for x in sig:
        last += alpha * (x - last)
        out.append(last)
    return out


def write_wav(path, sig):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = b"".join(
            struct.pack("<h", max(-32767, min(32767, int(x * 32767))))
            for x in sig
        )
        w.writeframes(frames)


def make(kind):
    n = int(RATE * SECONDS)
    if kind == "white":
        sig = white(n)
    elif kind == "pink":
        sig = lowpass(pink(n), 0.55)
    else:
        sig = lowpass(brown(n), 0.18)
    sig = normalize(sig)
    # 循环接缝处理：尾部 XFADE 秒混进开头
    x = int(RATE * XFADE)
    body = len(sig) - x
    for i in range(x):
        t = i / x
        sig[i] = sig[i] * t + sig[body + i] * (1 - t)
    return sig[:body]


def main():
    os.makedirs(OUT, exist_ok=True)
    for kind in ("white", "pink", "rain"):
        path = os.path.join(OUT, kind + ".wav")
        write_wav(path, make(kind))
        print("%-8s %6.1f KB" % (kind, os.path.getsize(path) / 1024))
    print("->", OUT)


if __name__ == "__main__":
    sys.exit(main())