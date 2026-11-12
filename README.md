# Fincsi

iPhone-os receptajánló: add meg, mi van otthon és mit nem szeretsz, a Fincsi pedig magyar recepteket javasol belőle. Étrend (gluténmentes, vegán, vegetáriánus, laktózmentes, dió nélkül) esetén a hozzávalókhoz cserét is ajánl.

## Funkciók

- **Kamra**: több mint 300 alapanyag kategóriánként, kereséssel; „van otthon” és „nem kérem” jelölés.
- **Receptajánló**: „most megfőzhető” és „majdnem megvan” lista, napi ötlet, véletlen választás, szűrés fogásra, kedvencekre és szövegre.
- **Étrendek és cserék**: a szűrés alapanyag-címkékre épül, a javasolt csere minden aktív étrendnek megfelel; elhagyható hozzávalók automatikusan kimaradnak.
- **Receptek**: 55 beépített magyar recept (offline), és további receptek a TheMealDB-ből gépi fordítással (DeepL, tartalékként MyMemory).
- **Receptoldal**: adagszám-átváltás, magyar mértékegységek, hiányzók a bevásárlólistára, megosztás.
- **Főzés mód**: lépésenként, időzítőkkel és értesítéssel, a kijelző nem alszik el.
- **Bevásárlólista**, kedvencek, előzmények; minden adat az eszközön marad.

## Fejlesztés

Szükséges: macOS, Xcode 16 vagy újabb, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open Fincsi.xcodeproj
```

A logikát a `FincsiKit` Swift csomag tartalmazza (`Sources/FincsiKit`), a felület az `App/Sources` mappában van.

```sh
swift test                      # egységtesztek
python3 Scripts/validate_data.py  # a beépített adatok ellenőrzése
```

## Adatforrások és kulcsok

- **TheMealDB**: az alapértelmezett `1` kulcs fejlesztési teszt-kulcs. Nyilvános kiadáshoz a szolgáltatás támogatói kulcsát kell megadni a Beállításokban.
- **DeepL**: opcionális, saját API-kulcs a Beállításokban (a Kulcstartóban tárolódik).
- **MyMemory**: kulcs nélkül, napi korláttal használható.

## Fontos

A receptek és cserejavaslatok tájékoztató jellegűek. Súlyos élelmiszer-allergia vagy cöliákia esetén mindig ellenőrizd a termékek címkéjét.
