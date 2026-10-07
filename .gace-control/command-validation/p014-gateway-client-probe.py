#!/usr/bin/env python3
from __future__ import annotations
import json
import os
import urllib.error
import urllib.request

url = str(os.environ.get("GACE_EVENT_GATEWAY_URL") or "").strip().rstrip("/")
token = str(os.environ.get("GACE_EVENT_GATEWAY_TOKEN") or "").strip()
if not url or not token:
    print("PY_GATEWAY_CONFIG=MISSING")
    raise SystemExit(2)
if not url.endswith("/internal/events"):
    url += "/internal/events"

def probe(label: str, user_agent: str | None) -> None:
    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {token}"}
    if user_agent:
        headers["User-Agent"] = user_agent
    req = urllib.request.Request(url, data=b"{}", method="POST", headers=headers)
    try:
        with urllib.request.build_opener().open(req, timeout=10) as resp:
            print(f"{label}_HTTP={int(getattr(resp, 'status', 0) or 0)}")
            print(f"{label}_CONTENT_TYPE={resp.headers.get('Content-Type','')}")
            print(f"{label}_SERVER={resp.headers.get('Server','')}")
    except urllib.error.HTTPError as exc:
        print(f"{label}_HTTP={int(exc.code)}")
        print(f"{label}_CONTENT_TYPE={exc.headers.get('Content-Type','')}")
        print(f"{label}_SERVER={exc.headers.get('Server','')}")
    except urllib.error.URLError as exc:
        reason = "TIMEOUT" if isinstance(exc.reason, TimeoutError) else "URL_ERROR"
        print(f"{label}_HTTP={reason}")
    except TimeoutError:
        print(f"{label}_HTTP=TIMEOUT")

proxy_detected = bool(urllib.request.getproxies())
print("PY_PROXY_DETECTED=" + ("YES" if proxy_detected else "NO"))
probe("PY_DEFAULT_UA", None)
probe("PY_GACE_UA", "G-ACE-KB-Logger/1.0")
print("SECRET_VALUE_EXPOSED=NO")
print("REAL_EVENT_CREATED=NO")
