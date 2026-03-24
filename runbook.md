# Runbook — AVA + Asterisk + OpenClaw AI-Callcenter
## Betrieb, Monitoring, Troubleshooting

---

## 1. Dienste starten / stoppen / neustarten

### Asterisk

```bash
# Status prüfen
systemctl status asterisk

# Starten
systemctl start asterisk

# Stoppen (laufende Calls werden ABGEBROCHEN — immer warten bis keine aktiven Kanäle)
asterisk -rx "core show calls"   # Erst prüfen ob Calls aktiv
systemctl stop asterisk

# Graceful Stop (wartet bis alle aktiven Calls beendet sind)
asterisk -rx "core stop gracefully"

# Neustart (kurze Unterbrechung)
systemctl restart asterisk

# Reload (Konfiguration neu laden OHNE Neustart — bevorzugt im Betrieb)
asterisk -rx "core reload"
asterisk -rx "dialplan reload"
asterisk -rx "module reload res_pjsip.so"
```

### AVA AI Voice Agent

```bash
# Status prüfen
systemctl status ava-agent

# Starten
systemctl start ava-agent

# Stoppen (laufende AudioSocket-Verbindungen werden getrennt)
systemctl stop ava-agent

# Neustart
systemctl restart ava-agent

# Logs live beobachten
journalctl -u ava-agent -f

# Letzten 100 Zeilen
journalctl -u ava-agent -n 100
```

### OpenClaw

```bash
# Status prüfen
systemctl status openclaw
# ODER falls PM2:
pm2 status openclaw

# Starten (systemd)
systemctl start openclaw
# ODER (PM2)
pm2 start openclaw

# Stoppen
systemctl stop openclaw
# ODER
pm2 stop openclaw

# Neustart mit Config-Reload
systemctl restart openclaw
# ODER
pm2 restart openclaw

# OpenClaw-Logs (systemd)
journalctl -u openclaw -f
# ODER (PM2)
pm2 logs openclaw --lines 100

# OpenClaw Port-Check
curl -s http://127.0.0.1:18789/v1/models | python3 -m json.tool
```

---

## 2. Startsequenz beim Serverstart

Korrekte Reihenfolge wenn alle Dienste neu gestartet werden muessen:

```bash
# 1. Asterisk zuerst (AVA braucht ARI)
systemctl start asterisk
sleep 5

# 2. ARI erreichbar?
curl -u ava-bot:ava-secret-2024 http://127.0.0.1:8088/ari/api-docs
# Erwartet: JSON-Response mit API-Beschreibung

# 3. OpenClaw starten (braucht Anthropic-Key)
systemctl start openclaw
sleep 3

# 4. OpenClaw erreichbar?
curl -s http://127.0.0.1:18789/v1/models
# Erwartet: {"object":"list","data":[...]}

# 5. AVA starten
systemctl start ava-agent

# 6. Gesamtstatus prüfen
/usr/local/bin/health-check.sh
```

---

## 3. Systemd Service Commands — Übersicht

| Aktion | Asterisk | AVA | OpenClaw |
|--------|----------|-----|----------|
| Status | `systemctl status asterisk` | `systemctl status ava-agent` | `systemctl status openclaw` |
| Start | `systemctl start asterisk` | `systemctl start ava-agent` | `systemctl start openclaw` |
| Stop | `systemctl stop asterisk` | `systemctl stop ava-agent` | `systemctl stop openclaw` |
| Restart | `systemctl restart asterisk` | `systemctl restart ava-agent` | `systemctl restart openclaw` |
| Logs | `journalctl -u asterisk -f` | `journalctl -u ava-agent -f` | `journalctl -u openclaw -f` |
| Autostart | `systemctl enable asterisk` | `systemctl enable ava-agent` | `systemctl enable openclaw` |
| Autostart aus | `systemctl disable asterisk` | `systemctl disable ava-agent` | `systemctl disable openclaw` |

---

## 4. Asterisk CLI Cheat Sheet

### Verbindung zur Asterisk-Konsole

```bash
# Interaktive Konsole (von aussen verbinden)
asterisk -r

# Befehl direkt ausfuehren (ohne interaktive Konsole)
asterisk -rx "BEFEHL HIER"

# Verbositaet erhoehen (0-5, Standard: 3)
asterisk -rvvv
```

