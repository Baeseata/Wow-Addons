#!/usr/bin/env python3
"""Tally the secondary stats top-ranked players actually WEAR, and diff that
against Data/StatPriority.lua as COUNTER-EVIDENCE ONLY.

    python tools/scan_wcl_stats.py --plan          # cost only, spends nothing
    python tools/scan_wcl_stats.py                 # fetch + report
    python tools/scan_wcl_stats.py --cached        # replay the last fetch
    python tools/scan_wcl_stats.py --only 581      # one spec
    python tools/scan_wcl_stats.py --verify        # negative controls, then exit

Credentials: C:/Users/Doodo/.private/wcl-api.json, override with WCL_API_JSON.
The secret is never printed; only its length.

WHAT THIS IS ALLOWED TO CONCLUDE (assertion 7 below, and the reason the
verdict column has no "confirms" value): the observed distribution is a
CONFOUND of guide-following, loot RNG and item-level dominance. It can say
"we ship mastery-first and the top parses are mastery-last, go look again".
It can never say "they stack X, therefore X is better".

NINE ASSERTIONS THAT MUST NOT BE REMOVED (each is a measured trap, and each
one's failure direction is SILENT):

  1. className/specName want the SLUG, not the display name. Measured
     2026-08-27 on raid encounter 3470, same second:
         className="DeathKnight"  specName="Blood"        -> 100 rankings
         className="Death Knight" specName="Blood"        ->   0 rankings
         className="Hunter" specName="BeastMastery"       -> 100 rankings
         className="Hunter" specName="Beast Mastery"      ->   0 rankings
     A wrong name is NOT an error. It is an empty page, which reads exactly
     like "this spec has no parses". roster() derives slugs from DB2 and
     verify_roster() checks every one against gameData before any scan.

  2. Every numeric field inside gear[] comes back as a STRING: itemLevel
     "321", bonusIDs ["41","13696"], permanentEnchant "8017", gems
     [{"id":"213455","itemLevel":"granite"}]. int() everything at the door;
     a scanner that trusts JSON types sorts by string and never notices.

  3. gear[] is a FIXED 18-element array in Blizzard INVSLOT order. An empty
     slot is a full placeholder object {"id":0,"name":"Unknown Item",...},
     not null and not omitted. Filter on id == 0, never on array length.

  4. bonusIDs CHANGE WHICH SECONDARY STATS AN ITEM HAS -- not only its item
     level. Measured 2026-08-27: 41 of 475 distinct sampled item ids carry
     the wildcard sentinels StatModifier_bonusStat = 24 and 25 in their
     ItemSparse row (a 50/50 3500+3500 split with no stat identity), and the
     identity arrives on the equipped instance via an ItemBonus Type=25 row.
     Six bonusIDs cover all six 2-of-4 combinations: 8790 crit+haste,
     8791 crit+mastery, 8792 haste+versatility, 8793 haste+mastery,
     8794 mastery+versatility, 8795 crit+versatility. In that same sample
     ONE item id (239648) was observed resolved five different ways on five
     different characters. Reading only the base row silently reports these
     as "no secondary stats" -- 118 real gear entries in a 1285-entry
     sample. --verify re-proves this every run; see verify_wildcards().

  5. StatPercentEditor values are BUDGET POINTS, not percentages, and the
     per-slot budget differs (armor ~7000, rings and necks ~17500).
     Normalise each item against ITS OWN pair total, never a constant.
     Same rule Data/Loot.lua's header states for the same reason.

  6. Healer rankings must be pulled with metric:hps. Measured on encounter
     3470, Restoration Druid: metric:dps also returns count=100, so nothing
     looks wrong -- but it is ranked by their incidental DAMAGE (top amounts
     ~10k) instead of their healing (~306k). The population is a different
     hundred people. Tanks use metric:dps: metric:tankhps answered
     {"error": "Tank HPS ranks not supported for this zone."}

  7. STAT_PRIORITY_WCL_RESEARCH_2026-08-27.md section 5 is a hard limit on
     OUTPUT, not a footnote: this script prints observations and
     disagreements, and every distribution it prints carries its n. It must
     never print a recommended order. There is deliberately no verdict value
     meaning "the top parses agree with us, so we are right".

  8. Zone ids are PINNED and cross-checked against live discovery, the same
     way gen_loot.py pins MPLUS_DISPLAY_SEASON. worldData.expansions does
     not come back newest-first, and the Midnight list carries (PTR), Beta,
     Dummy Dome and a "Complete Raid" aggregate zone alongside the real one.
     A season roll must fail loudly here, never silently rescan last tier.

  9. "Their leader differs from ours" is NOT by itself a disagreement, and
     the first full scan is the measurement that says so. 2026-08-27, all
     40 specs x 2 zones = 80 rows, 674 calls: the naive rule flagged 25 --
     but 20 of those led by under 5 percentage points, 11 by under 3, one
     by 0.2; and in 13 of the 25 the gems-and-enchants column agreed with
     what we ship. Worn gear is SUPPLY-limited (the loot table decides what
     exists to be worn); gems and enchants are not. So a FLAG now needs BOTH
     a margin over MIN_MARGIN AND the chosen column to disagree as well.
     "gear disagrees but their gems agree with us" gets its own verdict
     (loot?) because it is a different fact about the world, not a weaker
     version of the same one.
"""

import argparse
import base64
import csv
import io
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)
LOOT = os.path.join(ADDON, "Data", "Loot.lua")
CACHE = os.path.join(HERE, ".scan-cache")

# Assertion 2 of scan_statpriority.py: this exact UA. Do not lengthen it.
UA = {"User-Agent": "Mozilla/5.0"}
DB2 = "https://wago.tools/db2/%s/csv"

