# Setup-Anleitung — AVA + Asterisk + OpenClaw

## Voraussetzungen (Checkliste)

Folgendes ist bereits vorhanden:
- [x] Asterisk PBX laeuft (Version 20.x oder hoeher)
- [x] Sipgate SIP Trunk konfiguriert und aktiv
- [x] OpenClaw auf Port 18789 aktiv mit Agent "Ava"
- [x] Python 3.11+ installiert
- [x] Git installiert
- [ ] app_audiosocket.so in Asterisk geladen
- [ ] ARI in Asterisk aktiviert
- [ ] AMI in Asterisk aktiviert

Verifikation der bestehenden Asterisk-Module:
```bash
asterisk -rx "module show like audiosocket"
asterisk -rx "module show like ari"
asterisk -rx "module show like amd"
```
Erwartete Ausgabe: Alle drei Module mit Status "Running"

---

## Schritt 1: AVA AI Voice Agent installieren

### 1.1 Repository clonen
```bash
cd /opt
git clone https://github.com/hkjarral/AVA-AI-Voice-Agent-for-Asterisk.git ava
cd /opt/ava
```

Verifikation:
```bash
ls /opt/ava/
# Erwartet: main.py, requirements.txt, config/, etc.
```

> **Wichtig: config.yaml-Format nach Clone abgleichen**
> Das Blueprint `config.yaml` dient als Referenz. Nach `git clone` die tatsaechliche
> `config/ai-agent.yaml` des AVA-Repos pruefen und Konfigurationsschluessel ggf. anpassen.
> Offizielle Config-Referenz: https://github.com/hkjarral/Asterisk-AI-Voice-Agent/blob/main/docs/Configuration-Reference.md

### 1.2 Python-Environment erstellen
```bash
python3 -m venv /opt/ava/venv
source /opt/ava/venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

Verifikation:
```bash
/opt/ava/venv/bin/python -c "import asyncio; import aiohttp; print('OK')"
```

### 1.3 Whisper installieren (STT, lokal)
```bash
source /opt/ava/venv/bin/activate
pip install openai-whisper
# GPU-Variante (wenn NVIDIA GPU vorhanden):
pip install openai-whisper torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
```

Verifikation:
```bash
/opt/ava/venv/bin/python -c "import whisper; m = whisper.load_model('base'); print('Whisper OK')"
```

---

## Schritt 2: Asterisk ARI konfigurieren

### 2.1 ari.conf anlegen/aktualisieren
Datei: `/etc/asterisk/ari.conf` (Inhalt aus `asterisk-configs/ari.conf`)

```bash
cp /etc/asterisk/ari.conf /etc/asterisk/ari.conf.backup.$(date +%Y%m%d)
cp /opt/ava-asterisk-openclaw/asterisk-configs/ari.conf /etc/asterisk/ari.conf
```

Verifikation:
```bash
asterisk -rx "module reload res_ari.so"
asterisk -rx "ari show status"
# Erwartet: ARI status: Enabled
```

### 2.2 extensions.conf aktualisieren
```bash
cp /etc/asterisk/extensions.conf /etc/asterisk/extensions.conf.backup.$(date +%Y%m%d)
# Inhalte aus asterisk-configs/extensions.conf in bestehende Datei integrieren
# WICHTIG: Bestehende Konfiguration NICHT ueberschreiben, nur neue Contexts ergaenzen
```

Die neuen Contexts aus `asterisk-configs/extensions.conf` ans Ende der bestehenden Datei anhaengen:
```bash
cat /opt/ava-asterisk-openclaw/asterisk-configs/extensions.conf >> /etc/asterisk/extensions.conf
asterisk -rx "dialplan reload"
```

Verifikation:
```bash
asterisk -rx "dialplan show ava-outbound"
# Erwartet: Context 'ava-outbound' wird angezeigt
asterisk -rx "dialplan show ava-inbound"
```

### 2.3 manager.conf aktualisieren
```bash
cp /etc/asterisk/manager.conf /etc/asterisk/manager.conf.backup.$(date +%Y%m%d)
# AMI-User fuer AVA ergaenzen (nicht ersetzen):
cat /opt/ava-asterisk-openclaw/asterisk-configs/manager.conf >> /etc/asterisk/manager.conf
asterisk -rx "module reload manager"
```

Verifikation:
```bash
asterisk -rx "manager show users"
# Erwartet: ava-bot User in der Liste
```

---

## Schritt 3: AudioSocket konfigurieren

AudioSocket erlaubt bidirektionales Audio-Streaming von Asterisk zu AVA ueber TCP.

### 3.1 Module pruefen und laden
```bash
asterisk -rx "module show like audiosocket"
# Falls nicht geladen:
asterisk -rx "module load app_audiosocket.so"
```

### 3.2 AudioSocket-Port freigeben (lokal only)
AudioSocket laeuft auf TCP Port 9092 (konfiguriert in AVA config.yaml).
Da beide Dienste auf demselben Server laufen, kein Firewall-Eintrag noetig.

Verifikation (nach AVA-Start):
```bash
ss -tlnp | grep 9092
# Erwartet: LISTEN 0.0.0.0:9092 python3
```

---

## Schritt 4: AVA konfigurieren (OpenClaw als LLM-Backend)

### 4.1 Konfigurationsdatei erstellen
```bash
cp /opt/ava-asterisk-openclaw/ava-configs/config.yaml /opt/ava/config.yaml
cp /opt/ava-asterisk-openclaw/ava-configs/.env.example /opt/ava/.env
```

### 4.2 .env-Datei befuellen
```bash
nano /opt/ava/.env
```

Folgende Werte setzen (Details in ava-configs/.env.example):
- `OPENCLAW_API_URL=http://127.0.0.1:18789`
- `OPENCLAW_API_KEY=` (leer lassen wenn kein Key konfiguriert)
- `ASTERISK_ARI_URL=http://127.0.0.1:8088`
- `ASTERISK_ARI_USER=ava-bot`
- `ASTERISK_ARI_PASSWORD=ava-secret-2024`
- `ELEVENLABS_API_KEY=` (dein Key)
- `DEEPGRAM_API_KEY=` (optional, wenn Deepgram statt Whisper)