### Aktive Calls und Kanaele

```bash
# Alle aktiven Kanaele anzeigen
asterisk -rx "core show channels"

# Kanaele mit Details
asterisk -rx "core show channels verbose"

# Anzahl aktiver Calls
asterisk -rx "core show calls"

# Aktuellen Call beenden (Kanal-ID aus "core show channels")
asterisk -rx "channel request hangup SIP/sipgate-00000001"

# Alle aktiven Calls beenden (VORSICHT — trennt alle Verbindungen)
asterisk -rx "channel request hangup all"
```

### SIP / PJSIP Peer-Status

```bash
# Alle PJSIP-Endpoints anzeigen
asterisk -rx "pjsip show endpoints"

# Einzelnen Endpoint prüfen
asterisk -rx "pjsip show endpoint sipgate-trunk"

# PJSIP Registrierungen
asterisk -rx "pjsip show registrations"

# SIP-Verbindungstatus Sipgate
asterisk -rx "pjsip show aors"

# PJSIP Debug aktivieren (für Fehlersuche)
asterisk -rx "pjsip set logger on"
asterisk -rx "pjsip set logger off"
```

### Dialplan

```bash
# Alle Contexts anzeigen
asterisk -rx "dialplan show"

# Bestimmten Context anzeigen
asterisk -rx "dialplan show ava-outbound"
asterisk -rx "dialplan show ava-inbound"

# Dialplan neu laden (nach extensions.conf Aenderung)
asterisk -rx "dialplan reload"

# Extension testen (Dialplan-Logik prüfen ohne echten Anruf)
asterisk -rx "dialplan show ava-outbound@+4917600000000"
```

### AMD

```bash
# AMD-Modul Status
asterisk -rx "module show like amd"

# AMD-Modul neu laden (nach amd.conf Aenderung)
asterisk -rx "module reload app_amd.so"

# AMD-Verbose fuer naechsten Call aktivieren
asterisk -rx "core set verbose 5"
# Dann Call starten und in den Logs nach "AMD:" suchen
```

### Module

```bash
# Alle geladenen Module
asterisk -rx "module show"

# Spezifisches Modul prüfen
asterisk -rx "module show like audiosocket"
asterisk -rx "module show like ari"
asterisk -rx "module show like amd"
asterisk -rx "module show like pjsip"

# Modul laden (falls nicht automatisch)
asterisk -rx "module load app_audiosocket.so"
asterisk -rx "module load app_amd.so"

# Modul neu laden
asterisk -rx "module reload res_ari.so"
```

### Logging und Debug

```bash
# Verbose-Level setzen (0-5)
asterisk -rx "core set verbose 3"

# Debug-Level setzen
asterisk -rx "core set debug 0"   # aus
asterisk -rx "core set debug 1"   # ein

# Asterisk-Logs (Datei)
tail -f /var/log/asterisk/full
tail -f /var/log/asterisk/messages
grep "AMD:" /var/log/asterisk/full | tail -50
grep "ERROR" /var/log/asterisk/full | tail -20
```

### ARI Status

```bash
# ARI-Status prüfen
asterisk -rx "ari show status"

# ARI-Apps anzeigen
asterisk -rx "ari show apps"

# ARI-Verbindungen
asterisk -rx "ari show app ava"
```

---

## 5. AVA Logs abrufen

```bash
# Live-Logs verfolgen
journalctl -u ava-agent -f

# Letzte N Zeilen
journalctl -u ava-agent -n 200

# Logs seit einem bestimmten Zeitpunkt
journalctl -u ava-agent --since "2026-03-24 09:00:00"

# Nur Fehler
journalctl -u ava-agent -p err

# Logs in Datei (falls konfiguriert)
tail -f /var/log/ava/agent.log
grep "ERROR" /var/log/ava/agent.log | tail -30
grep "AMD" /var/log/ava/agent.log | tail -30

# AVA AudioSocket-Verbindungen
grep "AudioSocket" /var/log/ava/agent.log | tail -20

# OpenClaw-Anfragen von AVA
grep "POST.*18789" /var/log/ava/agent.log | tail -20

# Gesprächs-Outcomes
grep "OUTCOME:" /var/log/ava/agent.log | tail -50

# Laufende AudioSocket-Verbindungen (Ports)
ss -tlnp | grep 9092
lsof -i :9092
```

