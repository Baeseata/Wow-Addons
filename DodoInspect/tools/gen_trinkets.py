#!/usr/bin/env python3
"""Generate Data/Trinkets.lua -- per-spec trinket order from bloodmallet.com.

Run once per season, alongside gen_loot.py:

    python tools/gen_trinkets.py            # rewrites Data/Trinkets.lua
    python tools/gen_trinkets.py --dry-run  # report only, writes nothing

Why an external source at all: 33 of the 42 trinkets in Data/Loot.lua carry
NO secondary stats, so the stat-fit sort that ranks every other slot is
structurally unable to order them. Their value is in the on-item effect --
which a simulation prices and a stat sort cannot see.

Source: https://bloodmallet.com (free to use; the site asks only that we
credit it, which Options does). Fight style is single-target on purpose --
see TRINKET_DATA_RESEARCH_2026-08-14.md for the measured 1T-vs-3T delta.

THREE ASSERTIONS THAT MUST NOT BE REMOVED (each is a real trap, measured):

  1. The spec slug list is fetched from bloodmallet's own classes_specs.js,
     not typed here. A wrong slug and a genuinely absent spec return the
     identical {"status":"error"}, so a hand-typed list produces false
     "missing" entries that read exactly like real gaps.

  2. Every payload must report the SAME simc tier. The endpoint happily
     serves last season's data for specs that have not been re-simmed --
     HTTP 200, normal shape, nothing saying it is stale. Only
     simc_settings.tier tells them apart. Shipping that silently would mean
     shipping last season's rankings.

  3. The spec ids here must exactly match ns.SpecGear in Data/Loot.lua.
     Two hand-written spec lists drift; this one is checked against the
     other rather than trusted.
"""

import argparse
import csv
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request

UA = {"User-Agent": "DodoInspect-gen_trinkets/1.0"}
HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)
LOOT = os.path.join(ADDON, "Data", "Loot.lua")
OUT = os.path.join(ADDON, "Data", "Trinkets.lua")

SPEC_LIST_URL = "https://bloodmallet.com/static/general_website/js/classes_specs.js"
CHART_URL = "https://bloodmallet.com/chart/get/trinkets/%s/%s/%s"
ITEM_CSV = "https://wago.tools/db2/Item/csv"

FIGHT_STYLE = "castingpatchwerk"
TRINKET_INVENTORY_TYPE = 12

# bloodmallet (class, spec) -> ChrSpecialization id. Checked against
# ns.SpecGear below; a mismatch is fatal rather than a silent partial run.
SPEC_IDS = {
    ("death_knight", "blood"): 250, ("death_knight", "frost"): 251,
    ("death_knight", "unholy"): 252,
    ("demon_hunter", "havoc"): 577, ("demon_hunter", "vengeance"): 581,
    ("demon_hunter", "devourer"): 1480,
    ("druid", "balance"): 102, ("druid", "feral"): 103,
    ("druid", "guardian"): 104, ("druid", "restoration"): 105,
    ("evoker", "devastation"): 1467, ("evoker", "preservation"): 1468,
    ("evoker", "augmentation"): 1473,
    ("hunter", "beast_mastery"): 253, ("hunter", "marksmanship"): 254,
    ("hunter", "survival"): 255,
    ("mage", "arcane"): 62, ("mage", "fire"): 63, ("mage", "frost"): 64,
    ("monk", "brewmaster"): 268, ("monk", "windwalker"): 269,
    ("monk", "mistweaver"): 270,
    ("paladin", "holy"): 65, ("paladin", "protection"): 66,
    ("paladin", "retribution"): 70,
    ("priest", "discipline"): 256, ("priest", "holy"): 257,
    ("priest", "shadow"): 258,
    ("rogue", "assassination"): 259, ("rogue", "outlaw"): 260,
    ("rogue", "subtlety"): 261,
    ("shaman", "elemental"): 262, ("shaman", "enhancement"): 263,
    ("shaman", "restoration"): 264,
    ("warlock", "affliction"): 265, ("warlock", "demonology"): 266,
    ("warlock", "destruction"): 267,
    ("warrior", "arms"): 71, ("warrior", "fury"): 72,
    ("warrior", "protection"): 73,
}