TOKEN_URL = "https://www.warcraftlogs.com/oauth/token"
API_URL = "https://www.warcraftlogs.com/api/v2/client"
DEFAULT_CONF = "C:/Users/Doodo/.private/wcl-api.json"

# Assertion 8. name is carried so a roll reports what it found, not just that
# it differs. "Complete Raid" is the all-bosses aggregate zone, not the roster.
EXPECTED_ZONES = {
    "raid": (53, "The Venomous Abyss", 9),
    "mplus": (55, "Mythic+ Season 2", 8),
}
ZONE_NAME_EXCLUDE = ("PTR", "Beta", "Dummy", "Complete Raid")

# Assertion 6.
ROLE_METRIC = {"dps": "dps", "healer": "hps", "tank": "dps"}
# ChrSpecialization.Role, same map scan_statpriority.py uses.
ROLE_SUFFIX = {"0": "tank", "1": "healer", "2": "dps"}

# Same numeric stat-id space as gen_loot.py, and -- measured 2026-08-27 --
# the same space SpellItemEnchantment.EffectArg_N uses for gems and enchants.
SECONDARY = {32: "crit", 36: "haste", 40: "versatility", 49: "mastery"}
PRIMARY = {3: "AGI", 4: "STR", 5: "INT",
           71: "SAI", 72: "SA", 73: "AI", 74: "SI"}
STAT_ORDER = ("crit", "haste", "mastery", "versatility")

# Assertion 4. Sentinel stat ids that mean "identity arrives via bonusIDs".
WILDCARD = (24, 25)
STAMINA = 7
# Tertiary family seen on bonusIDs 40-43; known, not a secondary, not a
# mystery. Listed so it does not inflate the "unknown stat id" counter.
TERTIARY = (61, 62, 63, 64)

# ItemSparse.InventoryType for slots that carry no stats by design.
NO_STAT_SLOTS = (4, 19)          # 4 shirt, 19 tabard

ITEM_ENCHANTMENT_TYPE_STAT = 5   # SpellItemEnchantment.Effect_N

POINTS_PER_CALL = 2.02           # measured twice, fresh (non-cached) queries


# ----------------------------------------------------------------- plumbing

def die(msg):
    sys.exit("FATAL: " + msg)


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read().decode("utf-8", "replace")


def cache_path(name):
    return os.path.join(CACHE, name)


def cache_write(name, text):
    """tmp-then-replace: open(path,"w") destroys the old copy before it knows
    whether the new one can even be encoded."""
    if not os.path.isdir(CACHE):
        os.makedirs(CACHE)
    tmp = cache_path(name) + ".tmp"
    with io.open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, cache_path(name))


def cached(name, url):
    path = cache_path(name)
    if os.path.exists(path):
        return io.open(path, encoding="utf-8").read()
    body = get(url)
    cache_write(name, body)
    return body


def db2(table):
    return list(csv.DictReader(io.StringIO(cached(table + ".csv", DB2 % table))))


def load_conf():
    path = os.environ.get("WCL_API_JSON", DEFAULT_CONF)
    if not os.path.exists(path):
        die("no credentials at %s -- create a client at "
            "https://www.warcraftlogs.com/api/clients/ and save it as "
            '{ "client_id": "...", "client_secret": "..." }' % path)
    try:
        # utf-8-sig: Notepad writes a BOM and json.load then fails with
        # "Expecting value: line 1 column 1", which reads like a typo.
        conf = json.load(io.open(path, encoding="utf-8-sig"))
    except ValueError as e:
        die("%s is not valid JSON: %s" % (path, e))
    for key in ("client_id", "client_secret"):
        if not conf.get(key):
            die("%s is missing %r" % (path, key))
    print("credentials: %s" % path)
    print("  client_id     %s" % conf["client_id"])
    print("  client_secret %d chars (not shown)" % len(conf["client_secret"]))
    return conf


def post(url, data, headers):
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:400]
        die("HTTP %s from %s%s%s" % (e.code, url, chr(10), body))


def get_token(conf):
    """Basic auth first, ids-in-body as a fallback, so a rejection reports the
    real reason instead of the first thing that failed. Same shape as
    tools/wcl_probe.py, which is the script that measured it working."""
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
        die("token response has no access_token: %r" % list(tok))
    print("token: ok, expires_in=%s" % tok.get("expires_in"))
    return tok["access_token"]


class Api(object):
    """Counts its own calls so the report can state what it spent rather than
    repeat the estimate it started with."""

    def __init__(self, token):
        self.token = token
        self.calls = 0
        self.soft_errors = []

    def gql(self, query, variables=None, soft=False):
        """soft=True is for the 680 per-spec ranking calls: one metric a zone
        does not support (measured: tankhps answers "Tank HPS ranks not
        supported for this zone") must cost that one row, not the sweep. It
        still surfaces -- see self.soft_errors, which the report prints."""
        payload = json.dumps({"query": query,
                              "variables": variables or {}}).encode()
        out = post(API_URL, payload, {
            "Authorization": "Bearer " + self.token,
            "Content-Type": "application/json"})
        self.calls += 1
        if out.get("errors"):
            msg = json.dumps(out["errors"], ensure_ascii=False)[:300]
            if not soft:
                die("GraphQL errors: " + msg)
            self.soft_errors.append(msg)
            return None
        return out.get("data") or {}

    def rate_limit(self):
        """Reading this costs 1.000 point itself -- measured 2026-08-27 by
        reading it three times in a row (14.020 -> 15.020 -> 16.020). Callers
        that subtract a delta must subtract that 1.000 too."""
        d = self.gql("query { rateLimitData { limitPerHour "
                     "pointsSpentThisHour pointsResetIn } }")
        return d.get("rateLimitData") or {}


# ------------------------------------------------------- roster (assertion 1)