---

## 6. Kampagne starten und stoppen

### Einzelnen Anruf starten

```bash
# Einfacher Test-Call
/usr/local/bin/outbound-call.sh \
  --number "+4917612345678" \
  --lead-name "Max Mustermann" \
  --language "de" \
  --campaign-id "test-001"

# Mit Job-Profil
/usr/local/bin/outbound-call.sh \
  --number "+4917612345678" \
  --lead-name "Amir Bobic" \
  --language "bs" \
  --job-title "LKW-Fahrer" \
  --campaign-id "campaign-2026-03"
```

### Kampagne aus CSV starten

```bash
# Kampagne starten (alle Leads in CSV anrufen)
/usr/local/bin/batch-campaign.sh \
  --csv /path/to/leads.csv \
  --campaign-id "march-2026" \
  --max-concurrent 3 \
  --call-delay 5

# Kampagne im Hintergrund (nohup)
nohup /usr/local/bin/batch-campaign.sh \
  --csv /path/to/leads.csv \
  --campaign-id "march-2026" \
  > /var/log/ava/campaign-march-2026.log 2>&1 &

# PID merken
echo $! > /var/run/ava-campaign.pid

# Status der laufenden Kampagne
cat /var/run/ava-campaign.pid
ps -p $(cat /var/run/ava-campaign.pid)
```

### Kampagne stoppen

```bash
# Laufende Kampagne beenden (kein neuer Call-Start mehr)
kill $(cat /var/run/ava-campaign.pid)

# Sofortige Unterbrechung aller aktiven Calls:
asterisk -rx "core show channels"
asterisk -rx "channel request hangup all"

# Kampagnen-Logs prüfen
tail -f /var/log/ava/campaign-march-2026.log
```

### Kampagnen-Fortschritt prüfen

```bash
# Outcomes des aktuellen Tages
cat /var/log/ava/outcomes/$(date +%Y-%m-%d).jsonl | python3 -c "
import sys, json
lines = [json.loads(l) for l in sys.stdin]
outcomes = {}
for l in lines:
    o = l.get('outcome', 'unknown')
    outcomes[o] = outcomes.get(o, 0) + 1
for k, v in sorted(outcomes.items()):
    print(f'{k}: {v}')
print(f'Total: {len(lines)}')
"
```

---

## 7. Health Checks

### Vollstaendiger Health Check

```bash
/usr/local/bin/health-check.sh
```

Erwartet:
```
[OK] Asterisk laeuft (PID: XXXXX)
[OK] ARI erreichbar (Port 8088)
[OK] AMI erreichbar (Port 5038)
[OK] AVA laeuft (Port 9092)
[OK] OpenClaw erreichbar (Port 18789)
[OK] app_amd.so geladen
[OK] app_audiosocket.so geladen
[OK] Sipgate SIP registriert
```

### Manuelle Port-Checks

```bash
# Asterisk ARI
curl -s -u ava-bot:ava-secret-2024 http://127.0.0.1:8088/ari/api-docs | head -5

# Asterisk AMI
echo "Action: Ping" | nc 127.0.0.1 5038 -q 1

# AVA AudioSocket
ss -tlnp | grep 9092

# OpenClaw API
curl -s http://127.0.0.1:18789/v1/models | python3 -m json.tool

# Sipgate SIP-Registrierung
asterisk -rx "pjsip show registrations" | grep -E "sipgate|Registered|Unregistered"
```

### Kontinuierliches Monitoring

```bash
# Alle 10 Sekunden Health-Check (fuer Troubleshooting-Sessions)
watch -n 10 /usr/local/bin/health-check.sh

# Aktive Kanaele live
watch -n 2 "asterisk -rx 'core show calls'"
```

---

## 8. AMD Tuning — amd.conf Parameter

AMD (Answering Machine Detection) erfordert Feinabstimmung pro Netzwerk/Zielgruppe.

Datei: `/etc/asterisk/amd.conf`

