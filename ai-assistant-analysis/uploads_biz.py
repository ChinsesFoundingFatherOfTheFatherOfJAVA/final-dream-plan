import json, io

with open(r"E:\File\train.chinajack.com.har", 'r', encoding='utf-8') as f:
    har = json.load(f)

out = io.StringIO()
def P(*a): print(*a, file=out)

# 1. find upload-related requests (any domain)
P("=== UPLOAD-LIKE REQUESTS ===")
for e in har['log']['entries']:
    req = e.get('request', {})
    url = req.get('url', '')
    if any(k in url.lower() for k in ['upload', '/file', 'oss', 'storage', 'attach']) and 'yunxuetang' in url:
        P(f"{req.get('method')} {url[:200]}")
        pd = req.get('postData', {})
        if pd.get('params'):
            for p in pd['params'][:8]:
                P(f"   param: {p.get('name')} = {str(p.get('value'))[:80]} ({p.get('contentType','')[:40]})")
        elif pd.get('text'):
            P(f"   body: {pd['text'][:300]}")
        rc = e.get('response', {}).get('content', {})
        P(f"   resp: {rc.get('text','')[:400]}")
        P()

# 2. from WS frames: reassemble the full data parts of key biz events
P("=== KEY BIZ DATA PARTS (reassembled) ===")
for e in har['log']['entries']:
    url = e.get('request', {}).get('url', '')
    msgs = e.get('_webSocketMessages')
    if not msgs or '/ws/chat' not in url:
        continue
    # reassemble parts per message
    parts = {}   # (messageId, index) -> {contentType, buffer}
    order = []
    for m in msgs:
        try: j = json.loads(m.get('data', '{}'))
        except Exception: continue
        if m.get('type') != 'receive': continue
        ev = j.get('event')
        d = j.get('data', {})
        if ev == 'part-start':
            key = (d.get('messageId'), d.get('index'))
            parts[key] = {'ct': d.get('contentType'), 'buf': ''}
            order.append(key)
        elif ev == 'part-content':
            key = (d.get('messageId'), d.get('index'))
            if key in parts:
                delta = d.get('delta', {})
                parts[key]['buf'] += delta.get('data') if delta.get('type') == 'data_delta' else delta.get('text', '')
    for key in order:
        p = parts[key]
        if p['ct'] == 'data':
            try:
                bj = json.loads(p['buf'])
                bt = bj.get('bizType')
                s = json.dumps(bj, ensure_ascii=False)
                P(f"--- msg={key[0][:18]} part={key[1]} bizType={bt} len={len(s)}")
                P(s[:2600])
                P()
            except Exception as ex:
                P(f"--- msg={key[0][:18]} part={key[1]} UNPARSED len={len(p['buf'])}: {p['buf'][:200]}")

with open(r"D:\JACK\plan\ai-assistant-analysis\uploads-and-biz.txt", 'w', encoding='utf-8') as f:
    f.write(out.getvalue())
print("done, check uploads-and-biz.txt")
