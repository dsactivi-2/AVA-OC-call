# Kostenanalyse — AVA + Asterisk + OpenClaw AI-Callcenter
## Stand: 2026

---

## Infrastrukturkosten (Einmalig und Laufend)

### Server-Optionen

Dieser Stack kann vollstaendig lokal (auf vorhandener Hardware) oder auf einem dedizierten Server betrieben werden.

#### Option A: Lokal (Mac/Linux-Rechner, bereits vorhanden)
| Posten | Kosten |
|--------|--------|
| Hardware | $0 (vorhanden) |
| Strom/Betrieb | ~EUR 5-15/Monat |
| Internet (feste IP oder DynDNS) | ~EUR 0-5/Monat (meist im Paket) |
| **Summe lokal** | **~EUR 5-20/Monat** |

Einschraenkung: Kein Betrieb 24/7 ohne dedizierte Hardware. Fuer Tages-Kampagnen (8-18 Uhr) vollkommen ausreichend.

#### Option B: Hetzner Cloud (empfohlen fuer Produktion)
| Server-Typ | vCPU | RAM | Preis/Monat | Einsatz |
|-----------|------|-----|-------------|---------|
| CX22 | 2 vCPU | 4 GB | EUR 3.79 | Test/Pilot (kein Whisper large) |
| CX32 | 4 vCPU | 8 GB | EUR 6.80 | Whisper base, bis 5 parallele Calls |
| CX42 | 8 vCPU | 16 GB | EUR 16.40 | Whisper large-v3, bis 10 parallele Calls |
| CX52 | 16 vCPU | 32 GB | EUR 32.40 | Whisper + GPU, 20+ parallele Calls |

> **Hinweis:** Preise guenstiger als urspruenglich berechnet — Stack noch wirtschaftlicher.

**Empfehlung Step2Job Pilot:** CX32 (~EUR 6.80/Monat) ausreichend fuer bis zu 500 Calls/Monat.

#### Option C: DigitalOcean / Contabo (Alternativen)
| Anbieter | Vergleichbarer Plan | Preis/Monat |
|----------|---------------------|-------------|
| DigitalOcean | 4 vCPU, 8 GB | USD 48 |
| Contabo | VPS S | EUR 6.99 |
| Hetzner | CX32 | EUR 6.80 |

**Hetzner ist klarer Sieger fuer DE-basierte Infrastruktur** (DE-Datenschutz, DE-Netzwerk = niedrige Latenz zu Sipgate).

---

## Sipgate-Telefoniekosten (Variante: Eigener SIP Trunk)

Der groesste Kostenvorteil dieses Stacks gegenueber Vapi: **Sipgate-Flatrate bedeutet $0 Telefoniekosten**.

| Leistung | Preis | Details |
|----------|-------|---------|
| Sipgate Team — Festnetz-Flatrate DE | EUR 0/min | In Sipgate-Paket enthalten |
| Sipgate — DE Mobil | EUR 0.016/min | Nicht in Flatrate, gesondert abgerechnet |
| Sipgate — Ausland (BA/RS/HR) | EUR 0.020-0.040/min | Je nach Land |
| Sipgate Grundgebuehr (vorhanden) | EUR 0 zusaetzlich | Account bereits aktiv |

**Wichtig:** Bei ausschliesslich deutschen Festnetznummern (typisch fuer Step2Job B2B-Leads) entstehen KEINE Telefonie-Kosten ausserhalb des bestehenden Vertrags.

Bei Mobilnummern-Anteil von 80% (typisch fuer Arbeitssuchende):
- 80% Mobile: EUR 0.016/min
- 20% Festnetz: EUR 0/min
- Gewichteter Durchschnitt: ~EUR 0.013/min

---

## STT-Kosten

### Whisper Lokal ($0)

```
Kosten: $0.00/Minute
Voraussetzung: Server mit mindestens 4 GB RAM fuer Whisper base
             8 GB RAM fuer Whisper large-v3
Latenz: 1-3 Sekunden (base) / 3-8 Sekunden (large-v3)
Qualitaet: Sehr gut, speziell fuer Deutsch optimiert
Privacy: 100% lokal, keine Daten verlassen den Server
```

**Empfehlung:** Whisper `large-v3` fuer hohe Genauigkeit, `base` wenn Latenz kritisch.

### Deepgram API (kostenpflichtig)

