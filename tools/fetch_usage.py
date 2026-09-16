#!/usr/bin/env python3
"""Generates Resources/usage.json and Resources/moves.json.

Move usage comes from championsbattledata.com (Singles), move numbers from
PokeAPI. Both are cached under tools/.cache, so a second run costs nothing.

The app ships this as a snapshot and refreshes each Pokemon from the same API
while you play, so this only has to be re-run when cutting a release.
"""
import json, os, time, urllib.request, collections, datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tools", ".cache")
API = "https://championsbattledata.com"
POKEAPI = "https://pokeapi.co/api/v2"
UA = {"User-Agent": "pokemon-champions-analyzer"}

# Showdown ids the sprite keys spell differently. Everything else matches once
# punctuation is stripped.
ALIASES = {
    "basculegionf": "basculegion-female",
    "indeedeef": "indeedee-female",
    "meowsticf": "meowstic-female",
    "gourgeistsuper": "gourgeist-jumbo",
    "mausholdfour": "maushold",
}


def get(url, cache_dir, name, pause=0.25):
    d = os.path.join(CACHE, cache_dir)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, name + ".json")
    if os.path.exists(path):
        data = json.load(open(path))
        return None if data == {} else data
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
            data = json.loads(r.read().decode())
    except Exception:
        data = {}
    json.dump(data, open(path, "w"))
    time.sleep(pause)
    return None if data == {} else data


def norm(s):
    return "".join(c for c in str(s).lower() if c.isalnum())


def main():
    dex = json.load(open(os.path.join(ROOT, "Resources", "pokedex.json")))
    by_norm = {}
    for e in dex:
        if not e.get("shiny"):
            by_norm.setdefault(norm(e["key"]), e["key"])

    index = get(API + "/api", "usage", "_index")
    listing = next(v for v in index.values()
                   if isinstance(v, list) and v and isinstance(v[0], dict) and "showdownId" in v[0])
    print(f"{len(listing)} Pokemon in the index")

    pokemon, missing, move_names = {}, [], collections.Counter()
    for entry in listing:
        sid = entry["showdownId"]
        key = ALIASES.get(sid) or by_norm.get(norm(sid))
        if not key:
            missing.append(sid)
            continue
        data = get(f"{API}/api/battle/Singles/{sid}", "usage", sid)
        if not data:
            continue
        rows = [r for r in data.get("rows", []) if r.get("category") == "move"]
        rows.sort(key=lambda r: r.get("rank") or 99)
        moves = [{"name": r["name"], "pct": r.get("percentage_value")} for r in rows if r.get("name")]
        if not moves:
            continue
        pokemon[key] = {"id": sid, "moves": moves}
        for m in moves:
            move_names[m["name"]] += 1

    # Only moves that can actually be estimated: a fixed base power and a
    # physical or special class. Status moves and the likes of Seismic Toss or
    # Grass Knot would need rules of their own, so they are left out entirely
    # rather than shown with a wrong number.
    moves_out, skipped = {}, []
    for name in sorted(move_names):
        slug = name.lower().replace("'", "").replace(".", "").replace(",", "").replace(" ", "-")
        d = get(f"{POKEAPI}/move/{slug}", "moves", slug, pause=0.15) \
            or get(f"{POKEAPI}/move/{slug.replace('-', '')}", "moves", slug.replace("-", ""), pause=0.15)
        if not d:
            skipped.append((name, "unknown"))
            continue
        if d["damage_class"]["name"] == "status" or not d["power"]:
            skipped.append((name, d["damage_class"]["name"] if not d["power"] else "status"))
            continue
        zh = next((n["name"] for n in d["names"] if n["language"]["name"] == "zh-hant"), "")
        entry = {"power": d["power"], "type": d["type"]["name"],
                 "category": d["damage_class"]["name"], "zh": zh,
                 # Who it hits: "selected-pokemon" for most, "all-opponents" for
                 # spread moves, "all-other-pokemon" for the ones that catch
                 # your own partner as well. Doubles damage depends on it.
                 "target": d["target"]["name"]}
        # Only when it matters: priority 0 is the overwhelming majority, and
        # writing it out would be most of the file saying nothing.
        if d["priority"]:
            entry["priority"] = d["priority"]
        moves_out[name] = entry

    usage = {
        "generated": datetime.date.today().isoformat(),
        "format": "Singles",
        "source": "championsbattledata.com",
        "pokemon": pokemon,
    }
    res = os.path.join(ROOT, "Resources")
    with open(os.path.join(res, "usage.json"), "w") as f:
        json.dump(usage, f, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(res, "moves.json"), "w") as f:
        json.dump(moves_out, f, ensure_ascii=False, separators=(",", ":"))

    print(f"usage.json: {len(pokemon)} Pokemon"
          f" ({os.path.getsize(os.path.join(res, 'usage.json')) // 1024} KB)")
    print(f"moves.json: {len(moves_out)} damaging moves"
          f" ({os.path.getsize(os.path.join(res, 'moves.json')) // 1024} KB)")
    print(f"skipped {len(skipped)} moves (status or variable power)")
    if missing:
        print("no sprite key for:", missing)


if __name__ == "__main__":
    main()