def get(url, timeout=60):
    return urllib.request.urlopen(
        urllib.request.Request(url, headers=UA), timeout=timeout).read().decode("utf-8")


def authoritative_slugs():
    """bloodmallet's own class/spec roster -- see assertion 1 in the header."""
    raw = get(SPEC_LIST_URL)
    body = raw[raw.index("{"):raw.rindex("}") + 1]
    pairs = []
    for cls, specs in re.findall(r'"([a-z_]+)"\s*:\s*\[([^\]]*)\]', body):
        for spec in re.findall(r'"([a-z_]+)"', specs):
            pairs.append((cls, spec))
    return pairs


def our_trinkets():
    """Item ids in Data/Loot.lua whose InventoryType says trinket.

    Slot is deliberately absent from Loot.lua (the client answers it at
    runtime), so trinket identity comes from the Item table, not from us.
    """
    src = open(LOOT, encoding="utf-8").read()
    ids = {m for m in re.findall(r"^\s*\[(\d+)\]\s*=\s*\{",
                                 src[src.index("ns.Loot"):], re.M)}
    gear = src[src.index("ns.SpecGear"):src.index("ns.SpecWeapons")]
    spec_ids = {int(s) for s in re.findall(r"\[(\d+)\]\s*=\s*\{", gear)}

    csv.field_size_limit(10 ** 7)
    trinkets = set()
    for row in csv.DictReader(io.StringIO(get(ITEM_CSV, timeout=180))):
        if row["ID"] in ids and int(row.get("InventoryType") or 0) == TRINKET_INVENTORY_TYPE:
            trinkets.add(int(row["ID"]))
    return trinkets, spec_ids


def fetch_spec(cls, spec, pool):
    """Ranked item ids for one spec, restricted to our pool.

    bloodmallet emits one row per simulated CONFIGURATION, so a trinket with
    selectable effects (Ruby Whelp Shell) appears several times under one
    item id. The best-placed variant wins: that is what the trinket is worth
    to someone who sets it up correctly.
    """
    try:
        payload = json.loads(get(CHART_URL % (FIGHT_STYLE, cls, spec)))
    except urllib.error.HTTPError as e:
        return None, "HTTP %s" % e.code
    if not isinstance(payload, dict) or payload.get("status") == "error":
        return None, None
    ids = payload.get("item_ids") or {}
    tier = (payload.get("simc_settings") or {}).get("tier")
    ordered, seen = [], set()
    for name in payload.get("sorted_data_keys") or []:
        item = int(ids.get(name, 0))
        if item in pool and item not in seen:
            seen.add(item)
            ordered.append(item)
    return {"order": ordered, "tier": tier,
            "stamp": (payload.get("metadata") or {}).get("timestamp")}, None