| Plan | Preis/Minute | Details |
|------|-------------|---------|
| Pay-as-you-go | $0.0058/min | Nova-2, Echtzeit-Streaming |
| Growth Plan   | $0.0047/min | Ab $4.000/Jahr |
| Enterprise | Verhandlungsbasis | Ab 1.000h/Monat |

Deepgram-Latenz: < 300ms (deutlich schneller als lokaler Whisper).
Kosten pro 10-Minuten-Gespräch: ~$0.058.

### Vergleich STT-Optionen

| Option | Kosten/Min | Kosten/1000 Calls (10min) | Latenz | Datenschutz |
|--------|-----------|---------------------------|--------|-------------|
| Whisper lokal (base) | $0.00 | $0.00 | 1-3s | 100% lokal |
| Whisper lokal (large-v3) | $0.00 | $0.00 | 3-8s | 100% lokal |
| Deepgram Nova-2 | $0.0058 | $58.00 | <0.3s | Deepgram-Server |
| Google Speech-to-Text | ~$0.016 | $160.00 | <0.5s | Google Cloud |

**Empfehlung:** Whisper lokal fuer Datenschutz und Kosten. Deepgram wenn Latenz < 500ms kritisch.

---

## TTS-Kosten

### ElevenLabs

ElevenLabs berechnet nach Zeichen (Characters), nicht nach Minuten.

| Plan | Preis/Monat | Zeichen/Monat | USD/1000 Zeichen |
|------|-------------|---------------|-----------------|
| Free | $0 | 10.000 | $0 (begrenzt) |
| Starter | $5 | 30.000 | $0.167 |
| Creator | $22 | 100.000 | $0.220 |
| Pro | $99 | 500.000 | $0.198 |
| Scale | $330 | 2.000.000 | $0.165 |

**Schaetzung pro 10-Minuten-Gespräch (Ava spricht ~50% der Zeit):**
- 5 Minuten TTS-Ausgabe ≈ 750 Wörter ≈ 4.500 Zeichen
- Creator-Plan: 4.500 × $0.00022 = **$0.00099 pro Gespräch**

Bei 1.000 Calls/Monat (10 Min): 4.500.000 Zeichen → Scale-Plan ($330) oder Pay-per-use via API.

### Azure Cognitive Services TTS

| Stufe | Preis | Details |
|-------|-------|---------|
| Free | 0-500.000 Zeichen/Monat | Standard-Stimmen |
| Standard | $4.00 / 1 Million Zeichen | Standard-Stimmen |
| Neural | $16.00 / 1 Million Zeichen | Neural-Stimmen (de-DE-KatjaNeural) |

**Schaetzung pro 10-Minuten-Gespräch (Neural):**
- 4.500 Zeichen × $0.000016 = **$0.000072 pro Gespräch**

Azure Neural TTS ist deutlich guenstiger als ElevenLabs bei vergleichbarer Qualitaet fuer Deutsch.

### Coqui / Piper TTS Lokal ($0)

```
Kosten: $0.00
Qualitaet: Befriedigend bis gut (schlechter als ElevenLabs/Azure)
Latenz: < 500ms bei guter Hardware
Datenschutz: 100% lokal
```

Geeignet fuer Voicemail-Nachrichten oder Notfall-Fallback. Fuer direkte Gespraeche mit Leads nicht ideal.

### Vergleich TTS-Optionen (pro 1.000 Calls, 10 Min)

| Option | Kosten/1000 Calls | Qualitaet | Datenschutz |
|--------|-------------------|-----------|-------------|
| Coqui/Piper lokal | $0.00 | Befriedigend | 100% lokal |
| Azure Neural TTS | $0.072 | Sehr gut (natuerlich) | Azure EU |
| ElevenLabs Creator | $0.99 | Ausgezeichnet | ElevenLabs |
| ElevenLabs Scale | $0.74 | Ausgezeichnet | ElevenLabs |

---

## LLM-Kosten: Claude claude-sonnet-4-6 via OpenClaw

### Preismodell Anthropic (Stand 2026)

| Modell | Input | Output |
|--------|-------|--------|
| claude-sonnet-4-6 | $3.00 / 1M Tokens | $15.00 / 1M Tokens |
| claude-haiku-3-5 | $0.25 / 1M Tokens | $1.25 / 1M Tokens |

### Token-Verbrauch pro Gespräch (Schaetzung)

