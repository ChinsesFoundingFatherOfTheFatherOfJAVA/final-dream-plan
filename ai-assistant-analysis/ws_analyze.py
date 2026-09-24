import json, io, sys
from collections import Counter

with open(r"E:\File\train.chinajack.com.har", 'r', encoding='utf-8') as f:
    har = json.load(f)

out = io.StringIO()
def P(*a):
    print(*a, file=out)

for e in har['log']['entries']:
    url = e.get('request', {}).get('url', '')
    msgs = e.get('_webSocketMessages')
    if not msgs or '/ws/chat' not in url:
        continue
    P(f"=== WS {url[:130]} frames={len(msgs)} ===")
    events = Counter()
    sends = []
    interesting = []  # non part-content frames

    for i, m in enumerate(msgs):
        data = m.get('data', '')
        try:
            j = json.loads(data)
        except Exception:
            j = {}
        if m.get('type') == 'send':
            sends.append((i, j))
        ev = j.get('event') or j.get('type')
        events[ev] += 1
        # keep everything except streaming text deltas
        if ev in ('part-content',):
            # keep only if delta is not text_delta (rare)
            d = j.get('data', {}).get('delta', {})
            if d.get('type') == 'text_delta':
                continue
        interesting.append((i, m.get('type'), j))

    P("EVENT HISTOGRAM:", dict(events))
    P(f"\n--- USER SENDS ({len(sends)}) ---")
    for i, j in sends:
        P(f"\n[frame {i}] SEND:")
        P(json.dumps(j, ensure_ascii=False, indent=1)[:2500])

    P(f"\n--- NON-TEXT EVENTS ({len(interesting)}) ---")
    for i, dirn, j in interesting:
        ev = j.get('event') or j.get('type')
        s = json.dumps(j, ensure_ascii=False)
        P(f"\n[frame {i}] {dirn} {ev}:")
        P(s[:1800])

with open(r"D:\JACK\plan\ai-assistant-analysis\ws-protocol.txt", 'w', encoding='utf-8') as f:
    f.write(out.getvalue())
print("written, events summary:")
# also print histogram to console safely
for e in har['log']['entries']:
    url = e.get('request', {}).get('url', '')
    msgs = e.get('_webSocketMessages')
    if msgs and '/ws/chat' in url:
        events = Counter()
        sends = 0
        for m in msgs:
            try: j = json.loads(m.get('data','{}'))
            except Exception: j = {}
            if m.get('type')=='send': sends+=1
            events[j.get('event') or j.get('type') or '?'] += 1
        print(len(msgs), 'frames,', sends, 'sends')
        for k,v in events.most_common():
            print(' ', k, v)
