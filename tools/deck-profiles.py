#!/usr/bin/env python3
"""Erzeugt die Stream-Deck-Profile, die das Gnotchi-Plugin mitliefert (Michael 17.11.: „ein Profil mit allen Funktionen“).

Format wie Stream Decks eigener Export (gemessen am Profil, das Elgatos Codex-Plugin mitliefert): ZIP mit `package.json` und
`Profiles/<UUID>.sdProfile/{manifest.json, Profiles/<Seite>/manifest.json}`. Feste UUIDs, damit jeder Lauf dieselbe Datei ergibt.

Aufruf:  python3 -I tools/deck-profiles.py GnotchiDeck/dev.mwlr.gnotchi.deck.sdPlugin/profiles
"""
import json
import sys
import uuid
import zipfile
from pathlib import Path

PLUGIN = {"Name": "Gnotchi", "UUID": "dev.mwlr.gnotchi.deck", "Version": "0.36.0.0"}
NS = uuid.UUID("6f1d3c52-6a9e-4b4e-9d8c-1f4a2b7c9e01")   # Namensraum für feste UUIDs


def fixed(name):
    return str(uuid.uuid5(NS, name))


def key_state():
    return [{"FontFamily": "", "FontSize": 10, "FontStyle": "", "FontUnderline": False, "OutlineThickness": 2,
             "ShowTitle": True, "TitleAlignment": "top", "TitleColor": "#ffffff"}]


def action(kind, name, settings, slot):
    uuids = {"volume": "dev.mwlr.gnotchi.deck.volume", "play": "dev.mwlr.gnotchi.deck.play",
             "output": "dev.mwlr.gnotchi.deck.output"}
    return {"ActionID": fixed(f"{slot}-{kind}-{json.dumps(settings, sort_keys=True)}"), "LinkedTitle": True, "Name": name,
            "Plugin": PLUGIN, "Resources": None, "Settings": settings, "State": 0, "States": key_state(),
            "UUID": uuids[kind]}


def vol(app, key=None, slot=""):
    s = {"app": app}
    if key:
        s["key"] = key
    return action("volume", "App-Lautstärke", s, slot)


def play(app, what, slot=""):
    return action("play", "Wiedergabe", {"app": app, "what": what}, slot)


def out(app, slot=""):
    return action("output", "App-Lautsprecher", {"app": app}, slot)


CUR = "current"
SPOTIFY = "com.spotify.client"
HELIUM = "net.imput.helium"

KEYS_PLUS = {
    "0,0": play(CUR, "previous", "p00"), "1,0": play(CUR, "toggle", "p10"), "2,0": play(CUR, "next", "p20"),
    "3,0": vol(CUR, "mute", "p30"),
    "0,1": vol(CUR, "down", "p01"), "1,1": vol(CUR, "up", "p11"), "2,1": out(CUR, "p21"), "3,1": play(SPOTIFY, "toggle", "p31"),
}
DIALS_PLUS = {
    "0,0": vol(CUR, slot="d0"), "1,0": vol(SPOTIFY, slot="d1"), "2,0": vol(HELIUM, slot="d2"), "3,0": out(CUR, "d3"),
}
KEYS_NEO = {
    "0,0": play(CUR, "previous", "n00"), "1,0": play(CUR, "toggle", "n10"), "2,0": play(CUR, "next", "n20"),
    "3,0": out(CUR, "n30"),
    "0,1": vol(CUR, "down", "n01"), "1,1": vol(CUR, "mute", "n11"), "2,1": vol(CUR, "up", "n21"),
    "3,1": play(SPOTIFY, "toggle", "n31"),
}

# Gerätemodelle gemessen 17.11. in Michaels ProfilesV3: Stream Deck + = 20GBD9901, Stream Deck Neo = 20GBJ9901.
PROFILES = [
    {"file": "gnotchi-plus", "model": "20GBD9901", "second": "Encoder", "keys": KEYS_PLUS, "second_actions": DIALS_PLUS},
    {"file": "gnotchi-neo", "model": "20GBJ9901", "second": "Neo", "keys": KEYS_NEO, "second_actions": None},
]


def build(p, target: Path):
    prof = fixed(p["file"] + "-profile").upper()
    page = fixed(p["file"] + "-page")
    default = fixed(p["file"] + "-default")
    manifest = {"Device": {"Model": p["model"], "UUID": fixed(p["file"] + "-device")}, "Name": "Gnotchi",
                "Pages": {"Current": "00000000-0000-0000-0000-000000000000", "Default": default, "Pages": [page]},
                "Version": "3.0"}
    page_manifest = {"Controllers": [{"Actions": p["keys"], "Type": "Keypad"},
                                     {"Actions": p["second_actions"], "Type": p["second"]}],
                     "Icon": "", "Name": "Gnotchi"}
    default_manifest = {"Controllers": [{"Actions": None, "Type": "Keypad"}, {"Actions": None, "Type": p["second"]}],
                        "Icon": "", "Name": ""}
    package = {"AppVersion": "7.6.1.23033", "DeviceModel": p["model"], "DeviceSettings": None, "FormatVersion": 1,
               "OSType": "macOS", "OSVersion": "27.2", "RequiredPlugins": [PLUGIN["UUID"]]}
    root = f"Profiles/{prof}.sdProfile"
    path = target / f"{p['file']}.streamDeckProfile"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as z:
        def add(name, obj):
            info = zipfile.ZipInfo(name, date_time=(2026, 11, 17, 0, 0, 0))
            z.writestr(info, json.dumps(obj, ensure_ascii=False, indent=2))

        def folder(name):
            z.writestr(zipfile.ZipInfo(name + "/", date_time=(2026, 11, 17, 0, 0, 0)), "")

        add("package.json", package)
        folder("Profiles")
        folder(root)
        add(f"{root}/manifest.json", manifest)
        folder(f"{root}/Profiles")
        folder(f"{root}/Profiles/{page.upper()}")
        add(f"{root}/Profiles/{page.upper()}/manifest.json", page_manifest)
        folder(f"{root}/Profiles/{default.upper()}")
        add(f"{root}/Profiles/{default.upper()}/manifest.json", default_manifest)
    return path


if __name__ == "__main__":
    target = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    target.mkdir(parents=True, exist_ok=True)
    for p in PROFILES:
        print("geschrieben:", build(p, target))
