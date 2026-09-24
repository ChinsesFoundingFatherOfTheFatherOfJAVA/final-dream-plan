import json

with open(r"E:\File\train.chinajack.com.har", 'r', encoding='utf-8') as f:
    har = json.load(f)

# 1. find WS entry and its frames
ws_found = 0
for e in har['log']['entries']:
    url = e.get('request', {}).get('url', '')
    if '/ws/chat' in url:
        ws_found += 1
        print("=== WS ENTRY:", url[:160])
        # HAR WS frames
        msgs = e.get('_webSocketMessages', [])
        print(f"frames: {len(msgs)}")
        for i, m in enumerate(msgs):
            op = m.get('type')  # 'send' | 'receive'
            data = m.get('data', '')
            try:
                j = json.loads(data)
                keys = list(j.keys())
                s = json.dumps(j, ensure_ascii=False)
                preview = s[:400]
            except Exception:
                preview = data[:400]
                keys = ['<raw>']
            print(f"--- [{i}] {op} keys={keys} len={len(data)}")
            print(preview)
            if i > 40:
                print("...(stop at 40)")
                break

if not ws_found:
    print("no ws entries with /ws/chat")

# 2. any other _webSocketMessages entries
cnt = sum(1 for e in har['log']['entries'] if e.get('_webSocketMessages'))
print(f"\nentries with _webSocketMessages: {cnt}")