def loot_spec_ids():
    """The shipped roster is the source of truth, same as scan_statpriority.py."""
    body = io.open(LOOT, encoding="utf-8").read()
    block = re.search(r"ns\.SpecGear\s*=\s*\{(.*?)\n\}", body, re.S)
    if not block:
        die("ns.SpecGear not found in " + LOOT)
    ids = [int(n) for n in re.findall(r"\[(\d+)\]\s*=\s*\{", block.group(1))]
    if len(ids) != 40:
        die("expected 40 specs in ns.SpecGear, found %d" % len(ids))
    return ids


def deslug(name):
    """WCL's className/specName slug is the display name with every
    non-alphanumeric character removed: "Death Knight" -> DeathKnight,
    "Beast Mastery" -> BeastMastery. Derived, never typed here."""
    return re.sub(r"[^A-Za-z0-9]+", "", name)


def roster():
    """specID -> WCL slugs + role, joined from DB2. Nothing hand-typed."""
    specs = {int(r["ID"]): r for r in db2("ChrSpecialization")}
    classes = {r["ID"]: r for r in db2("ChrClasses")}
    out = []
    for sid in loot_spec_ids():
        r = specs.get(sid)
        if r is None:
            die("specID %d is in ns.SpecGear but not in DB2" % sid)
        cls = classes[r["ClassID"]]
        role = ROLE_SUFFIX.get(r["Role"])
        if role is None:
            die("specID %d has unmapped ChrSpecialization.Role %r"
                % (sid, r["Role"]))
        out.append({"id": sid, "spec": r["Name_lang"], "cls": cls["Name_lang"],
                    "class_slug": deslug(cls["Name_lang"]),
                    "spec_slug": deslug(r["Name_lang"]),
                    "role": role, "metric": ROLE_METRIC[role]})
    return out


def verify_roster(api, specs):
    """ASSERTION 1, enforced before a single ranking is pulled.

    A wrong slug returns an empty page, not an error, so the whole scan would
    come back "these specs have no parses" and read like a finding. One
    gameData call settles all 40 against the API's own spelling."""
    d = api.gql("query { gameData { classes { name slug "
                "specs { name slug } } } }")
    live = {}
    for c in ((d.get("gameData") or {}).get("classes") or []):
        for s in (c.get("specs") or []):
            live.setdefault(c.get("slug") or deslug(c.get("name") or ""),
                            set()).add(s.get("slug") or deslug(s.get("name") or ""))
    if not live:
        die("gameData returned no classes; cannot verify slugs, refusing to "
            "scan blind (an unverified slug fails silently -- assertion 1)")
    bad = [s for s in specs
           if s["spec_slug"] not in live.get(s["class_slug"], set())]
    if bad:
        lines = ["%d %s/%s -> class_slug=%r spec_slug=%r"
                 % (s["id"], s["cls"], s["spec"], s["class_slug"],
                    s["spec_slug"]) for s in bad]
        die("%d of %d derived slugs do not exist in WCL's gameData. These "
            "would have returned zero rankings and looked like specs with no "
            "parses:%s%s" % (len(bad), len(specs), chr(10),
                             chr(10).join("  " + x for x in lines)))
    print("roster: %d specs, all slugs verified against gameData" % len(specs))
    return live


# -------------------------------------------------------- zones (assertion 8)

def zones(api):
    """Discover, then check against the pin. Discovery alone would follow a
    season roll silently; the pin alone would go stale silently."""
    d = api.gql("query { worldData { expansions { name zones { id name frozen "
                "encounters { id name } } } } }")
    found = []
    for exp in ((d.get("worldData") or {}).get("expansions") or []):
        for z in (exp.get("zones") or []):
            if z.get("frozen"):
                continue
            name = z.get("name") or ""
            if any(bad in name for bad in ZONE_NAME_EXCLUDE):
                continue
            if any(bad in (exp.get("name") or "") for bad in ZONE_NAME_EXCLUDE):
                continue
            found.append({"id": int(z["id"]), "name": name,
                          "expansion": exp.get("name"),
                          "encounters": [{"id": int(e["id"]), "name": e["name"]}
                                         for e in (z.get("encounters") or [])]})
    by_id = {z["id"]: z for z in found}
    out = {}
    for key, (zid, zname, n_enc) in sorted(EXPECTED_ZONES.items()):
        z = by_id.get(zid)
        if z is None:
            die("pinned %s zone %d (%s) is not among the live non-frozen "
                "zones. A season may have rolled. Live candidates:%s%s"
                % (key, zid, zname, chr(10),
                   chr(10).join("  %-6d %-45s (%s)"
                                % (f["id"], f["name"], f["expansion"])
                                for f in found)))
        if z["name"] != zname or len(z["encounters"]) != n_enc:
            die("pinned %s zone %d changed: expected %r with %d encounters, "
                "live says %r with %d. Update EXPECTED_ZONES in the same edit "
                "that re-reads the data." % (key, zid, zname, n_enc,
                                             z["name"], len(z["encounters"])))
        out[key] = z
        print("zone %-6s %-6d %-32s %d encounters"
              % (key, zid, zname, len(z["encounters"])))
    return out


# ------------------------------------------------------- rankings (2, 3, 6)

RANK_Q = """
query ($e: Int!, $m: CharacterRankingMetricType!, $c: String!, $s: String!) {
  worldData { encounter(id: $e) {
    characterRankings(metric: $m, page: 1, includeCombatantInfo: true,
                      className: $c, specName: $s) } } }
"""


