#!/usr/bin/env python3
"""A beépített adatfájlok (alapanyagok, cserék, receptek) önellenőrzése."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "Sources" / "FincsiKit" / "Resources"
FORBIDDEN = {
    "glutenFree": {"gluten"},
    "vegan": {"meat", "fish", "dairy", "egg", "honey", "animal"},
    "vegetarian": {"meat", "fish", "animal"},
    "lactoseFree": {"lactose"},
    "nutFree": {"nut"},
}
UNITS = {"g", "dkg", "kg", "ml", "dl", "l", "db", "ek", "tk", "csipet", "gerezd", "szelet", "csokor",
         "marék", "doboz", "szál", "fej", "ízlés szerint", ""}

errors = []


def err(message):
    errors.append(message)


def load(name):
    with open(ROOT / name, encoding="utf8") as handle:
        return json.load(handle)


ingredients = load("ingredients.json")
categories = {c["id"] for c in ingredients["categories"]}
by_id = {}
for item in ingredients["ingredients"]:
    if item["id"] in by_id:
        err(f"duplikált alapanyag: {item['id']}")
    by_id[item["id"]] = item
    if not item["id"].isascii():
        err(f"nem ASCII azonosító: {item['id']}")
    if item["category"] not in categories:
        err(f"ismeretlen kategória: {item['id']}")
    if item.get("family") and item["family"] not in by_id and item["family"] not in {i["id"] for i in ingredients["ingredients"]}:
        err(f"ismeretlen család: {item['id']} -> {item['family']}")
    for tag in item["tags"]:
        if tag not in {"gluten", "meat", "fish", "dairy", "lactose", "egg", "honey", "nut", "animal"}:
            err(f"ismeretlen címke: {item['id']} {tag}")

alias_owner = {}
for item in ingredients["ingredients"]:
    for alias in item["aliasesEN"]:
        key = alias.lower().strip()
        if key in alias_owner and alias_owner[key] != item["id"]:
            err(f"angol alias ütközik: '{key}' ({alias_owner[key]} / {item['id']})")
        alias_owner[key] = item["id"]

subs = load("substitutions.json")["substitutions"]
for sub in subs:
    if sub["ingredient"] not in by_id:
        err(f"csere: ismeretlen forrás {sub['ingredient']}")
        continue
    target = by_id.get(sub["to"])
    if target is None:
        err(f"csere: ismeretlen cél {sub['to']}")
        continue
    if sub["diet"] not in FORBIDDEN:
        err(f"csere: ismeretlen étrend {sub['diet']}")
        continue
    if set(target["tags"]) & FORBIDDEN[sub["diet"]]:
        err(f"csere nem felel meg az étrendnek: {sub['ingredient']} -> {sub['to']} ({sub['diet']})")

recipes = load("recipes_hu.json")["recipes"]
seen = set()
for recipe in recipes:
    rid = recipe["id"]
    if rid in seen:
        err(f"duplikált recept: {rid}")
    seen.add(rid)
    if not recipe["steps"]:
        err(f"{rid}: nincs lépés")
    if recipe["servings"] < 1:
        err(f"{rid}: adagszám")
    for ing in recipe["ingredients"]:
        if ing["id"] not in by_id:
            err(f"{rid}: ismeretlen hozzávaló {ing['id']}")
        if ing["unit"] not in UNITS:
            err(f"{rid}: ismeretlen mértékegység '{ing['unit']}'")
        if ing.get("amount") is not None and ing["amount"] <= 0:
            err(f"{rid}: nem pozitív mennyiség ({ing['id']})")
    for step in recipe["steps"]:
        if not step["text"].strip():
            err(f"{rid}: üres lépés")

if errors:
    print("\n".join(errors))
    print(f"{len(errors)} hiba")
    sys.exit(1)
print(f"rendben: {len(by_id)} alapanyag, {len(subs)} csere, {len(recipes)} recept")
