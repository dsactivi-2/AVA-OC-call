# Validation Report — AVA + Asterisk + OpenClaw Plan
Datum: 2026-03-24
Validator: SUB-4 (Research & Analysis Agent)

---

## Ergebnis: NEEDS REVISION ⚠️

**5 kritische Fixes, 6 Minor Fixes**

---

## BESTAETIGT (Punkte die korrekt sind)

### 1. AVA GitHub-Repo existiert
Das Repository `https://github.com/hkjarral/AVA-AI-Voice-Agent-for-Asterisk` existiert und ist aktiv (Version 6.3.2, MIT-Lizenz).
- Quelle: https://github.com/hkjarral/AVA-AI-Voice-Agent-for-Asterisk
- AVA unterstuetzt AudioSocket als Default-Transport (explizit in `config/ai-agent.yaml`)
- AVA unterstuetzt ARI (Live ARI status im Admin UI dokumentiert)
- Python 3.11+ wird benoetigt (Plan nennt Python 3.10+ — ist ausreichend kompatibel, minor)

### 2. Asterisk ARI ari.conf — Felder korrekt
Alle konfigurierten Felder in `ari.conf` sind valide:
- `enabled` — korrekt
- `pretty` — korrekt
- `allowed_origins` — korrekt
- `auth_realm` — korrekt (in ari.conf.sample bestaetigt)
- `type = user` — korrekt
- `read_only` — korrekt
- `password` — korrekt
- `password_format = plain` — korrekt
- Quelle: https://github.com/asterisk/asterisk/blob/master/configs/samples/ari.conf.sample

### 3. AMD amd.conf — Meiste Parameter korrekt
Folgende Parameter existieren und sind korrekt in amd.conf:
- `initial_silence` — korrekt
- `greeting` — korrekt
- `after_greeting_silence` — korrekt
- `total_analysis_time` — korrekt
- `between_words_silence` — korrekt
- `maximum_number_of_words` — korrekt
- `silence_threshold` — korrekt
- `maximum_word_length` — korrekt
- Quelle: https://github.com/asterisk/asterisk/blob/master/configs/samples/amd.conf.sample

### 4. AMI Originate — Felder korrekt
Alle verwendeten Felder (Channel, Context, Exten, Priority, Timeout, CallerID, Variable, Async, ActionID) sind valide AMI Originate-Felder.
- Timeout-Einheit ist Millisekunden (korrekt — Script multipliziert `$CALL_TIMEOUT × 1000`)
- Quelle: https://docs.asterisk.org/Asterisk_18_Documentation/API_Documentation/AMI_Actions/Originate/

### 5. PJSIP Channel-Format korrekt
`PJSIP/${NUMBER}@sipgate` ist das korrekte Format fuer Outbound-Calls via PJSIP-Trunk.
- Quelle: https://community.asterisk.org/t/outbound-call-to-sip-trunk-with-pjsip/100049

### 6. OpenClaw Port 18789 OpenAI-kompatibel
Bestaetigt durch Denis' eigene Memory-Eintraege und CLAUDE.md: OpenClaw laeuft auf Port 18789 mit OpenAI-kompatiblem API-Endpunkt.
- Konfiguration in config.yaml (`provider: openai_compatible`, `base_url: http://127.0.0.1:18789/v1`) ist korrekt
- AVA unterstuetzt OpenAI-kompatible Endpunkte via `chat_base_url` Override

### 7. Shell-Scripts — set -euo pipefail vorhanden
Beide Scripts (`outbound-call.sh`, `batch-campaign.sh`) haben `set -euo pipefail` in Zeile 8/9.
- Fehlerbehandlung vorhanden (trap, Validierung, Error-Output)

### 8. ElevenLabs API-Endpunkt korrekt
`POST /v1/text-to-speech/{voice_id}` mit Header `xi-api-key` ist korrektes ElevenLabs-Format.
- Modell `eleven_multilingual_v2` existiert und ist korrekt.

### 9. Deepgram Nova-2 Model korrekt
`nova-2` ist ein valides Deepgram-Modell. Smart-format und punctuate sind valide Parameter.

---

## PROBLEME GEFUNDEN

