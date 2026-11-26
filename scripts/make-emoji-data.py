#!/usr/bin/env python3
"""Builds Resources/Emoji/emoji.json from Unicode's data, for Search Emoji & Symbols.

Usage: python3 -I scripts/make-emoji-data.py <folder> Resources/Emoji/emoji.json

<folder> holds, downloaded by hand:
  emoji-test.txt          https://unicode.org/Public/emoji/latest/emoji-test.txt
  annotations-{en,ja}.json  cldr-json: cldr-annotations-full/annotations/<lang>/annotations.json
  derived-{en,ja}.json      cldr-json: cldr-annotations-derived-full/annotationsDerived/<lang>/annotations.json

The output lists each emoji once, in Unicode's order, with its English and Japanese names and
keywords; skin-tone variants sit under the emoji they vary. Symbols CLDR names that aren't emoji
(→ ⌘ ™ °) come last, under Symbols.
"""

import json
import os
import sys

# Raycast's categories: Unicode's first two groups are one.
GROUPS = {
    "Smileys & Emotion": "Smileys & People",
    "People & Body": "Smileys & People",
    "Animals & Nature": "Animals & Nature",
    "Food & Drink": "Food & Drink",
    "Travel & Places": "Travel & Places",
    "Activities": "Activities",
    "Objects": "Objects",
    "Symbols": "Symbols",
    "Flags": "Flags",
}
ORDER = list(dict.fromkeys(GROUPS.values()))
TONES = ["light", "medium-light", "medium", "medium-dark", "dark"]
# The variation selector that asks for the emoji look; CLDR leaves it out of its keys.
VARIATION = "\ufe0f"
# The newest Emoji version this Mac's Apple Color Emoji drew (16.0's showed as boxes on macOS 26
# here); raise it once they draw.
MAX_VERSION = 15.1
MAC_KEYS = [
    ("⌘", "command key", "コマンドキー"), ("⌥", "option key", "オプションキー"),
    ("⌃", "control key", "コントロールキー"), ("⇧", "shift key", "シフトキー"),
    ("↩", "return key", "リターンキー"), ("⌫", "delete key", "デリートキー"),
    ("⌦", "forward delete key", "前方削除キー"), ("⎋", "escape key", "エスケープキー"),
    ("⇥", "tab key", "タブキー"), ("⏏", "eject key", "イジェクトキー"),
]


def annotations(folder, lang):
    """Character → (name, keywords), the derived set (flags, tones, keycaps) under the base."""
    merged = {}
    for file, key in (("derived-%s.json", "annotationsDerived"), ("annotations-%s.json", "annotations")):
        data = json.load(open(os.path.join(folder, file % lang), encoding="utf-8"))
        for char, entry in data[key]["annotations"].items():
            name = (entry.get("tts") or [""])[0]
            merged[char] = (name, entry.get("default", []))
    return merged


def lookup(table, char):
    # CLDR keys leave out the variation selector the fully qualified emoji has.
    return table.get(char) or table.get(char.replace(VARIATION, "")) or ("", [])


def main(folder, out):
    en, ja = annotations(folder, "en"), annotations(folder, "ja")
    emoji, by_name, group, every = [], {}, None, set()
    for line in open(os.path.join(folder, "emoji-test.txt"), encoding="utf-8"):
        if line.startswith("# group:"):
            group = GROUPS.get(line.split(":", 1)[1].strip())
            continue
        if line.startswith("#") or "; " not in line:
            continue
        char = line.split("#", 1)[1].split()[0]
        # Every emoji Unicode lists, left out or not (skin swatches and hair parts are its
        # "component"s), so none comes back below as a symbol.
        every.add(char.replace(VARIATION, ""))
        if group is None or "; fully-qualified" not in line:
            continue
        version = float(line.split("#", 1)[1].split()[1].lstrip("E"))
        if version > MAX_VERSION:
            continue  # newer than macOS's emoji font draws; it would show as a box
        name = line.split("#", 1)[1].split(" E", 1)[1].split(" ", 1)[1].strip()
        # "thumbs up: light skin tone" and "woman: medium skin tone, red hair": one tone
        # throughout, kept with "thumbs up" and "woman: red hair".
        head, _, rest = name.partition(": ")
        parts = rest.split(", ") if rest else []
        tones = [p.removesuffix(" skin tone") for p in parts if p.endswith(" skin tone")]
        if len(tones) == 1 and tones[0] in TONES:
            others = [p for p in parts if not p.endswith(" skin tone")]
            base = head + (": " + ", ".join(others) if others else "")
            if base in by_name:
                by_name[base].setdefault("tones", [None] * 5)[TONES.index(tones[0])] = char
            continue
        if tones:
            continue  # mixed tones; the base stays
        entry = {"c": char, "g": ORDER.index(group), "n": lookup(en, char)[0] or name,
                 "j": lookup(ja, char)[0], "k": lookup(en, char)[1], "kj": lookup(ja, char)[1]}
        by_name[name] = entry
        emoji.append(entry)
    seen = every | {e["c"].replace(VARIATION, "") for e in emoji}
    symbols = ORDER.index("Symbols")
    for char, (name, keywords) in en.items():
        # Single characters CLDR names that aren't emoji: arrows, math, currency, ⌘.
        if len(char) == 1 and char not in seen and name and not char.isalnum():
            emoji.append({"c": char, "g": symbols, "n": name, "j": lookup(ja, char)[0],
                          "k": keywords, "kj": lookup(ja, char)[1]})
    # Mac's key symbols, which CLDR doesn't name.
    present = {e["c"] for e in emoji}
    for char, name, japanese in MAC_KEYS:
        keys = {"k": [name, "key", "mac", "keyboard"], "kj": [japanese, "キー", "キーボード", "Mac"]}
        if char in present:
            # Named by CLDR as an arrow (⇧, ⇥): the key's name joins its keywords.
            entry = next(e for e in emoji if e["c"] == char)
            for key, words in keys.items():
                entry[key] = entry.get(key, []) + [w for w in words if w not in entry.get(key, [])]
        else:
            emoji.append({"c": char, "g": symbols, "n": name, "j": japanese, **keys})
    for entry in emoji:
        tones = entry.get("tones")
        if tones and None in tones:
            del entry["tones"]
        for key in ("j", "k", "kj"):
            if not entry[key]:
                del entry[key]
    # Symbols CLDR adds after Unicode's emoji, stable within the group.
    emoji.sort(key=lambda e: e["g"])
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"groups": ORDER, "emoji": emoji}, f, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(emoji)} entries, {sum(1 for e in emoji if 'tones' in e)} with skin tones")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
