# LibreChat Desktop Windows — Docker nélküli prototípus

**Állapot (2026-10-22): fejlesztői proof of concept, NEM kész Windows-telepítő.** A Windowsos teljes indítást még nem teszteltük.

## Mi változik?

A LibreChat megjelenik egy önálló **Electron Windows-alkalmazásablakban**, és a helyi LibreChat backend / MongoDB automatikusan indul vele. Dockerre nincs szükség. A MongoDB WiredTiger-t használ és megőrzi a felhasználói adatokat a kilépések között.

A Windowsos indító letölti a **hordozható Node.js 24.16.0** verziót (SHA-256 ellenőrzéssel), telepíti a függőségeket, felépíti a LibreChat frontendjét és létrehozza a Start menüs/asztali parancsikont.

## Gyors indítás (Windows 10/11 x64)

1. Töltsd le ezt az ágat ZIP-ként.
2. Csomagold ki normál mappába, és **ne töröld**, mert jelenleg ebből fut.
3. Duplán kattints a **desktop/windows/Telepites.cmd** fájlra.
4. A telepítés végén a saját LibreChat ablak megnyílik, később az asztali parancsikonról indítható.

Másik út: a **desktop/windows/QuickInstall.ps1** letölti ennek az ágnak a forrás ZIP-jét a helyi felhasználói AppData mappába, és onnan végzi el a telepítést.

## Adatok / naplók

- Állandó adatbázis: %LOCALAPPDATA%\LibreChatDesktop\data\mongodb
- Mongo bináris cache: %LOCALAPPDATA%\LibreChatDesktop\data\mongodb-binaries
- Backend / Desktop naplók: %LOCALAPPDATA%\LibreChatDesktop\data\logs
- Hordozható Node.js: %LOCALAPPDATA%\LibreChatDesktop\runtime\node
- LibreChat konfiguráció: a repo mappájában lévő .env

**Az adatmappát ne töröld!**

## Technológia

- Az eredeti React LibreChat UI fut Electron keretben, **nem WinUI-újraírás**.
- Az Electron a Node.js backend folyamatát vezérli.
- A mongodb-memory-server-core egy valós MongoDB binárist indít a gépen, állandó WiredTiger adatbázissal.
- Az API és az adatbázis csak 127.0.0.1-en érhető el; nincsenek publikált hálózati portok.

## Mit nem garantál még ez a prototípus?

- Nincs előre összeállított, aláírt, önálló LibreChat-Setup.exe.
- A SEARCH=false miatt hiányzik a Meilisearch beszélgetés-keresés.
- A Python RAG API, pgvector és egyéb opcionális szolgáltatások nincsenek beépítve.
- SSO/OAuth külső átirányítások vizsgálatot igényelnek.
- Nincs Windows 10/11 teljes telepítési, futás-, adatmegőrzési és funkcióteszt.
- Első futtatáskor MongoDB bináris letöltés kell, és az npm build nagy erőforrásigényű.

## Ellenőrzés

A lokális Node.js tesztfájl (desktop/runtime.test.cjs) **4/4 tesztje sikeresen lefutott**.
A Windows telepítési folyamatot nem futtattuk le ebben a környezetben.

A fork eredeti main ágát nem módosítottuk.

## 2026-10-22 — telepítőhiba utáni forráskód-audit

Az első gyorsindító **nem volt Windows alatt végponttól végpontig tesztelt**, ezért nem tekinthető telepítőkiadásnak. A következő **kódból bizonyított hibákat/hiányosságokat** javítottuk a fejlesztői ágon:

1. A LibreChat `/health` vagy gyökér HTTP-válaszát késznek tekintettük; ehelyett a **`/readyz`** végpont HTTP 200 válaszát várjuk meg, amely csak a teljes inicializálás után kész.
2. A hivatalosan javasolt npm 11.16.0 helyett a Node.js ZIP-ben érkező 11.13.0 volt használatban; most külön települ a rögzített npm 11.16.0.
3. Windows alatt a child.kill() azonnali folyamatleállításhoz vezethetett, még a MongoDB leállítása előtt; most IPC-vezérelt SIGTERM-alapú, időkorlátos backend leállítás előzi meg a MongoDB leállítását.
4. A második alkalmazáspéldány nem volt tiltva; most az alkalmazás egyetlen példányt enged.
5. A régi letöltött forrásban lévő hibás szkriptek beragadhattak; a bootstrap verziózott Desktop fájlokat frissít, az adatokat megtartja.

**Teszt:** hét célzott Node.js egységteszt átment egy Linux/Node környezetben. A Windowsos felületi/telepítési/end-to-end teszt még nincs meg. A Windows GitHub Actions ellenőrzés forrása: `.github/workflows/desktop-windows-smoke.yml`. A PR továbbra is **Draft**, nem szabad kiadássá vagy működő EXE-telepítővé nyilvánítani.

Fontos: a teljes LibreChat forrásból helyben történő `npm ci` / `npm run frontend` build még mindig fejlesztői folyamat. A célzott végleges megoldás az előre lefordított és Windows alatt valóban tesztelt telepítő, ahol a felhasználó nem a saját gépén buildeli a projektet.