def rankings(api, enc_id, spec, use_cache):
    name = "wcl-rank-%d-%d.json" % (enc_id, spec["id"])
    path = cache_path(name)
    if os.path.exists(path):
        return json.load(io.open(path, encoding="utf-8"))
    if use_cache:
        return None
    d = api.gql(RANK_Q, {"e": enc_id, "m": spec["metric"],
                         "c": spec["class_slug"], "s": spec["spec_slug"]},
                soft=True)
    if d is None:
        return None
    cr = (((d.get("worldData") or {}).get("encounter") or {})
          .get("characterRankings"))
    if not isinstance(cr, dict):
        api.soft_errors.append(
            "encounter %d spec %d: characterRankings was %s, not an object"
            % (enc_id, spec["id"], type(cr).__name__))
        return None
    cache_write(name, json.dumps(cr, ensure_ascii=False))
    return cr


def gear_of(entry):
    """ASSERTION 3: fixed 18-element array, empty slots are id==0 placeholders.
    ASSERTION 2: every number in here is a string."""
    out = []
    for g in (entry.get("gear") or []):
        try:
            iid = int(g.get("id") or 0)
        except (TypeError, ValueError):
            continue
        if iid == 0:
            continue
        bonus = []
        for b in (g.get("bonusIDs") or []):
            try:
                bonus.append(int(b))
            except (TypeError, ValueError):
                pass
        gems = []
        for gem in (g.get("gems") or []):
            try:
                gems.append(int(gem.get("id")))
            except (TypeError, ValueError, AttributeError):
                pass
        ench = g.get("permanentEnchant")
        try:
            ench = int(ench) if ench not in (None, "") else None
        except (TypeError, ValueError):
            ench = None
        out.append({"id": iid, "bonus": bonus, "gems": gems, "enchant": ench})
    return out


# --------------------------------------------------- item -> secondary stats

ITEM_KEEP = (["StatModifier_bonusStat_%d" % i for i in range(10)]
             + ["StatPercentEditor_%d" % i for i in range(10)]
             + ["Gem_properties", "InventoryType", "ItemLevel"])


def item_rows(item_ids):
    """Stream ItemSparse once (about 50 MB) and keep only the rows we need,
    cached as a small subset so a rerun does not re-download 50 MB."""
    name = "wcl-itemsparse-subset.json"
    path = cache_path(name)
    have = json.load(io.open(path, encoding="utf-8")) if os.path.exists(path) else {}
    wanted = set(str(i) for i in item_ids)
    missing = wanted - set(have)
    if not missing:
        return have
    print("  ItemSparse: %d of %d item ids not cached, streaming the table"
          % (len(missing), len(wanted)))
    req = urllib.request.Request(DB2 % "ItemSparse", headers=UA)
    stream = io.TextIOWrapper(urllib.request.urlopen(req, timeout=900),
                              encoding="utf-8")
    reader = csv.DictReader(stream)
    seen = 0
    for row in reader:
        if row["ID"] not in missing:
            continue
        keep = {k: row.get(k, "") for k in ITEM_KEEP}
        keep["name"] = row.get("Display_lang") or row.get("Name_lang") or ""
        have[row["ID"]] = keep
        seen += 1
        if seen == len(missing):
            break
    cache_write(name, json.dumps(have, ensure_ascii=False))
    still = wanted - set(have)
    if still:
        print("  ItemSparse: %d ids have NO row at all (they are counted as "
              "unresolved, not as zero-secondary): %s"
              % (len(still), sorted(still)[:8]))
    return have


def wildcard_map():
    """ASSERTION 4. bonusID -> [(OrderIndex, stat), ...] from ItemBonus
    Type == 25. 29 such rows exist in the whole table; six bonusIDs
    (8790-8795) cover all six 2-of-4 secondary combinations."""
    out = {}
    for r in db2("ItemBonus"):
        if (r.get("Type") or "") != "25":
            continue
        try:
            stat = int(r.get("Value_0") or -1)
            parent = int(r.get("ParentItemBonusListID") or -1)
            order = int(r.get("OrderIndex") or 0)
        except (TypeError, ValueError):
            continue
        if stat in SECONDARY:
            out.setdefault(parent, []).append((order, SECONDARY[stat]))
    for k in out:
        out[k].sort()
    if not out:
        die("ItemBonus has no Type=25 rows carrying a secondary stat id. "
            "Either the table shape changed or wago.tools served a different "
            "build -- either way wildcard items would silently tally as "
            '"no secondary stats" (assertion 4). Refusing to continue.')
    return out


class Diag(object):
    """Nothing is dropped silently. Every skip lands in one of these buckets
    and every bucket is printed, so a resolver regression shows up as a number
    moving rather than as a distribution that merely looks a bit different."""

    def __init__(self):
        self.no_row = 0            # item id not in ItemSparse at all
        self.no_stat_slot = 0      # shirt / tabard, correct to skip
        self.no_secondary = 0      # real item, genuinely no secondary budget
        self.wild_seen = 0         # items carrying a wildcard sentinel
        self.wild_resolved = 0     # ... of which resolved via bonusIDs
        self.wild_partial = 0      # ... resolved for fewer slots than it has
        self.resolved = 0
        self.unknown_stats = {}    # stat id -> count, never silently skipped

    def merge(self, other):
        for k, v in vars(other).items():
            if k == "unknown_stats":
                for s, c in v.items():
                    self.unknown_stats[s] = self.unknown_stats.get(s, 0) + c
            else:
                setattr(self, k, getattr(self, k) + v)


