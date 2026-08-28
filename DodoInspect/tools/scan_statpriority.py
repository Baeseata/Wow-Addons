#!/usr/bin/env python3
"""Scan all 40 Wowhead stat-priority guides and diff them against Data/StatPriority.lua.

    python tools/scan_statpriority.py                # fetch + report
    python tools/scan_statpriority.py --cached       # reuse the last fetch
    python tools/scan_statpriority.py --only 263     # one spec

This replaces the hand-run curl loop described in CLAUDE.md 1.13.1. The
prose version was run by hand three times and got a different answer each
time, because every one of the traps below is silent.

FIVE ASSERTIONS THAT MUST NOT BE REMOVED (each is a measured trap):

  1. Wowhead's BBCode lives inside a JSON string, so every closing tag is
     escaped: the page contains [\\/ol], never [/ol]. A [ol](.*?)[/ol]
     regex therefore matches NOTHING and returns an empty list -- and an
     empty list reads exactly like "this page has no ordered list".
     Measured 2026-08-27 on enhancement: [ol] x2, [/ol] x0, [\\/ol] x2.
     unescape() runs before any parsing and is asserted below.

  2. A REALISTIC browser User-Agent gets 403'd; the naive one does not.
     Measured 2026-08-27, same URL, same second:
        -A "Mozilla/5.0"                      -> 200, 69488 bytes
        -A "curl/8.0"                         -> 200
        no UA at all                          -> 200
        -A "Mozilla/5.0 (Windows NT 10.0; ... Chrome/120 ..." -> 403
     CloudFront blocks the spoofed-browser shape, not the honest one. Do
     not "improve" UA below; it is the thing that works.

  3. Items open as [li] OR [li icon=angle-right]. A \\[li\\] regex silently
     drops the second kind. Measured: 31 x [li] vs 41 closing tags on one
     page. Missing items do not look like an error -- they look like a
     shorter priority.

  4. Every extracted order must hold exactly the four secondaries, each
     once, after the primary stat is dropped. The third [li] writing style
     packs two stats into one item ("Critical Strike = Mastery"); it fails
     by UNDER-counting, so the page still yields a well-formed-looking
     order that is quietly missing two stats. Anything but 4 is fatal.

  5. The spec roster is joined from wago.tools DB2 (ChrSpecialization x
     ChrClasses) and cross-checked against ns.SpecGear in Data/Loot.lua.
     A hand-typed slug that is wrong and a spec that genuinely has no
     guide both return 404.
"""

import argparse
import csv
import io
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

# Assertion 2: this exact string. Do not lengthen it.
UA = {"User-Agent": "Mozilla/5.0"}

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)
LOOT = os.path.join(ADDON, "Data", "Loot.lua")
DATA = os.path.join(ADDON, "Data", "StatPriority.lua")
CACHE = os.path.join(HERE, ".scan-cache")

DB2 = "https://wago.tools/db2/%s/csv"
GUIDE = "https://www.wowhead.com/guide/classes/%s/%s/stat-priority-pve-%s"

ROLE_SUFFIX = {"0": "tank", "1": "healer", "2": "dps"}

# Tokens that legitimately appear inside a priority list but are not
# secondaries. Kept EXPLICIT: a catch-all "ignore what I cannot map" would
# turn every future writing style into a silently shorter priority, which is
# the exact failure mode assertion 4 exists to catch. Measured on the 2026-08
# pages -- tank guides open with item level, hunters with weapon damage.
PRIMARY = {
    "agility", "strength", "intellect", "stamina", "armor",
    "item level", "weapon damage", "weapon dps", "attack power", "spell power",
    "main stat", "primary stat",
}
SECONDARY = {
    "critical strike": "crit",
    "crit": "crit",
    "haste": "haste",
    "mastery": "mastery",
    "versatility": "versatility",
    "vers": "versatility",
}
ALL_SECONDARIES = {"crit", "haste", "mastery", "versatility"}


def get(url, binary=False):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = r.read()
    return raw if binary else raw.decode("utf-8", "replace")


