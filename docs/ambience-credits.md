# 环境音素材来源

专注时播放的三个循环音，原始素材全部取自 Wikimedia Commons 的
**Public domain**（公有领域）录音，不涉及署名义务，也没有再分发限制。

| 仓库文件 | 原始文件 | 作者 | 许可 | 原始时长 |
|---|---|---|---|---|
| `assets/audio/rain.wav` | [Rain (1).ogg](https://commons.wikimedia.org/wiki/File:Rain_(1).ogg) | Ezwa | Public domain | 44.9 s |
| `assets/audio/white.wav` | [White-noise-sound-20sec-mono-44100Hz.ogg](https://commons.wikimedia.org/wiki/File:White-noise-sound-20sec-mono-44100Hz.ogg) | J. Stolfi | Public domain | 20.0 s |
| `assets/audio/pink.wav` | [Pink.Noise.ogg](https://commons.wikimedia.org/wiki/File:Pink.Noise.ogg) | — | Public domain | 10.0 s |

处理流程（`tools/gen_ambience.py`）：

1. 用 ffmpeg 转成 22050 Hz 单声道 16 bit PCM
2. 白噪音再过一遍一阶低通，削掉 6 kHz 以上的刺耳成分
3. 去直流偏置
4. 截取 15 / 10 / 20 秒，把尾部 0.6 秒用等功率曲线交叉淡入开头，消掉循环接缝的「咔」
5. 按 RMS 归一（-21 / -21 / -19 dBFS），保证三者切换时响度接近

重新生成：

```bash
mkdir -p /tmp/raw && cd /tmp/raw
# 从上面的 Commons 链接下载对应的 .ogg，然后
ffmpeg -i rain.ogg  -ac 1 -ar 22050 -c:a pcm_s16le rain_raw.wav
ffmpeg -i white.ogg -ac 1 -ar 22050 -c:a pcm_s16le white_raw.wav
ffmpeg -i pink.ogg  -ac 1 -ar 22050 -c:a pcm_s16le pink_raw.wav
cd <仓库根目录>
python3 tools/gen_ambience.py /tmp/raw
```