def resolve_item(item, rows, wild_map, diag):
    """-> [(stat, points)] for this equipped INSTANCE, or None if unresolved.

    ASSERTION 4: the identity of a wildcard slot lives on the instance's
    bonusIDs, not on the item id. ASSERTION 5: points are budget points."""
    row = rows.get(str(item["id"]))
    if row is None:
        diag.no_row += 1
        return None
    try:
        inv = int(row.get("InventoryType") or 0)
    except (TypeError, ValueError):
        inv = 0
    if inv in NO_STAT_SLOTS:
        diag.no_stat_slot += 1
        return None
    secondary, wild = [], []
    for i in range(10):
        try:
            stat = int(row.get("StatModifier_bonusStat_%d" % i) or -1)
            amount = int(row.get("StatPercentEditor_%d" % i) or 0)
        except (TypeError, ValueError):
            continue
        if amount in (0, -1):
            continue
        if stat in SECONDARY:
            secondary.append((SECONDARY[stat], amount))
        elif stat in WILDCARD:
            wild.append((stat, amount))
        elif stat in PRIMARY or stat == STAMINA or stat in TERTIARY:
            pass
        elif stat >= 0:
            diag.unknown_stats[stat] = diag.unknown_stats.get(stat, 0) + 1
    if wild:
        diag.wild_seen += 1
        picks = []
        for b in item["bonus"]:
            if b in wild_map:
                picks = wild_map[b]
                break
        if picks:
            # Sentinel 24 is the first wildcard slot, 25 the second; the
            # bonus rows carry the same ordering in OrderIndex.
            wild.sort(key=lambda w: w[0])
            for (order, stat), (sentinel, amount) in zip(picks, wild):
                secondary.append((stat, amount))
            if len(picks) < len(wild):
                diag.wild_partial += 1
            else:
                diag.wild_resolved += 1
        elif not secondary:
            return None
    if not secondary:
        diag.no_secondary += 1
        return None
    diag.resolved += 1
    secondary.sort(key=lambda s: -s[1])
    return secondary


# ------------------------------------------- gems and enchants: CHOSEN stats

def enchant_index():
    """SpellItemEnchantment id -> [stat names]. Effect_N == 5 is
    ITEM_ENCHANTMENT_TYPE_STAT and EffectArg_N is then a stat id in the same
    numeric space ItemSparse uses -- measured 2026-08-27, cross-checked
    against each row's own Name_lang."""
    out = {}
    for r in db2("SpellItemEnchantment"):
        stats = []
        for i in range(3):
            try:
                eff = int(r.get("Effect_%d" % i) or -1)
                arg = int(r.get("EffectArg_%d" % i) or -1)
            except (TypeError, ValueError):
                continue
            if eff == ITEM_ENCHANTMENT_TYPE_STAT and arg in SECONDARY:
                stats.append(SECONDARY[arg])
        if stats:
            out[int(r["ID"])] = stats
    return out


def gem_index(rows, ench):
    """gem item id -> [stat names], via
    ItemSparse.Gem_properties -> GemProperties.Enchant_ID -> the enchant."""
    props = {}
    for r in db2("GemProperties"):
        try:
            props[int(r["ID"])] = int(r.get("Enchant_ID") or -1)
        except (TypeError, ValueError):
            continue
    out = {}
    for iid, row in rows.items():
        try:
            gp = int(row.get("Gem_properties") or 0)
        except (TypeError, ValueError):
            continue
        if gp and gp in props:
            stats = ench.get(props[gp])
            if stats:
                out[int(iid)] = stats
    return out


# ------------------------------------------------------------------- tally

# Below this many parsed players a distribution is not counter-evidence, it is
# noise. Measured 2026-08-27 on one boss: paladin 100+, holy priest 100+,
# enhancement shaman 58, frost mage 13. A 13-player distribution must not be
# printed with the same authority as a 100-player one, so it is never flagged.
MIN_N = 20

# Assertion 9. Percentage points. Below this the two orders are the same
# order with loot noise on top: 11 of the naive rule's 25 flags sat here,
# the smallest of them 0.2 points (spec 252, raid).
MIN_MARGIN = 3.0


def tally(entries, rows, wild_map, gems, ench):
    """Per player: each RESOLVED item contributes 1.0, split between its own
    secondaries by their share of ITS OWN budget (assertion 5). Player
    distributions are then averaged, so a player with more resolvable items
    does not weigh more than one with fewer.

    Gems and enchants are tallied SEPARATELY and never summed into the gear
    number: gear allocation is a ratio, a gem is a flat amount, and the two are
    not the same kind of quantity. They are also not the same kind of evidence
    -- gear is partly loot RNG, a gem is a choice."""
    diag = Diag()
    per_player, chosen, sockets = [], dict((s, 0.0) for s in STAT_ORDER), 0
    for e in entries:
        acc, items = dict((s, 0.0) for s in STAT_ORDER), 0
        for g in gear_of(e):
            sec = resolve_item(g, rows, wild_map, diag)
            if sec:
                total = float(sum(v for _n, v in sec))
                if total > 0:
                    for name, v in sec:
                        acc[name] += v / total
                    items += 1
            for gid in g["gems"]:
                st = gems.get(gid)
                if st:
                    sockets += 1
                    for s in st:
                        chosen[s] += 1.0 / len(st)
            if g["enchant"]:
                st = ench.get(g["enchant"])
                if st:
                    sockets += 1
                    for s in st:
                        chosen[s] += 1.0 / len(st)
        if items:
            per_player.append(dict((s, acc[s] / items) for s in STAT_ORDER))
    if not per_player:
        return None, chosen, sockets, 0, diag
    dist = dict((s, sum(p[s] for p in per_player) / len(per_player))
                for s in STAT_ORDER)
    return dist, chosen, sockets, len(per_player), diag


def order_of(dist):
    return sorted(STAT_ORDER, key=lambda s: -dist[s])


def parse_shipped(text):
    """"haste > crit=versatility=mastery" -> [["haste"], ["crit", ...]]"""
    return [g.split("=") for g in text.split(" > ")]


