# Helyi leirat

készítette: szarkabalint.hu

Ingyenes, MIT licencű macOS-alkalmazás magyar hangfelvételek helyi átírásához. A Whisper large-v3 modellt MLX-szel, az Apple GPU-n futtatja. A hangot és a leiratot nem küldi felhős feldolgozásra.

## Követelmények

- Apple Silicon Mac; Intel Mac nem támogatott.
- macOS 27.0 vagy újabb.
- Legalább 8 GB szabad tárhely a modellhez és a helyi futásokhoz.
- Internet az egyszeri modellletöltéshez; utána az átírás offline is működik.

A kipróbált gép Apple M5, 32 GB memória, macOS 27.0.1. Más hardveren a feldolgozás ideje és memóriaigénye eltérhet.

## Letöltés és telepítés

**[Helyi leirat letöltése Apple Silicon Macre (.dmg)](https://github.com/szarkab/helyi-leirat/releases/download/v0.3.0/Helyi-leirat-0.3.0-apple-silicon-local.dmg)**

A kész alkalmazás használatához Python, Homebrew és fordítás nem szükséges.

1. Nyisd meg a `Helyi-leirat-0.3.0-apple-silicon-local.dmg` fájlt.
2. Húzd a **Helyi leirat** alkalmazást az **Applications** mappába.
3. Indítsd el a bemásolt appot, majd válaszd le a DMG-t.
4. Első használatkor a felületen töltsd le a kb. 3,2 GB-os alapmodellt. Az opcionális beszélőmodellek további kb. 108 MB-ot foglalnak.

A jelenlegi 0.3.0 kiadás helyi, ad-hoc aláírású előzetes, Apple-notarizáció nélkül. Letöltés után a macOS fejlesztői figyelmeztetést adhat. Ha a forrást megbízhatónak ítéled, a sikertelen indítás után a **Rendszerbeállítások → Adatvédelem és biztonság → Megnyitás mindenképpen** lehetőség használható, ha a rendszered engedélyezi. A rendszer védelmét nem kell globálisan kikapcsolni. [Apple útmutató](https://support.apple.com/en-us/102445)

## Használat

1. Válassz M4A-, MP3- vagy WAV-hangfelvételt.
2. Igény szerint kapcsold be a **Beszélők elkülönítése** checkboxot. A létszámbecslés automatikus.
3. Kövesd a feldolgozás előrehaladását. A **Megszakítás** leállítja a munkát; részleges leirat nem menthető teljesként.
4. Válassz **TXT** vagy **Markdown** formátumot, majd mentsd a leiratot.

Az export UTF-8 szöveg, időbélyegekkel. A felismert szöveget nem fogalmazza át. A beszélők névtelen címkéket kapnak. Az elakadt felismerés legfeljebb egyszer indul újra; szöveges ismétlésgyanú nem indít újabb teljes átírást és nem töröl elhangzott ismétlést.

## Adatkezelés és korlátok

A modell-előkészítés nyilvános Hugging Face és Sherpa-ONNX letöltést végez, bejelentkezés és API-kulcs nélkül. Nincs beépített analitika vagy felhős tartalék.

A `~/Library/Application Support/Helyi leirat/` mappában találhatók a modellek és a futások. A `runs/` mappa hangmásolatokat, leiratokat és helyi naplókat őriz; tartalma személyes adat lehet és nem törlődik automatikusan. Bezárt app mellett a már nem szükséges futások törölhetők, miután a kívánt exportokat elmentetted. A `models/` törlése új modellletöltést igényel. A frissítés megőrzi ezeket az adatokat.

A felismerés hibázhat: félrehallás, kihagyás, kitalált szöveg és pontatlan időbélyeg is előfordulhat. A beszélőcímkék becsült hangcsoportok. Az ellenőrizendő szó és egyszerre beszélés jelölése kísérleti segítség; hiánya nem bizonyít hibátlan leiratot. Megbízható automatikus érthetetlenség-felismerés nincs. Fontos tartalomnál hallgasd vissza a hangot.

## Fordítás forrásból

Apple Silicon Mac, macOS 27+, Python 3.13, `uv`, az Xcode parancssori eszközei és `make` szükségesek.

```sh
uv venv --python 3.13 .venv
uv pip sync --python .venv/bin/python requirements-build.lock.txt
uv pip install --python .venv/bin/python --no-deps --no-build-isolation -e .
.venv/bin/python scripts/build_app.py
.venv/bin/python scripts/build_dmg.py
```

Az app a `build/Helyi leirat.app`, a kiadási fájlok a `dist/` mappában készülnek el. A build saját, rögzített verziójú FFmpeg/FFprobe eszközöket fordít, és becsomagolja a helyi futtatókörnyezetet. A több GB-os modellsúlyokat nem építi be az alkalmazásba.

A forráscsomag az appot, a buildeszközöket, a függőséglistákat és a licenceket tartalmazza. Hangfájlok, leiratok és tesztanyagok nem részei.

## Kiadás GitHubon

A forrást a repozitóriumba töltsd fel. A DMG-t a **Releases** részben, a hozzá tartozó verziótaghez csatold a `SHA256SUMS` és `release.json` fájlokkal együtt. A saját forrás-ZIP is mellékelhető; a jelenlegi ellenőrzőösszeg-jegyzék erre is hivatkozik. A nem notarizált előzeteshez a **Pre-release** jelölés javasolt.

A `dist/` mappában a fájlok épsége a `shasum -a 256 -c SHA256SUMS` paranccsal ellenőrizhető. A README-ben a közzétett Release-re mutató letöltési hivatkozás segíti a felhasználókat.

## Licenc

A saját forráskód [MIT licencű](LICENSE). A csomagolt könyvtárak és külön letöltött modellek a saját licenceik alatt maradnak; részletek: [THIRD_PARTY.md](THIRD_PARTY.md). Az FFmpeg LGPL-2.1-or-later licencű; eredeti forrása és fordítási receptje az app **Licencek és források…** menüjéből is elérhető.
