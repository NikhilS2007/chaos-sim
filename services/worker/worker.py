import os
import time
import requests

API_URL = os.getenv("API_URL", "http://api:5000")

if __name__ == "__main__":
    print("[worker] startingâ€¦ API_URL=", API_URL, flush=True)
    while True:
        try:
            r = requests.get(f"{API_URL}/work", timeout=3)
            if r.ok:
                print("[worker] work ok:", r.json(), flush=True)
            else:
                print("[worker] work failed status:", r.status_code, flush=True)
        except Exception as e:
            print("[worker] error:", e, flush=True)
        time.sleep(2)