def verdict(dist, chosen, candidates):
    """ASSERTION 7 + 9. The outcomes are: no disagreement found, a
    disagreement too thin to mean anything, a disagreement that the loot
    supply already explains, and a real one. There is deliberately no value
    meaning "confirmed": an agreeing distribution is what a shared guide
    produces, not evidence.

    candidates is every order we ship for this spec and bucket (one per hero
    tree). A spec only disagrees when NOTHING we ship can account for it."""
    if not candidates:
        return "no-data", ""
    obs = order_of(dist)
    top = obs[0]
    firsts = set(s for groups in candidates for s in groups[0])

    if top in firsts:
        # Weaker probe, and the one section 5 actually names: something we
        # put first sits LAST out there. Only meaningful past the margin.
        if obs[-1] in firsts:
            gap = 100.0 * (dist[top] - dist[obs[-1]])
            if gap >= MIN_MARGIN:
                return "FLAG", ("we tie %s into first place and it is observed "
                                "last, %.1f pts behind %s"
                                % (obs[-1], gap, top))
        return "ok", ""

    best = max(firsts, key=lambda k: dist[k])
    margin = 100.0 * (dist[top] - dist[best])
    if margin < MIN_MARGIN:
        return "thin", ("%s leads %s by only %.1f pts"
                        % (top, best, margin))

    total = sum(chosen.values())
    if total <= 0:
        return "FLAG?", ("worn %s +%.1f pts over %s, and there is no gem or "
                         "enchant data to corroborate it"
                         % (top, margin, best))
    ctop = max(STAT_ORDER, key=lambda k: chosen[k])
    if ctop in firsts:
        return "loot?", ("worn %s +%.1f pts, but their own gems and enchants "
                         "pick %s -- that is loot supply, not preference"
                         % (top, margin, ctop))
    cbest = max(firsts, key=lambda k: chosen[k])
    cmargin = 100.0 * (chosen[ctop] - chosen[cbest]) / total
    return "FLAG", ("worn %s +%.1f pts and chosen %s +%.1f pts -- both "
                    "disagree with %s"
                    % (top, margin, ctop, cmargin, "/".join(sorted(firsts))))


def shipped():
    """Data/StatPriority.lua through the real Lua loader, exactly the way
    scan_statpriority.py does it -- one parser, so the two scanners cannot
    drift into disagreeing about what we actually ship."""
    out = subprocess.run(["lua", "tools/dump_statpriority.lua"], cwd=ADDON,
                         capture_output=True, text=True)
    if out.returncode != 0:
        die("lua dump failed:" + chr(10) + (out.stderr or ""))
    rows = {}
    for line in out.stdout.splitlines():
        f = line.split("|")
        if len(f) == 4:
            rows.setdefault(int(f[0]), {})[(f[1], f[2])] = f[3]
    if len(rows) < 40:
        die("dump_statpriority.lua returned rows for only %d specs; expected "
            "40. A partial dump would silently turn missing specs into "
            '"no-data" rows.' % len(rows))
    return rows


def candidates_for(have, spec_id, bucket):
    """Every hero-tree row we ship for this bucket. mythic falls back to raid,
    which is exactly what Data/StatPriority.lua's header means by "omit when
    identical to raid"."""
    mine = have.get(spec_id, {})
    trees = sorted(set(k[0] for k in mine))
    out = []
    for t in trees:
        text = mine.get((t, bucket))
        if text is None and bucket == "mythic":
            text = mine.get((t, "raid"))
        if text:
            out.append(parse_shipped(text))
    return out


# --------------------------------------------------------- negative controls

def cached_entries():
    """Every ranking entry sitting in the cache, for the offline checks."""
    out = []
    if not os.path.isdir(CACHE):
        return out
    for f in sorted(os.listdir(CACHE)):
        if f.startswith("wcl-rank-") and f.endswith(".json"):
            cr = json.load(io.open(cache_path(f), encoding="utf-8"))
            out.extend(cr.get("rankings") or [])
    return out


