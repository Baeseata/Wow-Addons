#!/usr/bin/env python3
"""Scan all 40 Wowhead stat-priority guides and diff them against Data/StatPriority.lua.

    python tools/scan_statpriority.py                # fetch + report
    python tools/scan_statpriority.py --cached       # reuse the last fetch
    python tools/scan_statpriority.py --only 263     # one spec
    python tools/scan_statpriority.py --verify       # offline branch checks

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

Assertions 6-9 are stated next to the code they constrain, because each one
is about a single function: hero_trees (6), parse_page (7), box_label (8) and
BUCKET_TOKENS (9). Same standing -- none of them may be removed either.
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




# --- how a guide box maps onto our (hero tree, bucket) grid ---------------
#
# ASSERTION 9 (added 2026-08-28). Until this date the only exact comparison
# in this file read mine.get((tree_key, "raid")), and the word "mythic" did
# not occur anywhere in the file -- so the mythic half of StatPriority.lua
# was never compared to anything, in EITHER direction:
#   * a shipped mythic row could not go red. It could only be satisfied by
#     the any-key fallback, which printed `same*`. Measured: 270 Mistweaver
#     ships a mythic row that is character-for-character the guide's Mythic+
#     box, and the scanner still called it `same*` -- the right answer was
#     in hand and the vocabulary could not say it.
#   * guide boxes headed Mythic+ were diffed against our raid row.
# A/B: shuffling every shipped mythic row found nothing before this, and one
# finding per shuffled row after.
#
# The buckets are DEFINED in Data/StatPriority.lua's header, not here:
#     raid   : Raid / single-target order
#     mythic : M+ / AoE order; omit when identical to raid
# and the "omit" half is real runtime behaviour, not a comment --
# StatPriority.lua:307 resolves M+ as `data.mythic or data.raid`. A Mythic+
# box against a spec that ships no mythic row is therefore compared to the
# raid row and reported `same-fb`, so "we agree about M+" and "we never
# expressed an M+ opinion" cannot print as the same word.
#
# Tank guides split on a THIRD axis this data model does not have --
# Survivability vs DPS (Monk writes it Defensive vs Offensive). The addon
# ships the survival order for tanks by standing decision (CLAUDE.md 1.13.1),
# so Survivability maps and DPS is reported `no-model` and counted, instead
# of being quietly diffed against a row that never claimed to answer it.
#
# Measured label census, all 40 pages 2026-08-28: 84 boxes, every one of them
# either carries one of these tokens or is a bare "<Hero Tree> Stat Priority".
BUCKET_TOKENS = [
    ("mythic+", "mythic"), ("aoe", "mythic"),
    ("raid", "raid"), ("single-target", "raid"), ("all situations", "raid"),
    ("survivability", "raid"), ("defensive", "raid"),
    ("dps", None), ("offensive", None),
]


def alpha(s):
    return re.sub(r"[^a-z]", "", (s or "").lower())


def bucket_of(label, slug):
    """-> ("raid" | "mythic" | None, complaint). None = an axis we do not model.

    A heading that matches no token counts as the general order ONLY if
    nothing is left once the hero-tree name and the words "stat priority"
    come out. Anything else is reported rather than folded into `raid`:
    silently folding an unknown heading into raid is the exact bug this
    assertion exists to undo, and a new Wowhead heading must not be able to
    re-enter through the default.
    """
    low = (label or "").lower()
    for token, bucket in BUCKET_TOKENS:
        if token in low:
            return bucket, None
    rest = alpha(label).replace(alpha(slug), "", 1)
    for word in ("statpriority", "priority", "stat"):
        rest = rest.replace(word, "", 1)
    if not rest:
        return "raid", None
    return None, "unrecognised box heading, not compared: %r" % label


def tiers(text):
    """The order as comparable tiers, ties as sets. Used ONLY to tell a real
    disagreement apart from a tie group we happen to have written in another
    sequence -- that gets its own verdict, it is never silently equated. The
    addon's own ElemEqual (StatPriority.lua:208) is positional, so equating
    them here would put the two implementations quietly out of step."""
    return [frozenset(g.split("=")) for g in text.split(" > ")]


def verdict_for(mine, tree_key, bucket, guide):
    """-> (verdict, detail, the shipped row this actually got compared to).

    Resolution order mirrors ResolveDefault in StatPriority.lua: hero tree
    FIRST, then bucket. A spec ships either per-tree `builds` rows or one
    flat row, never both (the shape guard in test_statpriority.lua enforces
    that), so a flat row is the answer for every hero tree -- reporting it as
    "some other hero tree agrees" would be nonsense, and that is exactly what
    the old any-key fallback did for 38 of the 84 boxes.
    """
    if bucket is None:
        return "no-model", "", None
    if not mine:
        return "NEW", "", None
    split = any(k[0] != "0" for k in mine)
    tk = tree_key if split else "0"
    if split and not any(k[0] == tk for k in mine):
        return "no-row", "we ship no row for hero tree %s" % tk, None
    key = (tk, bucket)
    fb = bucket == "mythic" and key not in mine and (tk, "raid") in mine
    if fb:
        key = (tk, "raid")
    want = mine.get(key)
    if want == guide:
        return ("same-fb" if fb else "same"), "", key
    if want is not None and tiers(want) == tiers(guide):
        return "tie-order", "same tiers; we write it %s" % want, key
    hits = [k for k, v in mine.items() if v == guide]
    if not hits:
        return "DIFFERS", "", key if want is not None else None
    same_tree = sorted(k[1] for k in hits if k[0] == tk)
    if same_tree:
        return "bucket?", "our %s row for this tree says it" % "/".join(same_tree), key
    same_bucket = sorted(k[0] for k in hits if k[1] == bucket)
    if same_bucket:
        return "tree?", "hero tree %s says it" % "/".join(same_bucket), key
    return "else?", "only %s says it" % "/".join(
        sorted("%s|%s" % k for k in hits)), key


# --- offline self-check ---------------------------------------------------
FLAT = {("0", "raid"): "a > b > c > d", ("0", "mythic"): "d > c > b > a"}
SPLIT = {("18", "raid"): "a > b > c > d", ("18", "mythic"): "b > a > c > d",
         ("19", "raid"): "c > a > b > d"}


def verify():
    """`--verify`. Every verdict below is a branch that live data may not
    reach today (`same-fb` and `no-row` reach it zero times as of
    2026-08-28), and an unexercised branch is a claim nobody has checked.
    The last two checks are the A/B for assertion 9 itself, kept runnable
    instead of living only in a commit message."""
    bad = []

    def check(name, ok, note=""):
        bad.append(name) if not ok else None
        print("  %-52s %s  %s" % (name, "PASS" if ok else "FAIL", note))

    print()
    print("negative controls")
    for label, slug, want in (
            ("Voidweaver Stat Priority", "voidweaver", "raid"),
            ("Preservation Mythic+ Stat Priority", None, "mythic"),
            ("Dark Ranger Stat Priority / AoE:", "dark-ranger", "mythic"),
            ("Survivability Stat Priority", None, "raid"),
            ("DPS Stat Priority", None, None),
            ("Shado-Pan Offensive Priority", "shado-pan", None)):
        got = bucket_of(label, slug)[0]
        check("heading %-38.38s -> %s" % (label, want), got == want, "got %r" % got)
    check("an unknown heading is NOT folded into raid",
          bucket_of("Delve Stat Priority", "voidweaver")[0] is None)

    for name, mine, tk, bucket, guide, want in (
            ("flat row answers every hero tree", FLAT, "18", "raid", "a > b > c > d", "same"),
            ("mythic box hits the mythic row", FLAT, "18", "mythic", "d > c > b > a", "same"),
            ("no mythic row -> runtime raid fallback", {("0", "raid"): "a > b > c > d"},
             "0", "mythic", "a > b > c > d", "same-fb"),
            ("tie written in another sequence", {("0", "raid"): "a=b > c > d"},
             "0", "raid", "b=a > c > d", "tie-order"),
            ("our other bucket says it", SPLIT, "18", "raid", "b > a > c > d", "bucket?"),
            ("another hero tree says it", SPLIT, "19", "raid", "a > b > c > d", "tree?"),
            # First written as guide "b > a > c > d", which is 18|mythic --
            # same bucket as the box asks about, so the code correctly said
            # `tree?` and the expectation was the thing that was wrong. An
            # `else?` needs the only hit to differ in BOTH tree and bucket.
            ("only a different tree AND bucket says it", SPLIT, "19", "mythic",
             "a > b > c > d", "else?"),
            ("nothing we ship says it", SPLIT, "18", "raid", "d > c > b > a", "DIFFERS"),
            ("spec ships trees but not this one", SPLIT, "20", "raid", "a > b > c > d", "no-row"),
            ("spec ships nothing", {}, "0", "raid", "a > b > c > d", "NEW"),
            ("axis we do not model", FLAT, "0", None, "a > b > c > d", "no-model")):
        got = verdict_for(mine, tk, bucket, guide)[0]
        check("verdict: %-45.45s -> %s" % (name, want), got == want, "got %r" % got)

    # A/B for assertion 9, both arms. `old` is the exact pre-2026-08-28 line.
    corrupt = dict(FLAT)
    corrupt[("0", "mythic")] = "a > b > c > d"          # a real, shippable edit
    old = lambda m: m.get(("0", "raid")) == "d > c > b > a"
    check("OLD comparison cannot see a corrupted mythic row",
          old(FLAT) == old(corrupt) is False, "both False, in both arms")
    check("NEW comparison can (this is the load-bearing one)",
          verdict_for(FLAT, "0", "mythic", "d > c > b > a")[0] == "same"
          and verdict_for(corrupt, "0", "mythic", "d > c > b > a")[0] == "DIFFERS")
    print()
    print("%d checks, %d failures" % (7 + 11 + 2, len(bad)))
    return len(bad)
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cached", action="store_true",
                    help="reuse tools/.scan-cache instead of refetching")
    ap.add_argument("--only", type=int, action="append",
                    help="limit to these specIDs")
    ap.add_argument("--json", metavar="PATH", help="also write the raw result")
    ap.add_argument("--verify", action="store_true",
                    help="run the offline branch checks and exit")
    args = ap.parse_args()

    if args.verify:
        return 1 if verify() else 0

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
          ("spec", "class", "spec", "modified", "shape", "guide order  ->  VERDICT    box heading   tree(subTree/bucket)"))
    print("=" * 100)
    tally, touched, unverified = {}, set(), []
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
            bucket, complaint = bucket_of(o.get("label"), o.get("tree"))
            verdict, detail, key = verdict_for(mine, tree_key, bucket, guide)
            if key:
                touched.add((s["id"],) + key)
            tally[verdict] = tally.get(verdict, 0) + 1
            print("%s %-34s %-9s %-26.26s %s(%s/%s)" %
                  (head if first else " " * 57, guide, verdict,
                   o.get("label") or "-", o["tree"] or "no-tree", tree_key,
                   bucket or "?"))
            first = False
            if complaint or detail:
                print("%s   -> %s" % (" " * 57, complaint or detail))
            if bucket is None:
                # An exemption that is not counted is an exemption nobody
                # ever re-reads. Both kinds land in UNVERIFIED below.
                unverified.append("%-5s %-13s %s: %s" % (
                    s["id"], s["spec"],
                    "unrecognised heading" if complaint
                    else "guide box on an axis we do not model",
                    o.get("label")))
        if not r["orders"]:
            print("%s %s" % (head, "(no usable stat list; %d lists skipped)" % r["skipped"]))
        for n in r["notes"]:
            print("%s  ! %s" % (" " * 57, n))
            if n.startswith("NOT the 4"):
                unverified.append("%-5s %-13s guide box dropped by assertion 4: %s"
                                  % (s["id"], s["spec"], n.split(": ", 1)[-1]))
        if r["foreign"]:
            print("%s  ~ ignored foreign hero symbols: %s"
                  % (" " * 57, ", ".join(r["foreign"])))
    print()
    print("--- dateModified clusters (same minute = one Wowhead republish, not N authors) ---")
    for d in sorted(dates, key=lambda d: (d or "")):
        print("   %-30s %2d specs  %s" % (d, len(dates[d]), sorted(dates[d])))
    for r in results:
        sid = r["spec"]["id"]
        for k in sorted(have.get(sid, {})):
            if (sid,) + k not in touched:
                unverified.append(
                    "%-5s %-13s %s|%-6s never compared -- no guide box maps to it"
                    % (sid, r["spec"]["spec"], k[0], k[1]))
    print()
    print("--- UNVERIFIED: nothing above this line has an opinion about these ---")
    for u in unverified:
        print("   " + u)
    print("   (%d)   -- before assertion 9 this list did not exist, and the"
          " shipped mythic rows were all in it" % len(unverified))
    print()
    print("scanned %d, errors %d;  %s;  unverified %d"
          % (len(results), len(errors),
             "  ".join("%s=%d" % kv for kv in sorted(tally.items())),
             len(unverified)))
    if args.json:
        with io.open(args.json, "w", encoding="utf-8") as f:
            json.dump([{k: v for k, v in r.items()} for r in results], f,
                      indent=1, ensure_ascii=False, default=str)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