**10-Minuten-Gespräch, 12 Turns (Ava + Lead abwechselnd):**

| Komponente | Input Tokens | Output Tokens |
|------------|-------------|--------------|
| System-Prompt (einmalig) | 600 | - |
| Lead-Kontext (Metadata) | 150 | - |
| Gespräch Turn 1-12 (akkumuliert) | 2.400 | - |
| Ava-Antworten (12 Turns) | - | 1.800 |
| Memory-Kontext (falls vorhanden) | 300 | - |
| Outcome-Klassifikation | 200 | 100 |
| **Gesamt** | **3.650** | **1.900** |

### LLM-Kosten pro Gespräch

```
Input:  3.650 Tokens × $3.00 / 1.000.000  = $0.01095
Output: 1.900 Tokens × $15.00 / 1.000.000 = $0.02850
Gesamt (Sonnet):                           = $0.03945 ≈ $0.040

Mit Claude Haiku (Budget-Option):
Input:  3.650 × $0.25 / 1.000.000 = $0.00091
Output: 1.900 × $1.25 / 1.000.000 = $0.00238
Gesamt (Haiku):                     ≈ $0.003
```

**Ersparnis Haiku vs. Sonnet: ~92%** bei LLM-Kosten. Haiku fuer strukturierte Qualifizierungsgespraeche ausreichend.

---

## Gesamtkosten pro Monat — Szenarien

### Basis-Konfiguration fuer Berechnung

| Konfiguration | Wert |
|---------------|------|
| Durchschn. Gesprächsdauer | 10 Minuten |
| STT | Whisper lokal ($0) |
| TTS | Azure Neural ($0.000072/Gespräch) |
| LLM | claude-sonnet-4-6 ($0.040/Gespräch) |
| Telefonie | Sipgate Flatrate DE Festnetz ($0) |
| Server | Hetzner CX32 (EUR 6.80/Monat) |

### Szenario 1: Pilot (100 Calls/Monat)

| Posten | Berechnung | Kosten |
|--------|-----------|--------|
| Hetzner CX32 | Fixkosten | EUR 6.80 |
| Sipgate | Bereits vorhanden | EUR 0 |
| STT Whisper | $0/min × 1.000 min | $0.00 |
| TTS Azure Neural | $0.000072 × 100 | $0.007 |
| LLM claude-sonnet-4-6 | $0.040 × 100 | $4.00 |
| **Gesamt** | | **~EUR 6.80 + $4** |
| **In EUR** | | **≈ EUR 11/Monat** |
| **Pro Gespräch** | | **~EUR 0.11** |

### Szenario 2: Aktiv (500 Calls/Monat)

| Posten | Berechnung | Kosten |
|--------|-----------|--------|
| Hetzner CX32 | Fixkosten | EUR 6.80 |
| STT Whisper | $0 | $0.00 |
| TTS Azure Neural | $0.000072 × 500 | $0.036 |
| LLM claude-sonnet-4-6 | $0.040 × 500 | $20.00 |
| **Gesamt** | | **EUR 6.80 + $20** |
| **In EUR** | | **≈ EUR 26/Monat** |
| **Pro Gespräch** | | **~EUR 0.05** |

### Szenario 3: Skaliert (1.000 Calls/Monat)

| Posten | Berechnung | Kosten |
|--------|-----------|--------|
| Hetzner CX42 (mehr RAM fuer Whisper large) | Fixkosten | EUR 16.40 |
| STT Whisper | $0 | $0.00 |
| TTS ElevenLabs Creator | $22/Monat (100k Zeichen) | $22.00 |
| LLM claude-sonnet-4-6 | $0.040 × 1.000 | $40.00 |
| **Gesamt** | | **EUR 16.40 + $62** |
| **In EUR** | | **≈ EUR 74/Monat** |
| **Pro Gespräch** | | **~EUR 0.07** |

### Szenario 4: Enterprise (5.000 Calls/Monat)

| Posten | Berechnung | Kosten |
|--------|-----------|--------|
| Hetzner CX52 + CX42 (2 Server) | Fixkosten | EUR 49 |
| STT Deepgram (Latenz-kritisch) | $0.0058 × 50.000 min | $290.00 |
| TTS ElevenLabs Scale | $330/Monat (2M Zeichen) | $330.00 |
| LLM claude-sonnet-4-6 | $0.040 × 5.000 | $200.00 |
| **Gesamt** | | **EUR 49 + $820** |
| **In EUR** | | **≈ EUR 816/Monat** |
| **Pro Gespräch** | | **~EUR 0.16** |