def cached(name, url):
    """Fetch once per run into tools/.scan-cache so --cached can replay it."""
    path = os.path.join(CACHE, name)
    if os.path.exists(path):
        return io.open(path, encoding="utf-8").read()
    body = get(url)
    if not os.path.isdir(CACHE):
        os.makedirs(CACHE)
    tmp = path + ".tmp"
    with io.open(tmp, "w", encoding="utf-8") as f:
        f.write(body)
    os.replace(tmp, path)
    return body


def unescape(html):
    """Assertion 1. Wowhead ships BBCode inside a JSON string literal."""
    return html.replace(chr(92) + "/", "/")


def loot_spec_ids():
    """Assertion 5, half one: the shipped roster is the source of truth."""
    body = io.open(LOOT, encoding="utf-8").read()
    block = re.search(r"ns\.SpecGear\s*=\s*\{(.*?)\n\}", body, re.S)
    if not block:
        sys.exit("FATAL: ns.SpecGear not found in " + LOOT)
    ids = [int(n) for n in re.findall(r"\[(\d+)\]\s*=\s*\{", block.group(1))]
    if len(ids) != 40:
        sys.exit("FATAL: expected 40 specs in ns.SpecGear, found %d" % len(ids))
    return ids


def slugify(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def roster():
    """Assertion 5, half two: slugs are derived from DB2, never typed here."""
    specs = list(csv.DictReader(io.StringIO(
        cached("ChrSpecialization.csv", DB2 % "ChrSpecialization"))))
    classes = {r["ID"]: r for r in csv.DictReader(io.StringIO(
        cached("ChrClasses.csv", DB2 % "ChrClasses")))}
    by_id = {int(r["ID"]): r for r in specs}
    out = []
    for sid in loot_spec_ids():
        r = by_id.get(sid)
        if r is None:
            sys.exit("FATAL: specID %d is in ns.SpecGear but not in DB2" % sid)
        cls = classes[r["ClassID"]]
        out.append({
            "id": sid,
            "spec": r["Name_lang"],
            "cls": cls["Name_lang"],
            "class_slug": slugify(cls["Name_lang"]),
            "spec_slug": slugify(r["Name_lang"]),
            "role": ROLE_SUFFIX[r["Role"]],
        })
    return out


def hero_slug(name):
    """Wowhead drops apostrophes: San'layn -> sanlayn, Elune's Chosen ->
    elunes-chosen. slugify() would give san-layn and never match."""
    return re.sub(r"[^a-z0-9]+", "-", name.lower().replace("'", "")).strip("-")


def hero_trees():
    """specID -> {wowhead slug: subTreeID}, all from DB2.

    ASSERTION 6 (measured 2026-08-27): Enhancement maps to THREE trait trees
    in TraitTreeLoadout -- 786, 1033 and 1034 -- and each carries its own
    Stormbringer/Totemic/Farseer triple (54/55/56, 70/71/72, 73/74/75) with
    identical names, identical descriptions and identical atlas ids. Every
    other class maps to exactly one tree, so nothing warns you. The class
    talent tree is the one SkillLineXTraitTree names for the class skill
    line; 1033/1034 appear in that table not at all. Picking by "lowest id"
    or "first row" happens to be right today and is not a criterion.
    """
    sub = list(csv.DictReader(io.StringIO(cached(
        "TraitSubTree.csv", DB2 % "TraitSubTree"))))
    loadout = list(csv.DictReader(io.StringIO(cached(
        "TraitTreeLoadout.csv", DB2 % "TraitTreeLoadout"))))
    skill = list(csv.DictReader(io.StringIO(cached(
        "SkillLineXTraitTree.csv", DB2 % "SkillLineXTraitTree"))))
    class_trees = {r["TraitTreeID"] for r in skill}     # assertion 6
    by_tree = {}
    for r in sub:
        by_tree.setdefault(r["TraitTreeID"], []).append(r)
    out = {}
    for r in loadout:
        if r["TraitTreeID"] not in class_trees:
            continue
        spec = int(r["ChrSpecializationID"])
        for t in by_tree.get(r["TraitTreeID"], []):
            if t["Name_lang"]:
                out.setdefault(spec, {})[hero_slug(t["Name_lang"])] = int(t["ID"])
    return out


OL_RE = re.compile(r"\[ol\](.*?)\[/ol\]", re.S)
LI_RE = re.compile(r"\[li[^\]]*\](.*?)\[/li\]", re.S)   # assertion 3
TAG_RE = re.compile(r"\[[^\]]*\]")
HERO_RE = re.compile(r"wow-hero-talent-([a-z0-9\-]+)")
TAB_RE = re.compile(r"\[tab name=")
DATE_RE = re.compile(r'"dateModified"\s*:\s*"([^"]+)"')


GOAL_TAIL_RE = re.compile(
    r"\s+(?:to|until|above|below|past|up to|at least)\s+.*$", re.I)


def parse_item(text):
    """One [li] -> (stat keys in this tie group, goal text). Raises on unknown.

    Six writing styles measured on the 2026-08 pages, all in live use:
        [li][b]Haste[/b] (~700)                 goal in parentheses
        [li]Strength[/li]                       bare, no bold
        [li][b]Critical Strike = Mastery[/b]    two stats, one item
        [li][b]Crit[/b]                         abbreviated
        [li]Haste/Crit[/li]                     slash instead of '='
        [li]Mastery to 1200 rating[/li]         goal as trailing prose
    """
    plain = TAG_RE.sub("", text)
    goal = " ".join(re.findall(r"\(([^)]*)\)", plain)).strip()
    plain = re.sub(r"\([^)]*\)", " ", plain)
    tail = GOAL_TAIL_RE.search(plain)
    if tail:
        goal = (goal + " " + tail.group(0)).strip()
        plain = plain[:tail.start()]
    stats, dropped = [], []
    for part in re.split(r"[=/]|,| or | and ", plain):
        word = re.sub(r"[^a-z ]", " ", part.lower()).strip()
        word = re.sub(r"\s+", " ", word)
        if not word:
            continue
        if word in PRIMARY:
            dropped.append(word)
        elif word in SECONDARY:
            stats.append(SECONDARY[word])
        else:
            raise ValueError("unmapped stat text: %r" % part.strip())
    return stats, goal, dropped


# Measured: the hero-tree symbol that labels a list sits 80-110 characters
# in front of its [ol]. Anything further away belongs to a different
# section. 200 is a deliberate margin, not a tuned value.
HERO_WINDOW = 200

# Two container styles are in live use for the same thing:
#     [box border=true]                       (most pages)
#     [div style="border:1px solid #f3710c"]  (warrior, hunter, DK, ...)
# A [box]-only regex leaves those pages unlabelled, which reads as
# "this page has no headings" rather than "I looked for the wrong tag".
BOX_RE = re.compile(r"\[(?:box|div)[^\]]*\]")
CENTER_RE = re.compile(r"\[center\](.*?)\[/center\]", re.S)
# A hero box can itself hold two lists split by content:
#     [b]Single-Target:[/b] [ol]...[/ol]  [b]AoE:[/b] [ol]...[/ol]
SUBLABEL_RE = re.compile(r"\[b\]([^\[\]]{1,40}:)\[/b\]")


def box_label(u, ol_start):
    """The heading of the [box] this [ol] lives in -- the authoritative label.

    ASSERTION 8 (measured 2026-08-27, all 40 pages): every stat list sits in
    a `[box border=true]` opened by a `[center]...[/center]` heading, and the
    heading says what the box is:

        [symbol=wow-hero-talent-aldrachi-reaver] [b]Aldrachi Reaver[/b] ...
        [b][color=q9]Survivability[/color] Stat Priority[/b]
        [b] Preservation [color=venthyr]Raid[/color] Stat Priority[/b]

    Two side-by-side boxes therefore mean a HERO SPLIT or a CONTENT SPLIT and
    the heading is the only thing that tells them apart. Reading the boxes and
    guessing was how spec 1468 shipped a Raid/Mythic+ pair as two hero trees
    in 1.13.0. Related: `[tab name=` -- which CLAUDE.md named as the
    content-split marker -- occurs ZERO times across all 40 current pages.
    """
    boxes = [m.start() for m in BOX_RE.finditer(u) if m.start() < ol_start]
    if not boxes:
        return None
    head = CENTER_RE.search(u[boxes[-1]:ol_start])
    if not head:
        return None
    text = re.sub(r"\s+", " ", TAG_RE.sub(" ", head.group(1))).strip()
    subs = SUBLABEL_RE.findall(u[boxes[-1] + head.end():ol_start])
    if subs:
        text = (text + " / " + subs[-1].strip()).strip(" /")
    return text or None


def parse_page(html, allowed):
    """-> {date, trees, tabs, orders, notes, skipped}

    `allowed` is {wowhead slug: subTreeID} for THIS spec, from DB2.

    ASSERTION 7 (measured 2026-08-27): nearest-preceding-symbol alone is
    wrong. The Shadow Priest page carries a `wow-hero-talent-totemic` symbol
    95 characters before its second list -- Shadow has no Totemic -- and the
    Feral page repeats `druid-of-the-claw` where Wildstalker belongs. Both
    produce a confident, well-formed, wrong hero attribution. Symbols that
    are not one of this spec's own trees are counted and reported, never
    used.
    """
    u = unescape(html)
    if "[ol]" in u and "[/ol]" not in u:
        raise ValueError("assertion 1 broke: unescape() no longer produces [/ol]")
    date = DATE_RE.search(u)
    hits = [(m.start(), m.group(1)) for m in HERO_RE.finditer(u)]
    mine = [(p, n) for p, n in hits if n in allowed]
    foreign = sorted(set(n for _, n in hits if n not in allowed))
    orders, notes, skipped, seen = [], [], 0, set()
    for m in OL_RE.finditer(u):
        items = LI_RE.findall(m.group(1))
        try:
            parsed = [parse_item(x) for x in items]
        except ValueError as e:
            skipped += 1          # not a stat list (rotation, gems, ...)
            notes.append("skipped a list: %s" % e)
            continue
        order = [p[0] for p in parsed if p[0]]
        goals = {s: p[1] for p in parsed for s in p[0] if p[1]}
        flat = [s for grp in order for s in grp]
        if not flat:
            skipped += 1
            continue
        label = box_label(u, m.start())
        # The heading is authoritative; symbol proximity is the fallback.
        # Measured: the Feral page repeats druid-of-the-claw where the
        # Wildstalker box is, and only the heading gets it right.
        slug = None
        if label:
            lower = label.lower()
            for cand in sorted(allowed, key=len, reverse=True):
                if cand.replace("-", " ") in lower.replace("-", " "):
                    slug = cand
                    break
        if slug is None:
            near = [(p, n) for p, n in mine if 0 < m.start() - p <= HERO_WINDOW]
            slug = near[-1][1] if near else None
        # assertion 4 -- report, never silently accept a short priority
        if sorted(flat) != sorted(ALL_SECONDARIES):
            notes.append("NOT the 4 secondaries exactly once (%s): %s"
                         % (slug or "no tree", " > ".join(
                             "=".join(g) for g in order)))
            continue
        key = (label, slug, tuple(tuple(g) for g in order))
        if key in seen:           # Wowhead embeds the body twice per page
            continue
        seen.add(key)
        orders.append({"tree": slug, "subTreeID": allowed.get(slug),
                       "label": label, "order": order, "goals": goals})
    return {
        "date": date.group(1) if date else None,
        "trees": sorted(set(n for _, n in mine)),
        "foreign": foreign,
        "tabs": len(TAB_RE.findall(u)),
        "orders": orders,
        "notes": notes,
        "skipped": skipped,
    }


def fetch_guide(spec, force_role=None):
    """Try the DB2-derived role suffix first, then the other two (assertion 5:
    a wrong slug and a genuinely missing guide both 404, so say which won)."""
    tries = [force_role or spec["role"]]
    for r in ("dps", "tank", "healer"):
        if r not in tries:
            tries.append(r)
    last = None
    for role in tries:
        url = GUIDE % (spec["class_slug"], spec["spec_slug"], role)
        name = "guide-%d-%s.html" % (spec["id"], role)
        try:
            return cached(name, url), url, role
        except urllib.error.HTTPError as e:
            last = "HTTP %s" % e.code
        except Exception as e:                     # noqa: BLE001
            last = str(e)
    raise RuntimeError("no guide page for %s %s (%s)"
                       % (spec["cls"], spec["spec"], last))


def shipped():
    """Current Data/StatPriority.lua, via the real Lua loader."""
    out = subprocess.run(["lua", "tools/dump_statpriority.lua"], cwd=ADDON,
                         capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit("FATAL: lua dump failed:\n" + out.stderr)
    rows, meta = {}, {}
    for line in out.stdout.splitlines():
        f = line.split("|")
        if len(f) > 1 and f[1] == "meta":
            meta[int(f[0])] = line
        elif len(f) == 4:
            rows.setdefault(int(f[0]), {})[(f[1], f[2])] = f[3]
    return rows, meta


def render(order):
    return " > ".join("=".join(g) for g in order)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cached", action="store_true",
                    help="reuse tools/.scan-cache instead of refetching")
    ap.add_argument("--only", type=int, action="append",
                    help="limit to these specIDs")
    ap.add_argument("--json", metavar="PATH", help="also write the raw result")
    args = ap.parse_args()

    if not args.cached and os.path.isdir(CACHE):
        for f in os.listdir(CACHE):
            if f.startswith("guide-"):
                os.remove(os.path.join(CACHE, f))

    specs = roster()
    if args.only:
        specs = [s for s in specs if s["id"] in set(args.only)]
    have, meta = shipped()
    trees = hero_trees()

    results, errors, dates = [], [], {}
    for s in specs:
        try:
            html, url, role = fetch_guide(s)
            page = parse_page(html, trees.get(s["id"], {}))
        except Exception as e:                     # noqa: BLE001
            errors.append((s, str(e)))
            print("ERROR %-5s %-14s %-16s %s" % (s["id"], s["cls"], s["spec"], e))
            continue
        page.update(spec=s, url=url, role=role)
        results.append(page)
        dates.setdefault(page["date"], []).append(s["id"])

    print()
    print("=" * 100)
    print("%-5s %-13s %-15s %-10s %-6s %s" %
          ("spec", "class", "spec", "modified", "shape", "guide order  ->  VERDICT   box heading   tree"))
    print("=" * 100)
    changed = []
    for r in sorted(results, key=lambda r: r["spec"]["id"]):
        s = r["spec"]
        shape = "%dx%d" % (max(1, len(r["trees"])), max(1, r["tabs"]))
        head = "%-5s %-13s %-15s %-10s %-6s" % (
            s["id"], s["cls"], s["spec"], (r["date"] or "?")[:10], shape)
        mine = have.get(s["id"], {})
        first = True
        for o in r["orders"]:
            guide = render(o["order"])
            tree_key = str(o["subTreeID"]) if o["subTreeID"] else "0"
            exact = mine.get((tree_key, "raid")) == guide
            anywhere = [k for k in mine if mine[k] == guide]
            verdict = "same" if exact else (
                "same*" if anywhere else ("NEW" if not mine else "DIFFERS"))
            print("%s %-34s %-8s %-26.26s %s(%s)" %
                  (head if first else " " * 57, guide, verdict,
                   o.get("label") or "-", o["tree"] or "no-tree", tree_key))
            first = False
            if not exact:
                changed.append((s, o, guide, verdict))
        if not r["orders"]:
            print("%s %s" % (head, "(no usable stat list; %d lists skipped)" % r["skipped"]))
        for n in r["notes"]:
            print("%s  ! %s" % (" " * 57, n))
        if r["foreign"]:
            print("%s  ~ ignored foreign hero symbols: %s"
                  % (" " * 57, ", ".join(r["foreign"])))
    print()
    print("--- dateModified clusters (same minute = one Wowhead republish, not N authors) ---")
    for d in sorted(dates, key=lambda d: (d or "")):
        print("   %-30s %2d specs  %s" % (d, len(dates[d]), sorted(dates[d])))
    print()
    print("scanned %d, errors %d, rows differing from shipped %d"
          % (len(results), len(errors), len(changed)))
    if args.json:
        with io.open(args.json, "w", encoding="utf-8") as f:
            json.dump([{k: v for k, v in r.items()} for r in results], f,
                      indent=1, ensure_ascii=False, default=str)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
