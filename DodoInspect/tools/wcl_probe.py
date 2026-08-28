#!/usr/bin/env python3
"""First contact with the Warcraft Logs v2 API -- ask it what it has.

    python tools/wcl_probe.py

Run this the moment the credentials file exists. It answers the three
questions that decide whether "top-100 stat trends" is a small job or an
impossible one, and it answers them by ASKING THE API, not from memory:

    A. What is the rate limit, in the API's own words?
    B. Do the ranking entries carry gear?
    C. Are per-player secondary stats reachable, and at what cost per report?

Nothing here is designed until those three come back. The whole point of
this script is to stop me guessing a schema I could not read: warcraftlogs.com
sits behind a Cloudflare human-check, so the docs pages are unreachable from
a script (measured 2026-08-27 -- see STAT_PRIORITY_WCL_RESEARCH_2026-08-27.md).

CREDENTIALS -- never pasted into a chat, never inside the repo:

    C:/Users/Doodo/.private/wcl-api.json
    { "client_id": "...", "client_secret": "..." }

Override with WCL_API_JSON=<path>. The secret is never printed; only its
length, so a truncated paste is visible without exposing the value.
"""

import base64
import io
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

TOKEN_URL = "https://www.warcraftlogs.com/oauth/token"
API_URL = "https://www.warcraftlogs.com/api/v2/client"
DEFAULT_CONF = "C:/Users/Doodo/.private/wcl-api.json"


def load_conf():
    path = os.environ.get("WCL_API_JSON", DEFAULT_CONF)
    if not os.path.exists(path):
        sys.exit(
            "No credentials at %s\n"
            "Create a client at https://www.warcraftlogs.com/api/clients/ and\n"
            "save it as: { \"client_id\": \"...\", \"client_secret\": \"...\" }"
            % path)
    try:
        # utf-8-sig: Notepad can save a BOM, and json.load would then fail
        # with "Expecting value: line 1 column 1", which reads like a typo in
        # the file rather than an encoding artefact.
        conf = json.load(io.open(path, encoding="utf-8-sig"))
    except ValueError as e:
        sys.exit("%s is not valid JSON: %s" % (path, e))
    for key in ("client_id", "client_secret"):
        if not conf.get(key):
            sys.exit("%s is missing %r" % (path, key))
    print("credentials: %s" % path)
    print("  client_id     %s" % conf["client_id"])
    print("  client_secret %d chars (not shown)" % len(conf["client_secret"]))
    return conf


def post(url, data, headers):
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:400]
        sys.exit("HTTP %s from %s\n%s" % (e.code, url, body))


def get_token(conf):
    """OAuth2 client_credentials. Basic auth first; some servers only accept
    the ids in the body, so fall back rather than reporting a wrong reason."""
    basic = base64.b64encode(
        ("%s:%s" % (conf["client_id"], conf["client_secret"])).encode()).decode()
    try:
        tok = post(TOKEN_URL, b"grant_type=client_credentials", {
            "Authorization": "Basic " + basic,
            "Content-Type": "application/x-www-form-urlencoded"})
    except SystemExit:
        print("  (Basic auth rejected; retrying with ids in the body)")
        body = urllib.parse.urlencode({
            "grant_type": "client_credentials",
            "client_id": conf["client_id"],
            "client_secret": conf["client_secret"]}).encode()
        tok = post(TOKEN_URL, body,
                   {"Content-Type": "application/x-www-form-urlencoded"})
    if "access_token" not in tok:
        sys.exit("token response has no access_token: %r" % list(tok))
    print("token: ok, %d chars, expires_in=%s"
          % (len(tok["access_token"]), tok.get("expires_in")))
    return tok["access_token"]


def gql(token, query, variables=None):
    payload = json.dumps({"query": query, "variables": variables or {}}).encode()
    out = post(API_URL, payload, {
        "Authorization": "Bearer " + token,
        "Content-Type": "application/json"})
    if out.get("errors"):
        print("  ! GraphQL errors: %s"
              % json.dumps(out["errors"], ensure_ascii=False)[:400])
    return out.get("data") or {}


