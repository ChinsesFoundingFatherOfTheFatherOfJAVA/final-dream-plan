import json, re, sys

HAR = r"E:\File\train.chinajack.com.har"
OUT = r"D:\JACK\plan\ai-assistant-analysis\har-extract.json"

SKIP_URL = re.compile(r'\.(gif|png|jpg|jpeg|svg|css|woff2?|ttf|ico|mp3|mp4)(\?|$)|apm-pxy|errorreport|sobot|crumb|ingestion|/down/info/push|baidu\.com|bcebos\.com/orgsv2/.+\.(svg|png)|readthedocs|google|umeng|1949|cnzz', re.I)
KEEP_URL = re.compile(r'yunxuetang\.cn/(xuiappserver|artifact-server|sparring|aiassist|core)', re.I)

entries = []
with open(HAR, 'r', encoding='utf-8') as f:
    har = json.load(f)

log = har.get('log', {})
for e in log.get('entries', []):
    req = e.get('request', {})
    resp = e.get('response', {})
    url = req.get('url', '')
    if not KEEP_URL.search(url):
        continue
    if SKIP_URL.search(url):
        continue
    # response body
    body = ''
    rc = resp.get('content', {})
    if rc.get('size', 0) > 0 and rc.get('mimeType', '').startswith(('application/json', 'text/')):
        text = rc.get('text', '')
        if rc.get('encoding') == 'base64':
            try:
                import base64
                text = base64.b64decode(text).decode('utf-8', 'replace')
            except Exception:
                text = '<decode-failed>'
        body = text[:8000]
    # request body
    pd = req.get('postData', {})
    reqbody = ''
    if pd.get('text'):
        reqbody = pd['text'][:3000]
    entries.append({
        't': e.get('startedDateTime', '')[11:19],
        'm': req.get('method'),
        'u': url[:250],
        'status': resp.get('status'),
        'req': reqbody,
        'resp': body,
    })

# dedupe consecutive identical
out = []
for x in entries:
    if out and out[-1]['m'] == x['m'] and out[-1]['u'] == x['u'] and out[-1]['resp'][:200] == x['resp'][:200]:
        out[-1]['dup'] = out[-1].get('dup', 1) + 1
        continue
    out.append(x)

import os
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, 'w', encoding='utf-8') as f:
    json.dump(out, f, ensure_ascii=False, indent=1)

print(f'total kept: {len(out)} (from {len(log.get("entries", []))} entries)')
# print quick index
for i, x in enumerate(out):
    tag = f"+{x.get('dup')}" if x.get('dup') else ''
    print(f"[{i}] {x['t']} {x['m']} {x['status']} {x['u'][x['u'].find('cn/')+3:][:120]} {tag}")