def render(rows, tier, pool_size):
    out = []
    add = out.append
    add("-- DodoInspect - Data/Trinkets.lua")
    add("-- Per-spec trinket order, generated by tools/gen_trinkets.py.")
    add("-- Do not hand-edit. Regenerate each season, with Data/Loot.lua.")
    add("--")
    add("-- Source: bloodmallet.com, SimulationCraft, fight style")
    add("-- %s (single target), simc tier %s." % (FIGHT_STYLE, tier))
    add("--")
    add("-- Ordering is bloodmallet's own sorted_data_keys, which ranks each")
    add("-- trinket at ITS OWN highest simulated item level. That matters:")
    add("-- every trinket sits on a different item level track, so there is")
    add("-- no single item level at which they can all be compared. The")
    add("-- question it answers -- 'once upgraded, which is best' -- is also")
    add("-- the question a candidate list is asking.")
    add("--")
    add("-- Specs absent from this table have no simulation data at all.")
    add("-- That is a fact about the source, not about the player, so the")
    add("-- panel says so in words instead of showing an empty or")
    add("-- arbitrarily ordered list.")
    add("--")
    add("-- DATA ONLY, ASCII ONLY. Item ids only; names resolve in game.")
    add("")
    add("local _, ns = ...")
    add("")
    add("-- specID -> item ids, best first. Ids not listed for a covered spec")
    add("-- were not simulated for it and sort after the ranked ones.")
    add("ns.TrinketRank = {")
    for spec_id, order, label in rows:
        add("    -- %s" % label)
        add("    [%d] = { %s }," % (spec_id, ", ".join(str(i) for i in order)))
    add("}")
    add("")
    add("ns.TrinketRankMeta = {")
    add('    source = "bloodmallet.com",')
    add('    fightStyle = "%s",' % FIGHT_STYLE)
    add('    tier = "%s",' % tier)
    add("    specs = %d," % len(rows))
    add("    poolSize = %d," % pool_size)
    add("}")
    add("")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    slugs = authoritative_slugs()
    print("bloodmallet roster: %d specs" % len(slugs))

    unknown = [s for s in slugs if s not in SPEC_IDS]
    extra = [s for s in SPEC_IDS if s not in slugs]
    if unknown or extra:
        print("ERROR: spec roster drifted from SPEC_IDS in this script.")
        for s in unknown:
            print("   only upstream: %s/%s" % s)
        for s in extra:
            print("   only here:     %s/%s" % s)
        return 1

    pool, loot_spec_ids = our_trinkets()
    print("trinkets in Data/Loot.lua: %d" % len(pool))
    if set(SPEC_IDS.values()) != loot_spec_ids:
        print("ERROR: spec ids disagree with ns.SpecGear in Data/Loot.lua.")
        print("   here-not-there: %s" % sorted(set(SPEC_IDS.values()) - loot_spec_ids))
        print("   there-not-here: %s" % sorted(loot_spec_ids - set(SPEC_IDS.values())))
        return 1

    rows, tiers, skipped = [], set(), []
    for cls, spec in slugs:
        data, err = fetch_spec(cls, spec, pool)
        if err:
            print("ERROR: %s/%s -> %s" % (cls, spec, err))
            return 1
        if not data:
            skipped.append("%s/%s" % (cls, spec))
            continue
        if not data["order"]:
            print("ERROR: %s/%s answered but ranked none of our %d trinkets."
                  % (cls, spec, len(pool)))
            return 1
        tiers.add(data["tier"])
        rows.append((SPEC_IDS[(cls, spec)], data["order"],
                     "%s %s (%s, %s)" % (cls, spec, data["tier"],
                                         str(data["stamp"])[:10])))
        print("  %-14s %-14s %2d ranked   tier=%s" %
              (cls, spec, len(data["order"]), data["tier"]))

    if not rows:
        print("ERROR: no spec returned data. Refusing to write an empty table.")
        return 1
    if len(tiers) != 1:
        print("ERROR: payloads mix simc tiers %s -- at least one spec is "
              "serving a previous season. Refusing to ship mixed data."
              % sorted(tiers))
        return 1

    rows.sort(key=lambda r: r[0])
    tier = tiers.pop()
    print("\ncovered %d/%d specs, tier %s; no data for %d: %s"
          % (len(rows), len(slugs), tier, len(skipped), ", ".join(skipped) or "-"))

    text = render(rows, tier, len(pool))
    text.encode("utf-8")            # verify encodable BEFORE truncating the file
    if not text.isascii():
        print("ERROR: generated file is not ASCII.")
        return 1
    if args.dry_run:
        print("(dry run, %s not written)" % os.path.basename(OUT))
        return 0
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("wrote %s" % OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
