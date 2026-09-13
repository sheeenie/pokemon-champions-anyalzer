#!/usr/bin/env python3
"""Build-time generator for the Pokemon Champions reference data.

Produces, into Resources/:
  pokedex.json   species key -> English/Chinese names, types, base stats, abilities
  icons/*.png    Champions menu sprite per species/form

The icons come from Bulbagarden's "Champions menu sprites" category, which is
the art Champions actually renders on battle name plates. This matters: HOME and
official-artwork use a different pose entirely, and matching against them ranks
the correct species only 1st-4th of 30. With the Champions art it ranks 1st.

Stats and names come from PokeAPI. Run once; results are cached under .cache/
so re-runs are cheap.
"""

import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(ROOT, "Resources")
ICONS = os.path.join(RESOURCES, "icons")
TYPE_ICONS = os.path.join(RESOURCES, "types")
CACHE = os.path.join(ROOT, "tools", ".cache")

TYPES = ["Normal", "Fire", "Water", "Electric", "Grass", "Ice", "Fighting",
         "Poison", "Ground", "Flying", "Psychic", "Bug", "Rock", "Ghost",
         "Dragon", "Dark", "Steel", "Fairy"]

BULBA_API = "https://archives.bulbagarden.net/w/api.php"
BULBA_FILE = "https://archives.bulbagarden.net/wiki/Special:FilePath/"
POKEAPI = "https://pokeapi.co/api/v2"
UA = {"User-Agent": "iPhoneMirror-pokedex-builder/1.0"}

# Form suffixes whose PokeAPI slug differs from a plain lowercase/hyphenate.
FORM_OVERRIDES = {
    "incarnate": "",           # PokeAPI treats Incarnate as the base form
    "male": "",
    "ordinary": "",
    "aria": "",
    "shield": "",
    "disguised": "",
    "full-belly": "",
    "amped": "",
    "green-plumage": "",
    "curly": "",
    "family-of-three": "",
    "zero": "",
    "teal-mask": "",
    "combat-breed": "",
}