Verifikation:
```bash
grep -c "=" /opt/ava/.env
# Erwartet: 10 oder mehr Zeilen
```

---

## Schritt 5: STT konfigurieren

### Option A: Whisper lokal (empfohlen fuer Datenschutz, $0 Kosten)
In `/opt/ava/config.yaml`:
```yaml
stt:
  provider: whisper
  model: large-v3
  language: de
```

Modell vorher herunterladen:
```bash
source /opt/ava/venv/bin/activate
python -c "import whisper; whisper.load_model('large-v3')"
# Download: ~3GB, einmalig
```

Verifikation:
```bash
ls ~/.cache/whisper/
# Erwartet: large-v3.pt (ca. 3GB)
```

### Option B: Deepgram API (schneller, aber kostenpflichtig)
In `/opt/ava/config.yaml`:
```yaml
stt:
  provider: deepgram
  model: nova-2
  language: de
```

Und in `.env`:
```
DEEPGRAM_API_KEY=dein-deepgram-key
```

---

## Schritt 6: TTS konfigurieren

### Option A: ElevenLabs (empfohlen fuer natuerliche Stimme)
In `/opt/ava/config.yaml`:
```yaml
tts:
  provider: elevenlabs
  voice_id: "21m00Tcm4TlvDq8ikWAM"  # Rachel (Deutsch-kompatibel)
  model: eleven_multilingual_v2
```

Und in `.env`:
```
ELEVENLABS_API_KEY=dein-elevenlabs-key
```

Verifikation (Test-Request):
```bash
curl -X POST "https://api.elevenlabs.io/v1/text-to-speech/21m00Tcm4TlvDq8ikWAM" \
  -H "xi-api-key: $ELEVENLABS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"text":"Hallo, hier ist Ava.","model_id":"eleven_multilingual_v2"}' \
  --output /tmp/test-tts.mp3 && echo "TTS OK" && ls -lh /tmp/test-tts.mp3
```

### Option B: Azure Cognitive Services TTS
In `/opt/ava/config.yaml`:
```yaml
tts:
  provider: azure
  voice_name: de-DE-KatjaNeural
  region: westeurope
```

---

## Schritt 7: AMD in Asterisk aktivieren

