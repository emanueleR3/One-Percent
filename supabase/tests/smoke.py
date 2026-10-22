#!/usr/bin/env python3
"""Checks your live Supabase project end to end (standard library only).

    EMAIL=you@example.com PASSWORD='...' python3 supabase/tests/smoke.py

The project comes from Config/Local.xcconfig (ONEPERCENT_SUPABASE_HOST and _KEY).

Needs the migration applied and one confirmed user. It leaves two small tombstone rows of kind
"pref" behind (harmless; purge_tombstones() removes them after 180 days).
"""
import json, os, subprocess, sys, uuid, urllib.request, urllib.error, urllib.parse
from datetime import datetime, timedelta, timezone

here = os.path.dirname(os.path.abspath(__file__))
read_config = os.path.join(here, "..", "..", "Scripts", "read-config.py")
def setting(name):
    return subprocess.run([sys.executable, read_config, name], capture_output=True, text=True, check=True).stdout.strip()
HOST, KEY = setting("ONEPERCENT_SUPABASE_HOST"), setting("ONEPERCENT_SUPABASE_KEY")
if not HOST or not KEY:
    sys.exit("Set ONEPERCENT_SUPABASE_HOST and ONEPERCENT_SUPABASE_KEY in Config/Local.xcconfig first.")
URL = (HOST if "://" in HOST else "https://" + HOST).rstrip("/")
EMAIL, PASSWORD = os.environ.get("EMAIL"), os.environ.get("PASSWORD")

failures = 0

def call(method, path, body=None, token=None, headers=None):
    req = urllib.request.Request(URL + path, method=method)
    req.add_header("apikey", KEY)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(req, data=data, timeout=20) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw

def check(name, ok, detail=""):
    global failures
    print(("PASS  " if ok else "FAIL  ") + name + ("" if ok else f"   -> {detail}"))
    if not ok:
        failures += 1

def iso(minutes):
    return (datetime.now(timezone.utc) + timedelta(minutes=minutes)).isoformat()

# --- is the schema there at all? -----------------------------------------------------------------
status, body = call("GET", "/rest/v1/sync_records?select=id&limit=1")
if isinstance(body, dict) and body.get("code") == "PGRST205":
    sys.exit("The table public.sync_records does not exist yet: run supabase/migrations/*.sql in the SQL Editor first.")
check("anonymous visitors cannot read sync_records", status in (401, 403), f"{status} {body}")
status, body = call("POST", "/rest/v1/rpc/push_records", {"p_records": []})
check("anonymous visitors cannot call push_records", status in (401, 403), f"{status} {body}")

if not (EMAIL and PASSWORD):
    sys.exit("Set EMAIL and PASSWORD (a confirmed user of the project) to run the signed-in checks.")

# --- sign in ---------------------------------------------------------------------------------------
status, body = call("POST", "/auth/v1/token?grant_type=password", {"email": EMAIL, "password": PASSWORD})
if status != 200:
    sys.exit(f"Sign-in failed ({status}): {body}")
token = body["access_token"]
check("password sign-in works", True)

a, b = str(uuid.uuid4()), str(uuid.uuid4())
def push(records):
    return call("POST", "/rest/v1/rpc/push_records", {"p_records": records}, token)

status, out = push([
    {"id": a, "kind": "pref", "data": {"title": "smoke v1"}, "client_updated_at": iso(0), "device_id": "smoke"},
    {"id": b, "kind": "pref", "data": {"title": "other"}, "client_updated_at": iso(0), "device_id": "smoke"},
])
check("pushing two new items applies both", status == 200 and [r["r_applied"] for r in out] == [True, True], f"{status} {out}")

status, out = push([{"id": a, "kind": "pref", "data": {"title": "stale"}, "client_updated_at": iso(-60), "device_id": "smoke"}])
check("an older change is ignored", status == 200 and out[0]["r_applied"] is False, f"{status} {out}")

status, out = push([{"id": a, "kind": "pref", "data": {"title": "smoke v2"}, "client_updated_at": iso(5), "device_id": "smoke"}])
check("a newer change wins", status == 200 and out[0]["r_applied"] is True, f"{status} {out}")

status, rows = call("GET", f"/rest/v1/sync_records?id=in.({a},{b})&select=id,data,deleted,server_updated_at&order=server_updated_at.asc", token=token)
titles = {r["id"]: r["data"].get("title") for r in rows} if status == 200 else {}
check("pulling returns the latest data", titles.get(a) == "smoke v2" and titles.get(b) == "other", f"{status} {rows}")
check("every row carries a server timestamp", status == 200 and all(r["server_updated_at"] for r in rows), f"{rows}")

cursor = rows[0]["server_updated_at"] if status == 200 and rows else "1970-01-01T00:00:00Z"
status, newer = call("GET", "/rest/v1/sync_records?server_updated_at=gt." + urllib.parse.quote(cursor) + "&select=id&limit=500", token=token)
check("pulling with a cursor only returns what is newer", status == 200 and len(newer) >= 1, f"{status} {newer}")

status, out = call("DELETE", f"/rest/v1/sync_records?id=eq.{a}", token=token)
check("hard deletes are refused", status in (401, 403), f"{status} {out}")

status, out = push([
    {"id": a, "kind": "pref", "data": {}, "client_updated_at": iso(10), "deleted": True, "device_id": "smoke"},
    {"id": b, "kind": "pref", "data": {}, "client_updated_at": iso(10), "deleted": True, "device_id": "smoke"},
])
check("soft deleting (tombstones) works", status == 200 and all(r["r_applied"] for r in out), f"{status} {out}")

status, out = push([{"id": str(uuid.uuid4()), "kind": "nonsense", "client_updated_at": iso(0)}])
check("an unknown kind is rejected", status >= 400, f"{status} {out}")

print()
print("ALL LIVE CHECKS PASSED" if failures == 0 else f"{failures} CHECK(S) FAILED")
sys.exit(1 if failures else 0)