```ini
[general]
; Maximale Stille vor dem ersten Ton (ms)
; Zu niedrig: Menschliche Pause wird als Maschine erkannt
; Zu hoch: Lange Wartezeit bevor AMD entscheidet
initial_silence = 2500          ; Standard: 2500ms

; Maximale Laenge einer menschlichen Begruessung (ms)
; Menschliche Begruessung "Ja?" oder "Hallo?" ist kurz
; Anrufbeantworter-Ansagen sind laenger
greeting = 1500                  ; Standard: 1500ms

; Stille nach der Begruessung = Anrufbeantworter-Signal
; Anrufbeantworter macht nach Ansage Stille, Mensch antwortet ohne Pause
after_greeting_silence = 800    ; Standard: 800ms

; Maximale AMD-Analysezeit (ms) — danach: NOTSURE
total_analysis_time = 5000      ; Standard: 5000ms

; Minimaler Wortlaenge um als Sprache erkannt zu werden (ms)
min_word_length = 100           ; Standard: 100ms

; Zwischen-Wort-Stille (ms)
between_words_silence = 50      ; Standard: 50ms

; Maximale Anzahl Woerter bevor als Mensch klassifiziert
maximum_number_of_words = 2     ; Standard: 2

; Ton-Laenge fuer Voicemail-Erkennnung (ms)
silence_threshold = 256         ; Standard: 256
```

### AMD Tuning fuer typische DE-Mobilfunk-Szenarien

```ini
; Aggressivere Einstellungen fuer hoehere Treffsicherheit bei Mobilfunk:
initial_silence = 2000          ; Weniger Wartezeit
greeting = 1200                 ; Menschliche Begruessung "Ja?" kurz
after_greeting_silence = 600    ; Anrufbeantworter-Stille kuerzer
total_analysis_time = 4000      ; Schnellere Entscheidung
maximum_number_of_words = 3     ; Mehr Toleranz
```

### AMD nach Aenderung neu laden

```bash
asterisk -rx "module reload app_amd.so"
# Verifikation: Naechster Anruf mit verbose 5 beobachten
asterisk -rx "core set verbose 5"
```

### AMD-Ergebnisse auswerten

```bash
# AMD-Treffer aus Logs lesen
grep "AMD:" /var/log/asterisk/full | \
  grep -E "HUMAN|MACHINE|NOTSURE" | \
  awk '{print $NF}' | sort | uniq -c

# Typisch gutes Ergebnis (bei 100 Calls):
# 55 HUMAN
# 35 MACHINE
# 10 NOTSURE
```

---

## 9. Common Issues und Loesungen

### Problem 1: AVA startet nicht — ARI-Verbindung schlaegt fehl

**Symptom:** `journalctl -u ava-agent` zeigt "Connection refused" oder "WebSocket error"

**Ursachen und Loesungen:**
```bash
# Ursache A: Asterisk laeuft nicht
systemctl status asterisk
systemctl start asterisk

# Ursache B: ARI nicht aktiviert
cat /etc/asterisk/ari.conf | grep enabled
# Muss sein: enabled = yes
asterisk -rx "ari show status"

# Ursache C: Falsches Passwort in AVA-Config
cat /opt/ava/.env | grep ASTERISK_ARI
# Muss mit ari.conf uebereinstimmen
asterisk -rx "ari show users"

# Ursache D: Firewall blockiert Port 8088
ss -tlnp | grep 8088
# Muss LISTEN 0.0.0.0:8088 oder 127.0.0.1:8088 zeigen
```

---

### Problem 2: AudioSocket-Verbindung wird nicht hergestellt

**Symptom:** Call startet, aber kein Audio — AVA-Log zeigt kein "AudioSocket connected"

**Loesungen:**
```bash
# AudioSocket-Modul prüfen
asterisk -rx "module show like audiosocket"
# Falls nicht geladen:
asterisk -rx "module load app_audiosocket.so"

# Port 9092 (AVA AudioSocket Server)
ss -tlnp | grep 9092
# Falls nichts: AVA laeuft nicht oder Port falsch konfiguriert

# AVA neu starten
systemctl restart ava-agent
sleep 3
ss -tlnp | grep 9092

# extensions.conf AudioSocket-Eintrag prüfen
grep -A 5 "AudioSocket" /etc/asterisk/extensions.conf
# Muss auf 127.0.0.1:9092 zeigen
```

---

### Problem 3: Sipgate SIP nicht registriert

**Symptom:** `asterisk -rx "pjsip show registrations"` zeigt "Unregistered" oder kein Eintrag