### KRITISCH-1: AudioSocket-Dialplan — Falsche Parameter-Reihenfolge
**Problem:** In `extensions.conf` wird AudioSocket so aufgerufen:
```
AudioSocket(127.0.0.1:9092,${UNIQUEID})
```
Die offizielle Syntax laut Asterisk-Dokumentation ist `AudioSocket(uuid,service)` — UUID kommt **zuerst**, Service-Adresse kommt **zweimal**.
Ausserdem: `${UNIQUEID}` in Asterisk ist typischerweise im Format `1234567890.42` — das ist **kein gueltiges UUID-Format** (Standard-UUID: `550e8400-e29b-41d4-a716-446655440000`). Die Funktion `uuid_parse()` in app_audiosocket.c validiert das UUID und gibt einen Fehler zurueck wenn es kein gueltiges Format hat.

- Quelle: https://docs.asterisk.org/Asterisk_20_Documentation/API_Documentation/Dialplan_Applications/AudioSocket/
- Quelle: https://asterisk-doxygen.osso.pub/master/api/d9/daa/app__audiosocket_8c_source.html

**FIX:** In `asterisk-configs/extensions.conf` beide AudioSocket-Aufrufe aendern:
```
; ALT (FALSCH):
same => n,AudioSocket(127.0.0.1:9092,${UNIQUEID})

; NEU (KORREKT):
same => n,Set(AUDIO_UUID=${UUID()})
same => n,AudioSocket(${AUDIO_UUID},127.0.0.1:9092)
```
Benoetigt: Dialplan-Funktion `${UUID()}` (verfuegbar ab Asterisk 18 via `func_uuid`).

---

### KRITISCH-2: AMD() Dialplan-Aufruf — Falsche Parameter-Interpretation
**Problem:** In `extensions.conf` Zeile 21 steht:
```
AMD(800,2500,1500,5000,100,8,256)
```
Laut offizieller Asterisk-Dokumentation ist die Parameter-Reihenfolge:
1. initialSilence = 800
2. greeting = 2500
3. afterGreetingSilence = 1500
4. totalAnalysisTime = 5000
5. minimumWordLength = 100
6. betweenWordSilence = **8** (in ms — sehr niedrig!)
7. maximumNumberOfWords = **256** (extrem hoch!)

Der 6. Parameter `betweenWordSilence=8ms` ist faktisch 0 — das macht AMD sehr aggressiv bei Wort-Erkennung. Der 7. Parameter `maximumNumberOfWords=256` macht HUMAN-Erkennung nahezu unmoeglich (ein Mensch muesste 256 Woerter sprechen).

Im Kommentar des Plans steht `(800ms initial silence, 2500ms greeting, 1500ms after-greeting-silence, 5000ms total)` — die letzten 3 Parameter (`100,8,256`) sind offensichtlich falsch gesetzt. In der `amd.conf` sind korrekte Werte konfiguriert (`between_words_silence=50`, `maximum_number_of_words=3`), aber der inline-Dialplan-Aufruf ueberschreibt diese.

- Quelle: https://docs.asterisk.org/Latest_API/API_Documentation/Dialplan_Applications/AMD/

**FIX:** AMD()-Aufruf in `extensions.conf` korrigieren — entweder korrekte Werte eintragen oder Defaults aus amd.conf nutzen:
```
; Option A: Korrekter AMD()-Aufruf mit allen 7 Parametern:
same => n,AMD(800,2500,1500,5000,100,50,3)
;           ^    ^    ^    ^     ^   ^  ^
;           |    |    |    |     |   |  maximumNumberOfWords=3
;           |    |    |    |     |   betweenWordSilence=50ms
;           |    |    |    |     minimumWordLength=100ms
;           |    |    |    totalAnalysisTime=5000ms
;           |    |    afterGreetingSilence=1500ms
;           |    greeting=2500ms
;           initialSilence=800ms

; Option B (empfohlen): Keine Inline-Parameter, Defaults aus amd.conf nutzen:
same => n,AMD()
```

---