---

## Vergleich: AVA+Asterisk vs. Vapi-Stack

### Kostenvergleich bei verschiedenen Volumina

| Calls/Monat | AVA+Asterisk (Whisper+Azure) | Vapi+Sipgate (Deepgram+native TTS) | Ersparnis AVA |
|-------------|------------------------------|-------------------------------------|---------------|
| 100 | ~EUR 11 | ~$93 (~EUR 86) | **EUR 75 (87%)** |
| 500 | ~EUR 26 | ~$466 (~EUR 433) | **EUR 407 (94%)** |
| 1.000 | ~EUR 74 | ~$932 (~EUR 865) | **EUR 791 (91%)** |
| 5.000 | ~EUR 816 | ~$4.660 (~EUR 4.330) | **EUR 3.514 (81%)** |

**Fazit:** AVA+Asterisk ist bei allen Volumina massiv guenstiger als Vapi. Der Hauptgrund: Keine Vapi-Plattformgebuehr ($0.05/min) und Sipgate-Flatrate fuer Telefonie.

### Qualitative Unterschiede

| Kriterium | AVA+Asterisk | Vapi |
|-----------|-------------|------|
| Setup-Aufwand | Mittel (2-4h) | Gering (30min) |
| Wartungsaufwand | Mittel (Updates, Monitoring) | Gering (managed) |
| Datenschutz | Sehr hoch (lokal) | Mittel (Vapi-Server USA) |
| Debugging | Vollständig (Asterisk CLI) | Eingeschränkt |
| Skalierung | Sehr hoch (Asterisk 100+ Kanäle) | Hoch (Vapi-Limits) |
| AMD-Kontrolle | Vollständig (amd.conf) | Begrenzt (Vapi-Parameter) |
| Vendor Lock-in | Kein | Mittel (Vapi-API) |
| DSGVO | Vollständig (DE) | Bedingt (US-Server) |

---

## Empfehlung: Ab wann welcher Stack?

### Wähle AVA+Asterisk wenn:
- Asterisk bereits vorhanden und konfiguriert (wie bei Denis)
- Datenschutz / DSGVO-Konformität hohe Priorität
- Langfristiger Betrieb mit > 200 Calls/Monat geplant
- Vollständige Kontrolle über alle Stack-Komponenten gewuenscht
- Budget-Optimierung wichtig (bis zu 93% günstiger als Vapi)
- Debugging und Fehleranalyse auf Infrastruktur-Ebene benoetigt

### Wähle Vapi wenn:
- Schnellstmöglich produktiv (heute noch live)
- Keine eigene Infrastruktur verfuegbar
- Volumen unter 100 Calls/Monat (Setup-Aufwand vs. Ersparnis nicht lohnenswert)
- Team ohne Asterisk/Linux-Kenntnisse
- Managed-Service bevorzugt (kein Ops-Aufwand)

### Hybrid-Empfehlung fuer Step2Job:
**Start mit Vapi** (Variante A, Sipgate) zur schnellen Validierung der Kampagnen-Logik und des Gesprächs-Skripts. **Migration zu AVA+Asterisk** nach erfolgreicher Pilotphase (200+ Calls). Der Asterisk-Stack ist bereits vorhanden — Migration erfordert nur die AVA-Installation und Anpassung des Dialplans.

**Break-even der Migration:** Nach ca. 300 Calls (einmalige Setup-Zeit ~4h amortisiert sich nach < 1 Monat durch Kosteneinsparung).

---

## Kostenoptimierungs-Pfad nach Volumen

| Phase | Calls/Monat | Empfohlene Konfiguration | Monatliche Kosten |
|-------|-------------|--------------------------|-------------------|
| Pilot | 0-100 | AVA lokal + Whisper base + Azure TTS + Sonnet | ~EUR 11 |
| Aktiv | 100-500 | Hetzner CX32 + Whisper base + Azure TTS + Haiku | ~EUR 15 |
| Wachstum | 500-2.000 | Hetzner CX42 + Whisper large + Azure TTS + Sonnet (priority) / Haiku (mass) | ~EUR 40-70 |
| Scale | 2.000-10.000 | 2x Hetzner CX52 + Deepgram + ElevenLabs Scale + Sonnet | ~EUR 350-750 |