**Loesungen:**
```bash
# Registrierungsstatus detailliert
asterisk -rx "pjsip show registrations"

# PJSIP Debug aktivieren
asterisk -rx "pjsip set logger on"
asterisk -rx "module reload res_pjsip.so"
tail -f /var/log/asterisk/full | grep -E "pjsip|SIP|sipgate"

# Haufige Ursachen:
# - Falsches SIP-Passwort in pjsip.conf
# - Sipgate-Account gesperrt (Guthaben)
# - Firewall blockiert Port 5060 (UDP)

# UDP Port 5060 prüfen
ss -ulnp | grep 5060

# Firewall prüfen (falls UFW)
ufw status | grep 5060
```

---

### Problem 4: OpenClaw antwortet nicht / Timeout

**Symptom:** AVA-Log zeigt "Connection refused" oder "Timeout" bei Port 18789

**Loesungen:**
```bash
# OpenClaw-Status
systemctl status openclaw

# OpenClaw manuell testen
curl -s http://127.0.0.1:18789/v1/models
# Falls Fehler: OpenClaw neu starten

systemctl restart openclaw
sleep 5
curl -s http://127.0.0.1:18789/v1/models | python3 -m json.tool

# Anthropic API Key prüfen
grep ANTHROPIC_API_KEY /opt/ava/.env  # Oder OpenClaw-Config
# Key muss mit sk-ant-api03-... beginnen

# OpenClaw-Logs auf Fehler prüfen
journalctl -u openclaw -n 50 | grep -E "ERROR|error|failed|refused"
```

---

### Problem 5: AMD erkennt immer NOTSURE

**Symptom:** In Logs erscheint "AMD: NOTSURE" für fast alle Calls

**Loesungen:**
```bash
# AMD-Parameter lockern
nano /etc/asterisk/amd.conf
# total_analysis_time auf 6000 erhöhen
# initial_silence auf 3000 erhöhen

asterisk -rx "module reload app_amd.so"

# AMD mit hohem Verbose testen
asterisk -rx "core set verbose 5"
# Naechsten Call starten und Ausgabe beobachten
tail -f /var/log/asterisk/full | grep AMD
```

---

### Problem 6: TTS (ElevenLabs) schlaegt fehl — kein Audio

**Symptom:** Call verbindet, Ava "spricht" aber Lead hoert nichts

**Loesungen:**
```bash
# ElevenLabs API-Key prüfen
curl -X POST "https://api.elevenlabs.io/v1/text-to-speech/EXAVITQu4vr4xnSDxMaL" \
  -H "xi-api-key: $(grep ELEVENLABS_API_KEY /opt/ava/.env | cut -d= -f2)" \
  -H "Content-Type: application/json" \
  -d '{"text":"Test","model_id":"eleven_multilingual_v2"}' \
  -o /tmp/test-tts.mp3
ls -lh /tmp/test-tts.mp3  # Muss > 0 Bytes sein

# Falls ElevenLabs down: Fallback auf Azure TTS
# In /opt/ava/config.yaml:
# tts:
#   provider: azure
#   voice_name: de-DE-KatjaNeural

# AVA neu starten nach Config-Aenderung
systemctl restart ava-agent
```

---

### Problem 7: STT (Whisper) sehr langsam — Gesprächslatenz hoch

**Symptom:** Ava antwortet erst nach 5+ Sekunden auf jede Aussage des Leads

**Loesungen:**
```bash
# Whisper-Modell wechseln (in config.yaml)
# Aktuell: large-v3 (langsam, genau)
# Schneller: base oder small (weniger genau, aber schnell)
nano /opt/ava/config.yaml
# stt:
#   model: base         # Statt large-v3

# Falls GPU vorhanden: Whisper GPU-Nutzung prüfen
python3 -c "import torch; print(torch.cuda.is_available())"
# True = GPU vorhanden und nutzbar

# Alternative: Deepgram statt Whisper
# stt:
#   provider: deepgram
#   model: nova-2
# Deutlich schneller, kostet aber $0.01/min

systemctl restart ava-agent
```

---

### Problem 8: Kampagne laeuft nicht durch — Script haengt

**Symptom:** `batch-campaign.sh` laeuft an, macht keine weiteren Calls nach dem ersten