### KRITISCH-3: amd.conf — Falscher Parameter-Name
**Problem:** In `asterisk-configs/amd.conf` Zeile 24 steht:
```
min_word_length = 100
```
Das ist der korrekte Name fuer amd.conf (`min_word_length`). Allerdings ist im Runbook Abschnitt 8 (AMD Tuning) in der Kommentar-Sektion der Name **`minimum_word_length`** verwendet (Zeile 268: `; minimum_word_length: Max. Wortlaenge...`). Das ist inkonsistent und koennte zu Verwirrung fuehren.

Der offizielle Parameter-Name in amd.conf ist: **`min_word_length`** (nicht `minimum_word_length`).

- Quelle: https://github.com/asterisk/asterisk/blob/master/configs/samples/amd.conf.sample

**FIX:** Im `runbook.md` Abschnitt 8 den Kommentar korrigieren:
```
; ALT (Kommentar-Fehler in runbook.md):
; minimum_word_length: Max. Wortlaenge...

; NEU (korrekt):
; min_word_length: Minimale Wortlaenge...
```
Die `amd.conf` selbst ist korrekt — nur der Runbook-Kommentar muss angepasst werden.

---

### KRITISCH-4: Deepgram-Preise veraltet/falsch
**Problem:** In `costs.md` werden Deepgram-Preise als `$0.0043/min` angegeben. Laut aktuellem Deepgram-Preisverzeichnis (2026) sind die Preise hoeher:
- Pay-as-you-go: **$0.0058/min** (nicht $0.0043)
- Growth Plan: **$0.0047/min** (nicht $0.0036)

Der in costs.md genannte Wert `$0.0036/min` fuer den Growth-Plan stimmt nicht mit dem aktuellen Preismodell ueberein.

- Quelle: https://deepgram.com/pricing

**FIX:** In `costs.md` Deepgram-Preistabelle korrigieren:
```
; ALT:
| Pay-as-you-go | $0.0043/min | Nova-2, Echtzeit-Streaming |
| Growth (100h/Monat) | $0.0036/min | Ab 100 Stunden/Monat |

; NEU:
| Pay-as-you-go | $0.0058/min | Nova-2, Echtzeit-Streaming |
| Growth Plan | $0.0047/min | Ab $4.000/Jahr |
```
Die Enterprise-Kosten-Schatzung im Szenario 4 ($0.0043 × 50.000 min = $215) ist dadurch ca. 35% zu niedrig. Korrekt: $0.0058 × 50.000 = $290.

---

### KRITISCH-5: Hetzner-Preise veraltet/falsch
**Problem:** In `costs.md` werden folgende Hetzner-Preise genannt:
- CX22: EUR 5.52 → Aktuell: **EUR 3.79**
- CX32: EUR 9.90 → Aktuell: **EUR 6.80**
- CX42: EUR 21.58 → Aktuell: **EUR 16.40**
- CX52: EUR 49.29 → Aktuell: **EUR 32.40**

Alle Hetzner-Preise sind signifikant hoeher als die aktuellen Marktpreise. Das beeinflusst alle 4 Kostenszenarien.

- Quelle: https://costgoat.com/pricing/hetzner (Stand Maerz 2026)
- Hinweis: Ab 1. April 2026 koennte eine Preisanpassung erfolgen (laut Hetzner Docs)

**FIX:** In `costs.md` Hetzner-Preistabelle korrigieren:
```
; ALT:
| CX22 | 2 | 4 GB | EUR 5.52 |
| CX32 | 4 | 8 GB | EUR 9.90 |
| CX42 | 8 | 16 GB | EUR 21.58 |
| CX52 | 16 | 32 GB | EUR 49.29 |

; NEU (Stand Maerz 2026):
| CX22 | 2 | 4 GB | EUR 3.79 |
| CX32 | 4 | 8 GB | EUR 6.80 |
| CX42 | 8 | 16 GB | EUR 16.40 |
| CX52 | 16 | 32 GB | EUR 32.40 |
```
Alle 4 Kostenszenarien muessen entsprechend nach unten korrigiert werden (Vorteil: Stack ist noch guenstiger als berechnet).

---

## MINOR FIXES (empfohlen)