INTROSPECT = """
query { __schema { types {
  name kind
  fields { name type { name kind ofType { name kind ofType { name kind } } } }
} } }
"""


def unwrap(t):
    while t and not t.get("name") and t.get("ofType"):
        t = t["ofType"]
    return (t or {}).get("name") or (t or {}).get("kind") or "?"


def report_schema(token):
    print()
    print("=" * 78)
    print("SCHEMA -- what the API says it has")
    print("=" * 78)
    data = gql(token, INTROSPECT)
    types = {t["name"]: t for t in (data.get("__schema") or {}).get("types", [])
             if t.get("name")}
    if not types:
        print("  introspection returned nothing -- it may be disabled.")
        return types
    print("  %d types" % len(types))

    # A. rate limit -- find it rather than assuming its name
    hits = [(n, f["name"], unwrap(f.get("type")))
            for n, t in types.items() for f in (t.get("fields") or [])
            if "ratelimit" in f["name"].lower() or "ratelimit" in n.lower()]
    print("\n  A. rate limit fields: %s" % (hits or "NONE FOUND"))

    # B/C. where do gear and stats live
    wanted = ("gear", "combatantinfo", "playerdetails", "stats", "talents",
              "characterrankings", "rankings", "table", "events")
    print("\n  B/C. fields whose name matches what we need:")
    for n in sorted(types):
        for f in types[n].get("fields") or []:
            if f["name"].lower() in wanted:
                print("     %-22s . %-20s -> %s"
                      % (n, f["name"], unwrap(f.get("type"))))
    return types


def report_shape(token):
    """A JSON-typed field tells you nothing; only a real call shows the keys."""
    print()
    print("=" * 78)
    print("SHAPE -- one real call, because JSON-typed fields hide everything")
    print("=" * 78)
    zones = gql(token, "query { worldData { zones { id name expansion { name } } } }")
    zs = ((zones.get("worldData") or {}).get("zones") or [])[-6:]
    for z in zs:
        print("  zone %-6s %-42s (%s)"
              % (z.get("id"), z.get("name"), (z.get("expansion") or {}).get("name")))
    if not zs:
        print("  no zones returned; stop here and read the errors above.")
        return
    zid = zs[-1]["id"]
    enc = gql(token, """
        query ($z: Int!) { worldData { zone(id: $z) {
          name encounters { id name } } } }""", {"z": zid})
    encs = (((enc.get("worldData") or {}).get("zone") or {}).get("encounters") or [])
    print("\n  newest zone %s has %d encounters" % (zid, len(encs)))
    if not encs:
        return
    eid = encs[0]["id"]
    r = gql(token, """
        query ($e: Int!) { worldData { encounter(id: $e) {
          name characterRankings(metric: dps, page: 1) } } }""", {"e": eid})
    cr = (((r.get("worldData") or {}).get("encounter") or {})
          .get("characterRankings"))
    if not isinstance(cr, dict):
        print("  characterRankings did not come back as an object: %r" % type(cr))
        return
    print("\n  characterRankings top-level keys: %s" % sorted(cr))
    rk = (cr.get("rankings") or [])
    print("  entries on page 1: %d" % len(rk))
    if rk:
        e0 = rk[0]
        print("  ENTRY KEYS: %s" % sorted(e0))
        for k in ("gear", "talents", "stats", "combatantInfo"):
            if k in e0:
                print("    %-14s %s" % (k, json.dumps(e0[k], ensure_ascii=False)[:300]))
        print("\n  >>> gear present:  %s" % ("gear" in e0))
        print("  >>> stats present: %s" % ("stats" in e0))


def main():
    conf = load_conf()
    token = get_token(conf)
    report_schema(token)
    report_shape(token)
    print()
    print("Done. Nothing was designed from memory -- everything above is the "
          "API's own answer. Decide scope from the rate limit and from whether "
          "gear/stats ride along with the rankings.")


if __name__ == "__main__":
    sys.exit(main())
