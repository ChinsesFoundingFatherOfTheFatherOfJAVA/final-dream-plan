#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""临时诊断：测试候选模型是否接受 audio 输入（PoC 脚本 404 排查）"""
import base64, json, re, sys, requests

KEY = None
for line in open(r"D:\JACK\final_dream\after-end\SpeechTraining\src\main\resources\application.properties", encoding="utf-8"):
    if line.startswith("dashscope.api-key="):
        KEY = line.split("=", 1)[1].strip()
        break

WAV = r"D:\audio\asr\103.wav"
with open(WAV, "rb") as f:
    b64 = base64.b64encode(f.read()).decode("ascii")

CANDIDATES = ["qwen3.8-omni-flash", "qwen3.5-omni-plus", "qwen-omni-turbo", "qwen3-omni-flash"]
PROMPT = ('你是话术训练的语音表现评审。听这段学员录音，从"热情"角度给 0-100 分。'
          '只输出 JSON：{"score": N, "reason": "一句话依据"}')

for model in CANDIDATES:
    payload = {
        "model": model,
        "temperature": 0.1,
        "messages": [{"role": "user", "content": [
            {"type": "text", "text": PROMPT},
            {"type": "input_audio", "input_audio": {"data": "data:audio/wav;base64," + b64}},
        ]}],
    }
    try:
        r = requests.post("https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
                          headers={"Authorization": "Bearer " + KEY}, json=payload, timeout=120)
        if r.status_code == 200:
            content = r.json()["choices"][0]["message"]["content"]
            print("[%s] OK -> %s" % (model, content[:150].replace("\n", " ")))
        else:
            print("[%s] HTTP %d -> %s" % (model, r.status_code, r.text[:200].replace("\n", " ")))
    except Exception as e:
        print("[%s] EXC -> %s" % (model, e))
