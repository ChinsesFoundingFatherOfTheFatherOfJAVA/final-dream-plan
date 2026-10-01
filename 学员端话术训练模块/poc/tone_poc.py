#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
语气维度 PoC 评分脚本（FP-30 / 08 §2，2026-09-24）
读学员语音录音 + ASR 文本，调阿里云百炼 qwen2-audio API 按"热情/亲和/自信"三角度评分，
每条样本每角度评两次（稳定性指标），输出明细 CSV；--summary 汇总三指标并给 go/no-go 结论。

用法（Windows，py launcher）：
  py tone_poc.py --from-db                  # 模式A：读库内存量语音样本（training_round_acoustic）
  py tone_poc.py --csv samples.csv          # 模式B：读补采样本清单（外部录音文件）
  py tone_poc.py --summary results_xxx.csv  # 汇总指标（可对多个结果文件重复执行）

依赖：pip install pymysql requests
凭据：直读 SpeechTraining 的 application.properties（不硬编码密码）。
"""

import argparse
import base64
import csv
import datetime
import json
import os
import re
import sys
import time

try:
    import requests
except ImportError:
    sys.exit("缺少依赖：请先执行  pip install pymysql requests")

PROPS_PATH = r"D:\JACK\final_dream\after-end\SpeechTraining\src\main\resources\application.properties"
AUDIO_ROOT = r"D:\audio"          # 本地音频根目录（audio_url 前缀 /audio 映射到这里，不符则改）
ASPECTS = ["热情", "亲和", "自信"]
RUNS = 3                           # 每条每角度评几次（奇数次可取中位数；2026-09-24 由2改3：单次方差大，多评取中抑制）
API_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
# 2026-09-24 实测：qwen2-audio-instruct 已下架（404）；可用音频理解模型为 omni 系列。
# 同一段录音四模型打分 25/35/25/65（qwen3.8-omni-flash / qwen3.5-omni-plus / qwen-omni-turbo / qwen3-omni-flash），
# 跨模型分差大——PoC 期间必须固定同一模型（--model 可换，换模型前后结果不可比）。
MODEL = "qwen3.8-omni-flash"
SLEEP_BETWEEN_CALLS = 0.5

PROMPT = (
    "你是话术训练的语音表现评审。听这段学员录音（ASR 转写文本：{text}），"
    "只从\"{aspect}\"这一个角度给 0-100 整数分。\n"
    "评分锚点（按可听特征计分，逐条对照）：\n"
    "- 80-100：{aspect}特征密集出现——3 处及以上明确的语调上扬/重音强调/能量抬升段落，且贯穿全程，听感有感染力\n"
    "- 60-79：{aspect}特征存在但稀疏——1~2 处明确特征，其余段落平稳，整体合格不突出\n"
    "- 40-59：{aspect}特征基本缺失——全程单一节奏/单一音量，仅个别词有轻微变化，但表达仍完整清晰\n"
    "- 0-39：与{aspect}相悖——特征完全不存在且呈现相反气质（如冷漠、迟疑、破碎）\n"
    "判定纪律：\n"
    "1. 只统计听到的声学证据（语调起伏、重音、音量变化、语速变化、停顿控制），逐条对照上面锚点后给分；\n"
    "2. 庄重、沉稳、从容的风格不等于差——若其停顿控制有力、吐字笃定，按其与\"{aspect}\"的契合度计分，不因风格严肃而扣分；\n"
    "3. 转写文本仅作内容参考，不作为评分依据；录音中的掌声、噪声等非人声忽略；\n"
    "4. 打分克制：没有充分证据不要给两端极值。\n"
    "只输出 JSON：{{\"score\": N, \"evidence\": \"列出你统计到的特征条数与位置（如：第2句重音、结尾上扬共2处），一句话\"}}"
)


def load_props(path):
    props = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            props[k.strip()] = v.strip()
    return props


def parse_jdbc_url(url):
    m = re.match(r"jdbc:mysql://([^:/]+):(\d+)/([^?]+)", url)
    if not m:
        sys.exit("无法解析 jdbc url: " + url)
    return m.group(1), int(m.group(2)), m.group(3)


def audio_url_to_path(audio_url):
    # audio_url 形如 /audio/asr/46.wav → AUDIO_ROOT + /asr/46.wav
    rel = audio_url
    for prefix in ("/audio/",):
        if rel.startswith(prefix):
            rel = rel[len(prefix) - 1:]
            break
    return os.path.join(AUDIO_ROOT, rel.lstrip("/\\").replace("/", os.sep))


def fetch_db_samples(props):
    import pymysql
    host, port, db = parse_jdbc_url(props["spring.datasource.url"])
    conn = pymysql.connect(host=host, port=port, user=props["spring.datasource.username"],
                           password=props["spring.datasource.password"], database=db,
                           charset="utf8mb4", cursorclass=pymysql.cursors.DictCursor)
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT a.message_id, a.round_no, m.content, m.audio_url "
                "FROM training_round_acoustic a "
                "JOIN training_session_message m ON m.id = a.message_id "
                "WHERE m.audio_url IS NOT NULL AND m.audio_url <> '' "
                "ORDER BY a.message_id")
            rows = cur.fetchall()
    finally:
        conn.close()
    samples = []
    for r in rows:
        path = audio_url_to_path(r["audio_url"])
        if not os.path.isfile(path):
            print("[跳过] 文件不存在: %s (message_id=%s)" % (path, r["message_id"]))
            continue
        samples.append({"id": "db_%s" % r["message_id"], "file": path,
                        "text": r["content"] or "", "label": ""})
    return samples


def fetch_csv_samples(csv_path):
    samples = []
    with open(csv_path, encoding="utf-8-sig", newline="") as f:
        for i, row in enumerate(csv.DictReader(f), start=2):
            fpath = (row.get("file") or "").strip()
            if not fpath:
                continue
            if not os.path.isfile(fpath):
                print("[跳过] 文件不存在: %s (第%d行)" % (fpath, i))
                continue
            ext = os.path.splitext(fpath)[1].lower()
            if ext not in MIME_BY_EXT:
                print("[跳过] 不支持的音频格式 %s: %s (第%d行)" % (ext, fpath, i))
                continue
            samples.append({"id": row.get("id") or ("ext_%02d" % i), "file": fpath,
                            "text": (row.get("text") or "").strip(),
                            "label": (row.get("label") or "").strip()})
    return samples


def load_labels(path):
    labels = {}
    if not path:
        return labels
    with open(path, encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            sid = (row.get("id") or "").strip()
            lab = (row.get("label") or "").strip()
            if sid and lab:
                labels[sid] = lab
    return labels


MIME_BY_EXT = {".wav": "audio/wav", ".mp3": "audio/mpeg", ".flac": "audio/flac",
               ".m4a": "audio/mp4", ".ogg": "audio/ogg", ".aac": "audio/aac"}


def call_qwen_audio(api_key, wav_path, text, aspect):
    ext = os.path.splitext(wav_path)[1].lower()
    mime = MIME_BY_EXT.get(ext, "audio/wav")
    with open(wav_path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("ascii")
    payload = {
        "model": MODEL,
        "temperature": 0.1,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": PROMPT.format(aspect=aspect, text=text or "（无转写文本）")},
                {"type": "input_audio",
                 "input_audio": {"data": "data:%s;base64,%s" % (mime, b64)}},
            ],
        }],
    }
    last_err = None
    for attempt in (1, 2):  # 失败重试一次
        try:
            r = requests.post(API_URL, headers={"Authorization": "Bearer " + api_key},
                              json=payload, timeout=180)
            if r.status_code != 200:
                # 带上响应体：404=模型名不存在（已踩过：qwen2-audio-instruct 下架）、401=key 失效、429=限流
                raise ValueError("HTTP %d: %s" % (r.status_code, r.text[:200]))
            content = r.json()["choices"][0]["message"]["content"]
            m = re.search(r"\{.*\}", content, re.S)
            if not m:
                raise ValueError("回复中无 JSON: " + content[:200])
            obj = json.loads(m.group(0))
            score = int(round(float(obj["score"])))
            if not 0 <= score <= 100:
                raise ValueError("分数越界: %s" % score)
            return score, str(obj.get("evidence") or obj.get("reason", ""))[:300]
        except Exception as e:
            last_err = "%s (attempt %d)" % (e, attempt)
            time.sleep(3)
    return None, "ERROR: " + str(last_err)


def run_scoring(samples, api_key, out_path):
    fieldnames = ["sample_id", "file", "text", "aspect", "label", "run", "score", "reason"]
    total = len(samples) * len(ASPECTS) * RUNS
    done = 0
    with open(out_path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for s in samples:
            for aspect in ASPECTS:
                for run in range(1, RUNS + 1):
                    score, reason = call_qwen_audio(api_key, s["file"], s["text"], aspect)
                    w.writerow({"sample_id": s["id"], "file": s["file"], "text": s["text"],
                                "aspect": aspect, "label": s["label"], "run": run,
                                "score": "" if score is None else score, "reason": reason})
                    f.flush()
                    done += 1
                    print("[%d/%d] %s %s run%d -> %s" % (done, total, s["id"], aspect, run,
                                                          score if score is not None else reason[:60]))
                    time.sleep(SLEEP_BETWEEN_CALLS)
    print("\n明细已写入: %s" % out_path)
    print("下一步: py tone_poc.py --summary %s" % out_path)


def summarize(in_paths):
    rows = []
    for p in in_paths:
        with open(p, encoding="utf-8-sig", newline="") as f:
            rows.extend(csv.DictReader(f))

    def to_score(v):
        try:
            return int(v)
        except (TypeError, ValueError):
            return None

    # 按 (sample, aspect) 聚合；同时计算中位数（多评取中抑制单次漂移）
    def median(v):
        s = sorted(v)
        n = len(s)
        return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2

    agg = {}
    for r in rows:
        key = (r["sample_id"], r["aspect"])
        d = agg.setdefault(key, {"scores": [], "label": r.get("label", "")})
        v = to_score(r.get("score"))
        if v is not None:
            d["scores"].append(v)
    for d in agg.values():
        d["median"] = median(d["scores"]) if d["scores"] else None

    print("=" * 64)
    print("语气 PoC 三指标汇总（样本 %d 条 × 角度 %d）" %
          (len({k[0] for k in agg}), len(ASPECTS)))
    print("=" * 64)

    # 指标1 区分度（每角度全样本极差；按中位数算——中位数本身已抑制单次漂移）
    ok_range = True
    print("\n[指标1] 区分度（每角度按中位数的极差，达标线 >= 25）")
    for aspect in ASPECTS:
        scores = [d["median"] for (sid, a), d in agg.items() if a == aspect and d["median"] is not None]
        if not scores:
            print("  %s: 无数据" % aspect)
            ok_range = False
            continue
        spread = max(scores) - min(scores)
        flag = "PASS" if spread >= 25 else "FAIL"
        ok_range = ok_range and spread >= 25
        print("  %s: min=%.0f max=%.0f 极差=%.0f  %s" % (aspect, min(scores), max(scores), spread, flag))

    # 指标2 稳定性：a) 原始逐次差（模型单次方差，观测用）
    #             b) 中位数的相邻差（Phase 2 落地口径：多评取中后还剩多少漂移）
    ok_stab = True
    diffs = []
    for (sid, a), d in agg.items():
        if len(d["scores"]) >= 2:
            diffs.append(max(d["scores"]) - min(d["scores"]))
    avg_raw = sum(diffs) / len(diffs) if diffs else None
    # 中位数稳定性：对同一(样本,角度)把奇数次评分逐一去掉一个再取中位数，看中位数本身的波动
    med_diffs = []
    for (sid, a), d in agg.items():
        s = d["scores"]
        if len(s) >= 3:
            meds = []
            for i in range(len(s)):
                rest = [x for j, x in enumerate(s) if j != i]
                meds.append(median(rest))
            med_diffs.append(max(meds) - min(meds))
        elif len(s) == 2:
            med_diffs.append(abs(s[0] - s[1]))  # 只有两票时中位数=均值，稳定性即两票差
    avg_med = sum(med_diffs) / len(med_diffs) if med_diffs else None
    print("\n[指标2] 稳定性（达标线 <= 10）")
    if avg_raw is not None:
        print("  原始单次最大差均值: %.1f  %s（观测：模型单次方差）"
              % (avg_raw, "PASS" if avg_raw <= 10 else "FAIL"))
    if avg_med is not None:
        flag = "PASS" if avg_med <= 10 else "FAIL"
        ok_stab = avg_med <= 10
        print("  多评取中后漂移:    %.1f  %s（Phase 2 落地口径）" % (avg_med, flag))
    else:
        ok_stab = False
        print("  无成对数据: SKIP")

    # 指标3 方向正确性（带 label 的样本：好 > 差；按中位数算）
    labeled = {}
    for (sid, a), d in agg.items():
        if d["label"] and d["median"] is not None:
            labeled.setdefault(d["label"], []).append(d["median"])
    ok_dir = True
    print("\n[指标3] 方向正确性（label=好 的均分应高于 label=差）")
    if "好" in labeled and "差" in labeled:
        good = sum(labeled["好"]) / len(labeled["好"])
        bad = sum(labeled["差"]) / len(labeled["差"])
        flag = "PASS" if good > bad else "FAIL"
        ok_dir = good > bad
        print("  好=%s条 均分%.1f | 差=%s条 均分%.1f  %s"
              % (len(labeled["好"]), good, len(labeled["差"]), bad, flag))
    else:
        ok_dir = False
        print("  无带 label 样本（补采样本请在 CSV/labels 文件填 label 列）: SKIP")

    print("\n" + "=" * 64)
    verdict = "GO" if (ok_range and ok_stab and ok_dir) else \
              "NO-GO（或补样本后重跑）"
    print("结论: %s   [区分度 %s | 稳定性 %s | 方向 %s]"
          % (verdict, "PASS" if ok_range else "FAIL",
             "PASS" if ok_stab else "FAIL", "PASS" if ok_dir else "SKIP/FAIL"))
    print("说明: go 则进入 Phase 2（tone 指标入链路，见 08 §2.3）；")
    print("      no-go 则语气维度维持不评，留存数据继续积累。")


def main():
    ap = argparse.ArgumentParser(description="语气维度 PoC 评分脚本")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--from-db", action="store_true", help="读库内存量语音样本")
    g.add_argument("--csv", metavar="SAMPLES_CSV", help="读补采样本清单 CSV")
    g.add_argument("--summary", nargs="+", metavar="RESULTS_CSV", help="汇总结果文件")
    ap.add_argument("--labels", metavar="LABELS_CSV", help="可选：sample_id,label 标注文件")
    ap.add_argument("--runs", type=int, default=3, help="每条每角度评分次数（默认3，奇数便于取中位数）")
    ap.add_argument("--model", metavar="MODEL_ID", help="可选：音频模型（默认 qwen3.8-omni-flash；换模型前后结果不可比）")
    ap.add_argument("--out", metavar="OUT_CSV", help="输出文件名（默认自动带时间戳）")
    args = ap.parse_args()

    global MODEL, RUNS
    if args.model:
        MODEL = args.model
    if args.runs:
        RUNS = max(1, args.runs)

    if args.summary:
        summarize(args.summary)
        return

    props = load_props(PROPS_PATH)
    api_key = props.get("dashscope.api-key")
    if not api_key:
        sys.exit("application.properties 中未找到 dashscope.api-key")

    if args.from_db:
        samples = fetch_db_samples(props)
    else:
        samples = fetch_csv_samples(args.csv)
    if args.labels:
        labels = load_labels(args.labels)
        for s in samples:
            s["label"] = labels.get(s["id"], s["label"])
    if not samples:
        sys.exit("没有可用样本（检查音频文件是否存在）")

    print("样本 %d 条 × 角度 %d × 每角度 %d 次 = 共 %d 次调用"
          % (len(samples), len(ASPECTS), RUNS, len(samples) * len(ASPECTS) * RUNS))
    out = args.out or ("results_%s.csv"
                       % datetime.datetime.now().strftime("%Y%m%d_%H%M"))
    run_scoring(samples, api_key, out)


if __name__ == "__main__":
    main()