def verify(api):
    """Negative controls. A green run here means the mechanisms are LOAD
    BEARING, not merely present -- each check breaks the thing it is checking
    and requires the result to change. Returns the number of failures."""
    bad = []

    def check(name, ok, detail=""):
        print("  %-46s %s%s" % (name, "PASS" if ok else "FAIL",
                                ("  " + detail) if detail else ""))
        if not ok:
            bad.append(name)

    print()
    print("negative controls")
    wmap = wildcard_map()
    combos = set(tuple(sorted(s for _o, s in v)) for v in wmap.values()
                 if len(v) == 2)
    check("ItemBonus Type=25 covers all six stat pairs", len(combos) == 6,
          "%d combos over %d bonusIDs" % (len(combos), len(wmap)))

    entries = cached_entries()
    if not entries:
        print("  %-46s SKIP  no cached rankings; run a scan first"
              % "wildcard resolution is load bearing")
        print("  (SKIP is not PASS -- assertion 4 is unverified this run)")
    else:
        ids = set()
        for e in entries:
            for g in gear_of(e):
                ids.add(g["id"])
        rows = item_rows(ids)
        seen = {}
        d_on, d_off = Diag(), Diag()
        for e in entries:
            for g in gear_of(e):
                on = resolve_item(g, rows, wmap, d_on)
                off = resolve_item(g, rows, {}, d_off)
                if on is not None and off is None:
                    seen.setdefault(g["id"], set()).add(
                        tuple(sorted(n for n, _v in on)))
        multi = {k: v for k, v in seen.items() if len(v) > 1}
        check("wildcard resolution is load bearing",
              d_on.resolved > d_off.resolved,
              "resolved %d with bonusIDs vs %d without (+%d)"
              % (d_on.resolved, d_off.resolved, d_on.resolved - d_off.resolved))
        check("one item id resolves >1 way across characters", bool(multi),
              "%d such ids, e.g. %s" % (len(multi), sorted(multi)[:3]))

    ench = enchant_index()
    covered = set(s for v in ench.values() for s in v)
    check("SpellItemEnchantment yields all four secondaries",
          covered == set(STAT_ORDER), "%d enchants, %s"
          % (len(ench), ",".join(sorted(covered)) or "none"))

    # Assertion 9's two gates, on synthetic rows, plus the negative control
    # that proves the margin gate is load bearing rather than decorative.
    ships = [[["mastery"], ["crit"], ["haste"], ["versatility"]]]
    thin = {"crit": 0.31, "haste": 0.25, "mastery": 0.30, "versatility": 0.14}
    wide = {"crit": 0.40, "haste": 0.25, "mastery": 0.25, "versatility": 0.10}
    picks_us = {"crit": 10.0, "haste": 5.0, "mastery": 60.0, "versatility": 1.0}
    picks_them = {"crit": 60.0, "haste": 5.0, "mastery": 10.0, "versatility": 1.0}
    check("a 1-point lead is not a disagreement",
          verdict(thin, picks_them, ships)[0] == "thin",
          "got %r" % (verdict(thin, picks_them, ships)[0],))
    check("gear disagrees but their gems agree -> loot?",
          verdict(wide, picks_us, ships)[0] == "loot?",
          "got %r" % (verdict(wide, picks_us, ships)[0],))
    check("both disagree past the margin -> FLAG",
          verdict(wide, picks_them, ships)[0] == "FLAG",
          "got %r" % (verdict(wide, picks_them, ships)[0],))
    global MIN_MARGIN
    keep, MIN_MARGIN = MIN_MARGIN, 0.0
    without = verdict(thin, picks_them, ships)[0]
    MIN_MARGIN = keep
    check("the margin gate is load bearing (negative control)",
          without == "FLAG",
          "with MIN_MARGIN=0 the same thin row reads %r" % (without,))

    if api is not None:
        live = api.gql("query { gameData { classes { slug specs { slug } } } }")
        slugs = set()
        for c in ((live.get("gameData") or {}).get("classes") or []):
            for s in (c.get("specs") or []):
                slugs.add(s.get("slug"))
        check("a de-slugged spec name is genuinely rejected",
              "Beast Mastery" not in slugs and "BeastMastery" in slugs,
              "the trap assertion 1 exists for is real")
    else:
        print("  %-46s SKIP  --offline" % "de-slugged spec name is rejected")
    return len(bad)


# ------------------------------------------------------------------- report

BANNER = """
====================================================================================================
OBSERVED secondary-stat distribution of ranked players, vs what we ship.

This is an OBSERVATION, and it is admissible as COUNTER-EVIDENCE ONLY. What
people wear is a confound of the same guides we read, of loot RNG, and of item
level dominating secondaries. "They stack X" therefore does not argue for X.
"We lead with X and out there X is last" is worth a second look, and that --
and nothing else -- is what a FLAG means here.

n is the number of ranked players whose gear actually resolved. Below n=%d no
verdict is issued at all.
====================================================================================================""" % MIN_N


def pct(x):
    return "%4.1f%%" % (100.0 * x)


def report(results, have, diag, api_calls, soft_errors):
    print(BANNER)
    print("%-5s %-13s %-14s %-6s %4s  %-5s %-5s %-5s %-5s  %-24s %-8s %s"
          % ("spec", "class", "spec", "zone", "n", "crit", "haste", "mast",
             "vers", "observed", "verdict", "why / what we ship"))
    print("-" * 100)
    flags = 0
    for r in sorted(results, key=lambda r: (r["spec"]["id"], r["zone"])):
        s, dist = r["spec"], r["dist"]
        cands = candidates_for(have, s["id"],
                               "raid" if r["zone"] == "raid" else "mythic")
        if dist is None or r["n"] == 0:
            print("%-5s %-13s %-14s %-6s %4s  %s"
                  % (s["id"], s["cls"], s["spec"], r["zone"], 0,
                     "(no ranked players resolved; count=%s)" % r["count"]))
            continue
        if r["n"] < MIN_N:
            v, why = "n<%d" % MIN_N, "sample too small to be counter-evidence"
        else:
            v, why = verdict(dist, r["chosen"], cands)
            if v == "FLAG":
                flags += 1
        shipped_txt = " | ".join(" > ".join("=".join(g) for g in c)
                                 for c in cands) or "(nothing shipped)"
        print("%-5s %-13s %-14s %-6s %4d  %-5s %-5s %-5s %-5s  %-24s %-8s %s"
              % (s["id"], s["cls"], s["spec"], r["zone"], r["n"],
                 pct(dist["crit"]), pct(dist["haste"]), pct(dist["mastery"]),
                 pct(dist["versatility"]), " > ".join(order_of(dist)), v,
                 (why + "  ") if why else "") + shipped_txt)
        if r["sockets"]:
            tot = sum(r["chosen"].values()) or 1.0
            print("%s chosen (gems+enchants, %d picks): %s"
                  % (" " * 45, r["sockets"],
                     "  ".join("%s %s" % (k, pct(r["chosen"][k] / tot))
                               for k in order_of(r["chosen"]))))

    print()
    print("--- resolution diagnostics (nothing above was dropped silently) ---")
    print("  items resolved to secondaries      %d" % diag.resolved)
    print("  wildcard items seen                %d  (resolved %d, partial %d, "
          "unresolved %d)"
          % (diag.wild_seen, diag.wild_resolved, diag.wild_partial,
             diag.wild_seen - diag.wild_resolved - diag.wild_partial))
    print("  skipped, no stats by design        %d  (shirt / tabard)"
          % diag.no_stat_slot)
    print("  skipped, no secondary budget       %d" % diag.no_secondary)
    print("  skipped, no ItemSparse row at all  %d" % diag.no_row)
    if diag.unknown_stats:
        print("  UNRECOGNISED stat ids              %s"
              % ", ".join("%d x%d" % (k, v)
                          for k, v in sorted(diag.unknown_stats.items())))
        print("    ^ a new wildcard family or a new stat id would appear here "
              "rather than silently inflating the skip counts.")
    else:
        print("  unrecognised stat ids              none")
    print()
    if soft_errors:
        print()
        print("--- %d calls the API refused (these rows are MISSING above, "
              "not empty) ---" % len(soft_errors))
        for m in sorted(set(soft_errors))[:10]:
            print("  " + m)
    print()
    print("api calls %d (~%.0f points), specs flagged %d"
          % (api_calls, api_calls * POINTS_PER_CALL, flags))
    return flags