### 7.1 amd.conf pruefen
```bash
cp /opt/ava-asterisk-openclaw/asterisk-configs/amd.conf /etc/asterisk/amd.conf
asterisk -rx "module reload app_amd.so"
```

Verifikation:
```bash
asterisk -rx "module show like amd"
# Erwartet: app_amd.so   Answering Machine Detection   Running
```

### 7.2 AMD im Dialplan einsetzen (bereits in extensions.conf enthalten)
Der Outbound-Context ruft AMD() automatisch auf. Keine weiteren Schritte noetig.

AMD-Tuning (nach ersten Test-Calls anpassen):
```bash
# Wichtige AMD-Parameter (in amd.conf):
# initial_silence: Max. Stille vor erstem Ton (ms)
# greeting:        Max. Laenge einer menschlichen Begruessung (ms)
# after_greeting_silence: Stille nach Begruessung = Anrufbeantworter-Signal
# total_analysis_time: Maximale AMD-Analysezeit (ms)
```

---

## Schritt 8: Outbound-Call-Script einrichten

```bash
cp /opt/ava-asterisk-openclaw/scripts/outbound-call.sh /usr/local/bin/outbound-call.sh
chmod +x /usr/local/bin/outbound-call.sh
```

Verifikation:
```bash
/usr/local/bin/outbound-call.sh --help
# Erwartet: Usage-Text
```

---

## Schritt 9: Batch-Campaign-Script einrichten

```bash
cp /opt/ava-asterisk-openclaw/scripts/batch-campaign.sh /usr/local/bin/batch-campaign.sh
chmod +x /usr/local/bin/batch-campaign.sh
```

Test-CSV erstellen:
```bash
cat > /tmp/test-leads.csv << 'EOF'
name,phone,language,job_title
Max Mustermann,+4917612345678,de,Lagermitarbeiter
Amir Bobic,+4917698765432,bs,Fahrer
EOF
```

---

## Schritt 10: AVA starten

### 10.1 Manueller Start (Test)
```bash
cd /opt/ava
source venv/bin/activate
python main.py --config config.yaml
```

Erwartete Ausgabe:
```
[AVA] AudioSocket Server listening on 0.0.0.0:9092
[AVA] Connecting to Asterisk ARI at ws://127.0.0.1:8088/ari/events
[AVA] Connected to ARI. Waiting for calls...
```

### 10.2 Systemd-Service einrichten
```bash
cat > /etc/systemd/system/ava-agent.service << 'EOF'
[Unit]
Description=AVA AI Voice Agent
After=network.target asterisk.service
Requires=asterisk.service

[Service]
Type=simple
User=asterisk
WorkingDirectory=/opt/ava
ExecStart=/opt/ava/venv/bin/python main.py --config config.yaml
Restart=on-failure
RestartSec=5
EnvironmentFile=/opt/ava/.env

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ava-agent
systemctl start ava-agent
```

Verifikation:
```bash
systemctl status ava-agent
# Erwartet: active (running)
journalctl -u ava-agent -f
```

---

## Schritt 11: Test-Call durchfuehren

### 11.1 Einzelner Test-Call (eigene Nummer)
```bash
/usr/local/bin/outbound-call.sh \
  --number "+4917600000000" \
  --lead-name "Test User" \
  --language "de" \
  --campaign-id "test-001"
```

Beobachten in Asterisk:
```bash
asterisk -rx "channel show all"
asterisk -rx "core show calls"
```

### 11.2 AVA-Logs beobachten
```bash
journalctl -u ava-agent -f
# Oder:
tail -f /var/log/ava/agent.log
```

### 11.3 AMD testen
AMD gibt AMDSTATUS in den Asterisk-Logs aus:
```bash
asterisk -rx "core set verbose 5"
# Dann Call initiieren und beobachten:
# -- AMD: Channel xxx: HUMAN / MACHINE / NOTSURE
```

---

## Gesamtverifikation

```bash
# Health-Check ausfuehren
/usr/local/bin/health-check.sh

# Erwartet:
# [OK] Asterisk laeuft
# [OK] ARI erreichbar (Port 8088)
# [OK] AMI erreichbar (Port 5038)
# [OK] AVA laeuft (Port 9092)
# [OK] OpenClaw erreichbar (Port 18789)
# [OK] app_amd.so geladen
# [OK] app_audiosocket.so geladen
```