### MINOR-1: ElevenLabs Creator-Plan Preis unklar
**Problem:** In `costs.md` wird der Creator-Plan mit **$22/Monat** angegeben. Aktuelle Quellen (Maerz 2026) zeigen teils **$11/Monat** (mit 50% Rabatt auf ersten Monat) oder weiterhin $22 als Regelpreis. Die Zeichenbegrenzung (100.000 Zeichen) ist korrekt. Der Pro-Plan ($99/500k Zeichen) und Scale-Plan ($330/2M Zeichen) sind bestaetigt korrekt.
- Quelle: https://flexprice.io/blog/elevenlabs-pricing-breakdown
- FIX: Preis als "$11-22/Monat (Regularpreis $22)" annotieren oder direkt prufen.

### MINOR-2: Azure TTS Free-Tier unklar in costs.md
**Problem:** `costs.md` nennt "Free: 0-500.000 Zeichen/Monat — Standard-Stimmen". Laut aktueller Azure-Dokumentation gilt: Neural-TTS Free Tier = **500.000 Zeichen/Monat** (F0 Tier). Der Paid-Preis fuer Neural ist **$16/Million Zeichen** (nicht $16 wie im Plan — das stimmt).
- Quelle: https://azure.microsoft.com/en-us/pricing/details/cognitive-services/speech-services/
- FIX: Azure Free-Tier im Plan explizit als "500k Zeichen/Monat Neural (F0 Tier)" annotieren.

### MINOR-3: AVA Repo-URL im Plan veraltet
**Problem:** `setup-guide.md` referenziert:
```
git clone https://github.com/hkjarral/AVA-AI-Voice-Agent-for-Asterisk.git
```
Das Repo existiert unter dieser URL korrekt. Allerdings gibt es auch ein zweites verwandtes Repo unter `https://github.com/hkjarral/Asterisk-AI-Voice-Agent` (aktiv, mit anderer Architektur). Der Plan sollte explizit klarstellen, welches Repo gemeint ist.
- Quelle: https://github.com/hkjarral/AVA-AI-Voice-Agent-for-Asterisk
- FIX: URL im setup-guide.md beibehalten, aber Hinweis ergaenzen dass es ein zweites Repo des Autors gibt (`Asterisk-AI-Voice-Agent`) mit neuerer Architektur.

### MINOR-4: AVA config.yaml Format-Unterschied zur offiziellen Konfiguration
**Problem:** Das offizielle AVA-Repo verwendet `config/ai-agent.yaml` als primae Konfigurationsdatei (nicht `config.yaml`). Das Blueprint hat eine eigene `config.yaml` erstellt, die dem AVA-Repo nicht 1:1 entspricht. Insbesondere:
- Offizielle AVA-Config verwendet `providers.<name>.model` (nicht `llm.model`)
- Der `system_prompt` wird im offiziellen Repo via `llm.prompt` konfiguriert
- Der Plan-Config-Key `llm.provider: openai_compatible` koennte nicht dem offiziellen Schluessel entsprechen
- Quelle: https://github.com/hkjarral/Asterisk-AI-Voice-Agent/blob/main/docs/Configuration-Reference.md
- FIX: Konfigurationsformat nach erstem `git clone` gegen tatsaechliche `ai-agent.yaml` des Repos abgleichen. Die Blueprint-config.yaml gilt als Referenz, muss aber an das reale Repo-Format angepasst werden.

### MINOR-5: nc -q Flag auf Linux-Servern
**Problem:** In `outbound-call.sh` wird `nc -q 2` verwendet. Das `-q` Flag ist nur in GNU/Linux `netcat-traditional` verfuegbar, nicht in BSD-netcat (macOS) oder `netcat-openbsd`. Da der Stack auf Hetzner Linux-Servern laeuft, ist das Flag korrekt fuer diese Zielumgebung. Auf macOS-Entwicklungsrechner schlaegt das Script fehl.
- Quelle: https://forums.freebsd.org/threads/netcat-missing-q.86933/
- FIX: Dokumentation-Hinweis ergaenzen: "Script laeuft nur auf Linux (GNU netcat). Auf macOS: `brew install netcat` oder `nc -w 2` statt `-q 2` verwenden."

### MINOR-6: AVA Python-Version
**Problem:** Plan verlangt Python 3.10+, offizielles AVA-Repo verlangt Python 3.11+.
- Quelle: https://github.com/hkjarral/AVA-AI-Voice-Agent-for-Asterisk (README)
- FIX: In `setup-guide.md` Voraussetzung aendern von "Python 3.10+" zu "Python 3.11+".