# --------------------------------------------------------------------- main

def player_key(e):
    """The same player parses several bosses. Counting them once per boss
    would report n=900 for a hundred people and make every distribution look
    far better supported than it is."""
    srv = e.get("server") or {}
    return "%s|%s" % (e.get("name"), srv.get("id") or srv.get("name"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cached", action="store_true",
                    help="reuse tools/.scan-cache instead of refetching")
    ap.add_argument("--only", type=int, action="append",
                    help="limit to these specIDs")
    ap.add_argument("--zone", choices=("raid", "mplus", "both"), default="both")
    ap.add_argument("--plan", action="store_true",
                    help="print the call count and point cost, spend nothing")
    ap.add_argument("--verify", action="store_true",
                    help="run the negative controls and exit")
    ap.add_argument("--offline", action="store_true",
                    help="with --verify: skip the checks that need the API")
    ap.add_argument("--force", action="store_true",
                    help="proceed even if the plan exceeds the hourly budget")
    ap.add_argument("--json", metavar="PATH", help="also write the raw result")
    args = ap.parse_args()

    specs = roster()
    if args.only:
        specs = [s for s in specs if s["id"] in set(args.only)]
        if not specs:
            die("--only matched none of the 40 specs in ns.SpecGear")
    keys = ["raid", "mplus"] if args.zone == "both" else [args.zone]

    if args.plan:
        enc = sum(EXPECTED_ZONES[k][2] for k in keys)
        calls = enc * len(specs)
        print("plan: %d encounters x %d specs = %d calls, ~%.0f points "
              "(%.0f%% of the 3600/hour limit). Nothing spent."
              % (enc, len(specs), calls, calls * POINTS_PER_CALL,
                 100.0 * calls * POINTS_PER_CALL / 3600.0))
        return 0

    if args.verify:
        api = None if args.offline else Api(get_token(load_conf()))
        return 1 if verify(api) else 0

    api = Api(get_token(load_conf()))
    verify_roster(api, specs)                       # assertion 1
    zs = zones(api)                                 # assertion 8

    fresh = 0
    for key in keys:
        for enc in zs[key]["encounters"]:
            for s in specs:
                if not os.path.exists(cache_path(
                        "wcl-rank-%d-%d.json" % (enc["id"], s["id"]))):
                    fresh += 1
    rl = api.rate_limit()
    try:
        left = float(rl.get("limitPerHour") or 0) - float(
            rl.get("pointsSpentThisHour") or 0)
    except (TypeError, ValueError):
        left = 0.0
    cost = fresh * POINTS_PER_CALL
    print("plan: %d fresh calls, ~%.0f points; %.0f left this hour "
          "(resets in %ss)" % (fresh, cost, left, rl.get("pointsResetIn")))
    if not args.cached and cost > left and not args.force:
        die("the plan needs ~%.0f points and only %.0f remain this hour. "
            "Re-run after the reset, narrow it with --zone/--only, or pass "
            "--force to run it anyway and fail partway." % (cost, left))

    buckets, missing = {}, 0
    for key in keys:
        for enc in zs[key]["encounters"]:
            for s in specs:
                cr = rankings(api, enc["id"], s, args.cached)
                if cr is None:
                    missing += 1
                    continue
                b = buckets.setdefault((key, s["id"]),
                                       {"seen": {}, "count": 0})
                b["count"] = max(b["count"], int(cr.get("count") or 0))
                for e in (cr.get("rankings") or []):
                    b["seen"].setdefault(player_key(e), e)
    if missing:
        print("  --cached: %d spec/encounter pairs are not in the cache and "
              "were skipped" % missing)

    ids = set()
    for b in buckets.values():
        for e in b["seen"].values():
            for g in gear_of(e):
                ids.add(g["id"])
                ids.update(g["gems"])
    if not ids:
        die("no gear was returned at all. With assertion 1 verified above, "
            "this is not a slug problem -- read the raw cache before "
            "believing any distribution.")
    rows = item_rows(ids)
    wmap = wildcard_map()
    ench = enchant_index()
    gems = gem_index(rows, ench)
    print("resolvers: %d items, %d wildcard bonusIDs, %d stat enchants, "
          "%d stat gems" % (len(rows), len(wmap), len(ench), len(gems)))

    by_id = {s["id"]: s for s in specs}
    results, total = [], Diag()
    for (key, sid), b in buckets.items():
        entries = list(b["seen"].values())
        dist, chosen, sockets, n, diag = tally(entries, rows, wmap, gems, ench)
        total.merge(diag)
        results.append({"spec": by_id[sid], "zone": key, "dist": dist,
                        "chosen": chosen, "sockets": sockets, "n": n,
                        "count": b["count"]})
    flags = report(results, shipped(), total, api.calls,
                   api.soft_errors)

    if args.json:
        with io.open(args.json, "w", encoding="utf-8") as f:
            json.dump([{"spec": r["spec"], "zone": r["zone"], "n": r["n"],
                        "count": r["count"], "dist": r["dist"],
                        "chosen": r["chosen"], "sockets": r["sockets"]}
                       for r in results], f, indent=1, ensure_ascii=False)
    return 0 if flags >= 0 else 1


if __name__ == "__main__":
    sys.exit(main())