def get(url, binary=False, pause=0.25, attempts=4):
    """Fetch with a small on-disk cache and polite rate limiting.

    Retries with backoff: under sustained requests PokeAPI returns transient
    503s and occasional spurious 404s, which would otherwise silently drop
    species from the library.
    """
    key = re.sub(r"[^A-Za-z0-9]+", "_", url)[-180:]
    path = os.path.join(CACHE, key)
    if os.path.exists(path):
        with open(path, "rb") as f:
            data = f.read()
        return data if binary else data.decode("utf-8")

    last = None
    for attempt in range(attempts):
        time.sleep(pause * (1 + attempt * 3))
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=45) as r:
                data = r.read()
            break
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
            last = exc
            code = getattr(exc, "code", None)
            # A real 404 on the final attempt is meaningful; earlier ones are
            # usually rate limiting wearing a different hat.
            if code == 404 and attempt == attempts - 1:
                raise
    else:
        raise last

    os.makedirs(CACHE, exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    return data if binary else data.decode("utf-8")


def champions_files(category):
    """Every Menu_CP_*.png in one category."""
    names, cont = [], None
    while True:
        params = {
            "action": "query", "list": "categorymembers",
            "cmtitle": f"Category:{category}",
            "cmlimit": "500", "cmtype": "file", "format": "json",
        }
        if cont:
            params["cmcontinue"] = cont
        data = json.loads(get(BULBA_API + "?" + urllib.parse.urlencode(params)))
        names += [m["title"] for m in data["query"]["categorymembers"]]
        cont = data.get("continue", {}).get("cmcontinue")
        if not cont:
            return sorted(names)


def parse_title(title):
    """Split a sprite filename into dex number, form, file name and shininess.

    'File:Menu CP 0006-Mega X.png'       -> (6, 'Mega X', ..., False)
    'File:Menu CP 0006-Mega X shiny.png' -> (6, 'Mega X', ..., True)

    Shinies are a separate reference icon for the same species: identification
    is colour-based, and a shiny is a recolour, so it cannot match the normal
    artwork. Stats are unaffected.
    """
    stem = title[len("File:"):-len(".png")]
    filename = stem.replace(" ", "_") + ".png"
    shiny = stem.endswith(" shiny")
    if shiny:
        stem = stem[: -len(" shiny")]
    m = re.match(r"Menu CP (\d+)(?:-(.+))?$", stem)
    if not m:
        return None
    return int(m.group(1)), (m.group(2) or ""), filename, shiny


def species_info(dex):
    """Names plus the concrete pokemon slugs this species resolves to.

    The default variety is not always the species name: Meowstic is
    'meowstic-male', Aegislash is 'aegislash-shield'. Reading `varieties`
    avoids guessing and eliminates a round of 404s.
    """
    data = json.loads(get(f"{POKEAPI}/pokemon-species/{dex}"))
    names = {n["language"]["name"]: n["name"] for n in data["names"]}
    varieties = [v["pokemon"]["name"] for v in data["varieties"]]
    default = next(
        (v["pokemon"]["name"] for v in data["varieties"] if v["is_default"]),
        varieties[0] if varieties else data["name"],
    )
    # PokeAPI spells the language code lowercase.
    return (default, varieties, data["name"],
            names.get("en", data["name"]), names.get("zh-hant", ""))


def variant_slug(species_slug, default_slug, varieties, form):
    """Pick the variety matching this form, falling back to the default."""
    if not form:
        return default_slug
    slug = re.sub(r"[^a-z0-9]+", "-", form.lower()).strip("-")
    slug = FORM_OVERRIDES.get(slug, slug)
    if not slug:
        return default_slug

    exact = f"{species_slug}-{slug}"
    if exact in varieties:
        return exact
    # Champions and PokeAPI sometimes word a form differently (e.g. "Mega X"
    # vs "mega-x", "Teal Mask" vs "teal"); accept a variety that contains all
    # the form's words.
    parts = slug.split("-")
    for v in varieties:
        if all(p in v for p in parts):
            return v
    return exact  # let the caller's 404 fallback handle it


def pokemon_stats(slug):
    data = json.loads(get(f"{POKEAPI}/pokemon/{slug}"))
    stats = {s["stat"]["name"]: s["base_stat"] for s in data["stats"]}
    return {
        "types": [t["type"]["name"] for t in data["types"]],
        "abilities": [{"name": a["ability"]["name"], "hidden": a["is_hidden"]}
                      for a in sorted(data["abilities"], key=lambda a: a["slot"])],
        "baseStats": {
            "hp": stats["hp"], "atk": stats["attack"], "def": stats["defense"],
            "spa": stats["special-attack"], "spd": stats["special-defense"],
            "spe": stats["speed"],
        },
    }


# Traditional Chinese for form labels. PokeAPI's own localized form names are
# unusable as a source: some are the full name ("超級噴火龍Ｘ"), some only the form
# ("阿羅拉的樣子"), and Champions-exclusive forms such as Mega Z have none at all.
# Whole phrases are tried first, then individual words; anything unlisted stays
# in English rather than being guessed.
FORM_ZH = {
    "Mega": "超級", "Alola": "阿羅拉", "Galar": "伽勒爾", "Hisui": "洗翠",
    "Paldea": "帕底亞", "Combat": "鬥戰種", "Blaze": "火熾種", "Aqua": "水瀾種",
    "Therian": "靈獸形態", "Incarnate": "化身形態", "Origin": "起源形態",
    "Female": "雌性", "Male": "雄性",
    "Heat": "加熱", "Wash": "清洗", "Frost": "結冰", "Fan": "旋轉", "Mow": "切割",
    "Sunny": "太陽的樣子", "Rainy": "雨水的樣子", "Snowy": "雪雲的樣子",
    "Rapid Strike": "連擊流", "Single Strike": "一擊流",
    "Family of Three": "三口之家", "Family of Four": "四口之家",
    "Midday": "白晝的樣子", "Midnight": "黑夜的樣子", "Dusk": "黃昏的樣子",
}


def form_zh(form):
    if form in FORM_ZH:
        return FORM_ZH[form]
    return " ".join(FORM_ZH.get(word, word) for word in form.split(" "))


def ability_info(name):
    """English and Traditional Chinese name and description for one ability.

    A failed lookup degrades to the slug rather than raising, so a missing
    description can never drop a species from the library.
    """
    try:
        data = json.loads(get(f"{POKEAPI}/ability/{name}"))
    except Exception:  # noqa: BLE001
        return {"en": name.replace("-", " ").title(), "zh": "", "descEn": "", "descZh": ""}

    names = {n["language"]["name"]: n["name"] for n in data["names"]}

    def latest(lang):
        texts = [e["flavor_text"] for e in data["flavor_text_entries"]
                 if e["language"]["name"] == lang]
        return texts[-1] if texts else ""

    return {
        "en": names.get("en", name),
        "zh": names.get("zh-hant", ""),
        "descEn": re.sub(r"\s+", " ", latest("en")).strip(),
        # Chinese flavour text is hard-wrapped with spaces and newlines that
        # are line breaks, not word separators.
        "descZh": re.sub(r"\s+", "", latest("zh-hant")),
    }


def fetch_type_icons():
    """Scarlet/Violet type glyphs.

    These ship as a white symbol on the type's own coloured background. The app
    keys the background out at load and redraws the glyph over the palette in
    TypeChart, so one colour scheme governs the whole panel.
    """
    os.makedirs(TYPE_ICONS, exist_ok=True)
    for name in TYPES:
        data = get(BULBA_FILE + f"{name}_icon_SV.png", binary=True)
        with open(os.path.join(TYPE_ICONS, name.lower() + ".png"), "wb") as f:
            f.write(data)
    print(f"wrote {len(TYPES)} type icons")


def main():
    os.makedirs(ICONS, exist_ok=True)
    fetch_type_icons()
    titles = (champions_files("Champions_menu_sprites")
              + champions_files("Champions_Shiny_menu_sprites"))
    print(f"Champions menu sprites (incl. shiny): {len(titles)}")

    entries, failures = [], []
    for i, title in enumerate(titles, 1):
        parsed = parse_title(title)
        if not parsed:
            failures.append((title, "unparseable filename"))
            continue
        dex, form, filename, shiny = parsed

        try:
            base_slug, varieties, species_slug, english, zh = species_info(dex)
            slug = variant_slug(species_slug, base_slug, varieties, form)
            try:
                info = pokemon_stats(slug)
            except urllib.error.HTTPError as e:
                if e.code != 404:
                    raise
                # Form not in PokeAPI under that slug; fall back to base stats
                # rather than dropping the icon entirely.
                info = pokemon_stats(base_slug)
                failures.append((title, f"no PokeAPI form '{slug}', used base"))

            # Key off the sprite FILE, not the resolved PokeAPI slug: distinct
            # icons (Vivillon patterns, Tornadus Incarnate vs base) can resolve
            # to the same slug, and sharing a key would let one overwrite the
            # other's icon and lose it from the library.
            species_name = species_slug
            file_form = re.sub(r"[^a-z0-9]+", "-", form.lower()).strip("-")
            key = f"{species_name}-{file_form}" if file_form else species_name
            if shiny:
                key += "-shiny"

            icon = get(BULBA_FILE + urllib.parse.quote(filename), binary=True)
            with open(os.path.join(ICONS, key + ".png"), "wb") as f:
                f.write(icon)

            stats = info["baseStats"]
            entries.append({
                "key": key,
                "dex": dex,
                "name": english + (f" ({form})" if form else ""),
                "shiny": shiny,
                "form": form,
                "formZh": form_zh(form) if form else "",
                "zhHant": zh,
                "nameZh": (zh or english) + (f"（{form_zh(form)}）" if form else ""),
                "abilities": [dict(ability_info(a["name"]), hidden=a["hidden"])
                              for a in info["abilities"]],
                "types": info["types"],
                "baseStats": stats,
                "bst": sum(stats.values()),
            })
        except Exception as exc:  # noqa: BLE001 - report and continue
            failures.append((title, str(exc)))

        if i % 25 == 0:
            print(f"  {i}/{len(titles)}  ok={len(entries)} failed={len(failures)}")

    entries.sort(key=lambda e: (e["dex"], e["form"]))
    with open(os.path.join(RESOURCES, "pokedex.json"), "w") as f:
        json.dump(entries, f, indent=1, ensure_ascii=False)

    print(f"\nwrote {len(entries)} entries and icons to {RESOURCES}")
    if failures:
        print(f"\n{len(failures)} issues:")
        for t, why in failures[:40]:
            print(f"  {t}: {why}")
    return 0 if entries else 1


if __name__ == "__main__":
    sys.exit(main())
