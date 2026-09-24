import json

with open(r"D:\JACK\plan\ai-assistant-analysis\har-extract.json", 'r', encoding='utf-8') as f:
    data = json.load(f)

def show(i, resp_len=3500, req_len=1500):
    x = data[i]
    print(f"===== [{i}] {x['t']} {x['m']} {x['status']} =====")
    print(f"URL: {x['u']}")
    if x.get('req'):
        print(f"--- REQ ---\n{x['req'][:req_len]}")
    print(f"--- RESP ---\n{x['resp'][:resp_len]}")
    print()

# 1. session creation (POST /session-v2)
show(0, 2500, 800)
# 2. session detail
show(2, 2000)
# 3. message history head (only structure)
show(4, 3000)
# 4. publish
show(65, 1500)
# 5. first script-progress
show(73, 800)
# 6. last script-progress
show(77, 800)
# 7. final info
show(79, 2500)
# 8. first info (after entering theme page)
show(53, 2500)