**Loesungen:**
```bash
# Script-Prozess prüfen
ps aux | grep batch-campaign
# Falls "D" State (Disk-Wait) oder kein Output: haengt

# Logs des Scripts prüfen
cat /var/log/ava/campaign-*.log | tail -30

# Haeufige Ursachen:
# - AMI-Verbindung bricht ab (AMI-Timeout in manager.conf)
# - CSV-Format falsch (fehlende Spalten, falsche Encoding)
# - Rate-Limiting: Zu schnelle Call-Initiierung

# AMI-Verbindung prüfen
echo "Action: Ping\r\n\r\n" | nc -q 1 127.0.0.1 5038

# CSV-Format prüfen
head -3 /path/to/leads.csv
# Erwartet: name,phone,language,job_title
file /path/to/leads.csv  # Sollte UTF-8 sein
```

---

### Problem 9: Hohe Fehlerrate bei deutschen Mobilnummern

**Symptom:** Calls zu +4915x oder +4916x schlagen haeufig fehl oder werden sofort abgelehnt

**Loesungen:**
```bash
# Sipgate-Konto: Auslandsoptionen / Mobilnummern freigeschaltet?
# -> Sipgate-Portal prüfen: Einstellungen > Dienstmerkmale > Mobilnummern

# Telnyx: Caller-ID für Mobilnummern validiert?
# -> Telnyx-Portal: Numbers > Phone Numbers > Regulatory

# Asterisk: Caller-ID korrekt gesetzt?
asterisk -rx "dialplan show ava-outbound"
# Caller-ID muss gültige DE-Nummer sein

# E.164-Format prüfen
# Richtig: +49176XXXXXXXX
# Falsch: 0176XXXXXXXX oder 0049176XXXXXXXX
```

---

### Problem 10: Ava spricht Englisch statt Deutsch

**Symptom:** TTS-Ausgabe kommt auf Englisch, obwohl Lead DE-Profil hat

**Loesungen:**
```bash
# System-Prompt in OpenClaw prüfen
# Ava-Agent-Config -> system_prompt muss explizit enthalten:
# "Du sprichst ausschliesslich auf Deutsch..."

# Lead-Metadata beim Call-Start prüfen
grep "language" /var/log/ava/agent.log | tail -20
# Muss "de" uebergeben werden

# ElevenLabs Voice-ID prüfen
# Nicht alle Voices unterstützen Deutsch gleichwertig
# Empfohlene DE-Voice: Verwende eleven_multilingual_v2 Model

# AVA-Config prüfen
grep -A 5 "language" /opt/ava/config.yaml
```

---

### Problem 11: Memory-Speicherung nach Gesprach schlaegt fehl

**Symptom:** Gesprächs-Outcomes werden nicht in mem0/Supermemory gespeichert

**Loesungen:**
```bash
# mem0-Service prüfen (SSH-Tunnel zum CCT-Server)
curl -s http://localhost:8002/health
# Muss: {"status": "ok"} oder ähnlich zurückgeben

# SSH-Tunnel zum CCT-Server aktiv?
ss -tlnp | grep 8002
# Falls nicht: cct-tunnels alias ausfuehren

# OpenClaw mem0-Integration prüfen
cat ~/.openclaw/agents/ava/agent/tools.json | python3 -m json.tool
# Memory-Tool muss konfiguriert sein

# AVA-Log auf Memory-Fehler
grep -i "memory\|mem0\|supermemory" /var/log/ava/agent.log | tail -20
```

---

### Problem 12: Zu viele parallele Calls — Asterisk überlastet

**Symptom:** Calls schlagen fehl ab einer bestimmten Gleichzeitigkeit, Asterisk-CPU > 90%

**Loesungen:**
```bash
# Aktive Kanäle prüfen
asterisk -rx "core show calls"
asterisk -rx "core show channels" | wc -l

# Asterisk-Ressourcen
top -p $(pgrep asterisk)

# Max-Channels in Asterisk begrenzen (falls noch nicht konfiguriert)
# In /etc/asterisk/asterisk.conf:
# maxcalls = 10     ; Absolute Obergrenze

# Kampagnen-Concurrency reduzieren
# In batch-campaign.sh: --max-concurrent 2 statt 5

# Whisper-CPU-Last wenn viele gleichzeitige STT-Anfragen
# -> Deepgram-API statt lokalem Whisper bei hohem Volumen
```