---

## Kritische Fixes (muss behoben werden)

1. **AudioSocket()-Syntax falsch** — Reihenfolge uuid,service (uuid zuerst) und ${UNIQUEID} ist kein gueltiges UUID-Format — Fix: `${UUID()}` verwenden
2. **AMD()-Dialplan-Aufruf** — Parameter 6 und 7 sind extrem falsch (betweenWordSilence=8ms, maximumNumberOfWords=256) — AMD erkennt niemals HUMAN
3. **amd.conf Kommentar im Runbook** — `minimum_word_length` ist kein gueltiger Parameter-Name (korrekt: `min_word_length`)
4. **Deepgram-Preise** — $0.0043/min ist veraltet, aktuell: $0.0058/min Pay-as-you-go (35% Abweichung)
5. **Hetzner-Preise** — Alle 4 Serverkategorien zu teuer angegeben (CX32: EUR 9.90 statt EUR 6.80)

## Minor Fixes (empfohlen)

1. ElevenLabs Creator-Plan Preis unklar ($11 vs $22) — verifizieren
2. Azure TTS Free-Tier expliziter dokumentieren (500k Zeichen Neural)
3. AVA hat zweites Repo-Variante — Hinweis ergaenzen
4. AVA config.yaml Format nach echtem Repo-Clone abgleichen
5. nc -q auf macOS nicht verfuegbar — Hinweis in Doku ergaenzen
6. Python-Mindestversion: 3.10 → 3.11

---

## Gesamt-Empfehlung

**REVISION REQUIRED — 5 kritische, 6 minor Fixes**

Der Plan ist architektonisch solide und die Gesamtstrategie (Asterisk + ARI + AudioSocket + AVA + OpenClaw) ist korrekt und technisch realisierbar. Die kritischen Fehler sind konkret und behebbar:

- Kritisch-1 und Kritisch-2 sind **Showstopper**: Mit falscher AudioSocket-Syntax und falschem AMD()-Aufruf wuerde der Stack nicht funktionieren (kein Audio, AMD erkennt nie HUMAN).
- Kritisch-4 und Kritisch-5 (Preise) sind **Planungs-Fehler**: Der Stack ist in Wirklichkeit noch guenstiger als berechnet (positive Abweichung).
- Kritisch-3 ist ein Dokumentationsfehler ohne Laufzeit-Auswirkung.

Nach den 5 kritischen Fixes ist der Stack produktionsreif.

---

## Quellen

- [AVA GitHub Repo](https://github.com/hkjarral/AVA-AI-Voice-Agent-for-Asterisk)
- [Asterisk AudioSocket Docs](https://docs.asterisk.org/Asterisk_20_Documentation/API_Documentation/Dialplan_Applications/AudioSocket/)
- [app_audiosocket.c Source](https://asterisk-doxygen.osso.pub/master/api/d9/daa/app__audiosocket_8c_source.html)
- [Asterisk ARI Konfiguration](https://docs.asterisk.org/Configuration/Interfaces/Asterisk-REST-Interface-ARI/Asterisk-Configuration-for-ARI/)
- [ari.conf.sample](https://github.com/asterisk/asterisk/blob/master/configs/samples/ari.conf.sample)
- [AMD() Dokumentation](https://docs.asterisk.org/Latest_API/API_Documentation/Dialplan_Applications/AMD/)
- [amd.conf.sample](https://github.com/asterisk/asterisk/blob/master/configs/samples/amd.conf.sample)
- [AMI Originate Action](https://docs.asterisk.org/Asterisk_18_Documentation/API_Documentation/AMI_Actions/Originate/)
- [Deepgram Pricing 2026](https://deepgram.com/pricing)
- [ElevenLabs Pricing 2026](https://elevenlabs.io/pricing)
- [Azure TTS Pricing](https://azure.microsoft.com/en-us/pricing/details/cognitive-services/speech-services/)
- [Hetzner Cloud Pricing](https://costgoat.com/pricing/hetzner)
- [AVA Configuration Reference](https://github.com/hkjarral/Asterisk-AI-Voice-Agent/blob/main/docs/Configuration-Reference.md)
