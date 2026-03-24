# Workflows — AVA + Asterisk + OpenClaw AI-Callcenter
## Detaillierte Sequenzdiagramme aller Gesprächsabläufe

---

## 1. Outbound Lead-Calling (Komplettfluss)

Vom Kampagnen-Start über Asterisk-AMD bis zum abgeschlossenen Gespräch mit Ava.

```mermaid
sequenceDiagram
    participant CSV as leads.csv
    participant CAMP as batch-campaign.sh
    participant AMI as Asterisk AMI (Port 5038)
    participant AST as Asterisk PBX
    participant AMD as AMD Engine (app_amd.so)
    participant SIP as Sipgate SIP Trunk
    participant LEAD as Lead Telefon
    participant ARI as Asterisk ARI (Port 8088)
    participant AVA as AVA Voice Agent (Port 9092)
    participant AS as AudioSocket (TCP 9092)
    participant STT as Whisper / Deepgram
    participant OC as OpenClaw :18789
    participant AV as Ava (claude-sonnet-4-6)
    participant TTS as ElevenLabs / Azure TTS

    CSV->>CAMP: Zeile einlesen (name, phone, language, job_title)
    CAMP->>AMI: Action: Originate {Channel: PJSIP/sipgate-trunk, Exten: +49..., Context: ava-outbound}
    AMI->>AST: Call-Originierung ausführen
    AST->>SIP: SIP INVITE (from: Step2Job Nummer, to: Lead)
    SIP->>LEAD: PSTN-Anruf klingelt

    alt Lead nimmt ab
        LEAD->>SIP: SIP 200 OK
        SIP->>AST: RTP Audio-Stream verbunden
        AST->>AMD: AMD() aufrufen — Audio-Analyse startet
        Note over AMD: Analysiert erste 2-4 Sekunden Audio
        Note over AMD: Kriterien: Länge der Begrüssung, Stille, Ton-Pattern

        alt AMD: HUMAN erkannt
            AMD->>AST: AMDSTATUS=HUMAN
            AST->>ARI: StasisStart-Event (Channel mit AVA-App verbinden)
            ARI->>AVA: WebSocket-Event: channel.entered
            AVA->>AS: AudioSocket-Verbindung zu Asterisk aufbauen (TCP 9092)
            AS->>AVA: Audio-Stream bidirektional aktiv

            AVA->>OC: POST /v1/chat/completions {messages: [system_prompt, user: "call_started"], metadata: {lead_name, language, job_title}}
            OC->>AV: Route zu Ava-Agent, system_prompt + lead_context laden
            AV-->>OC: Begrüssungstext generieren ("Guten Tag Herr Mustermann...")
            OC-->>AVA: Text-Response (streaming)
            AVA->>TTS: Text an TTS senden
            TTS-->>AVA: Audio-Bytes (MP3/PCM)
            AVA->>AS: Audio-Bytes → Asterisk → Lead
            LEAD->>AS: Lead spricht (Audio-Eingang)
            AS->>AVA: Audio-Stream (rohe PCM-Daten)
            AVA->>STT: Audio-Chunk senden
            STT-->>AVA: Transkription ("Ja, hallo?")

            loop Gesprächsverlauf (N Turns)
                AVA->>OC: POST /v1/chat/completions {messages: [...history, user: transkription]}
                OC->>AV: Kontext + Gesprächshistorie übergeben
                AV-->>OC: Antwort (qualifizieren, fragen, reagieren)
                OC-->>AVA: Text-Response
                AVA->>TTS: Text → Audio
                TTS-->>AVA: Audio
                AVA->>AS: Audio → Lead
                LEAD->>AS: Antwort des Leads
                AS->>AVA: Audio
                AVA->>STT: Transkribieren
                STT-->>AVA: Text
            end

            AVA->>OC: Gespräch beenden (Outcome ermitteln)
            OC->>AV: Outcome-Klassifikation
            AV-->>OC: {outcome: "qualified", notes: "...", next_action: "appointment"}
            OC-->>AVA: Abschlusstext + Outcome
            AVA->>TTS: Verabschiedungstext
            TTS-->>AVA: Audio
            AVA->>AS: Audio → Lead
            AVA->>ARI: Hangup-Anweisung
            AST->>SIP: SIP BYE
            AVA->>CAMP: Webhook/Event: call.ended {outcome, duration, transcript}
            CAMP->>CSV: Lead-Status aktualisieren (qualified/callback/not-interested)

        else AMD: MACHINE erkannt
            Note over AST: Weiterleitung an Voicemail-Flow (siehe Diagramm 3)
        end

    else Lead nimmt nicht ab / Besetzt / Abgelehnt
        SIP->>AST: 486 Busy / 480 No Answer / 603 Decline
        AST->>AMI: Hangup-Event {cause: NO_ANSWER / BUSY / CONGESTION}
        AMI->>CAMP: Call-Ergebnis: no-answer / busy
        CAMP->>CAMP: Retry-Zeitpunkt berechnen und in Queue eintragen
    end
```

---

## 2. Inbound Call Flow

Ein Lead ruft auf der Step2Job-Nummer an — Ava antwortet automatisch.

```mermaid
sequenceDiagram
    participant LEAD as Lead (ruft an)
    participant SIP as Sipgate SIP Trunk
    participant AST as Asterisk PBX
    participant ARI as Asterisk ARI
    participant AVA as AVA Voice Agent
    participant AS as AudioSocket
    participant STT as Whisper / Deepgram
    participant OC as OpenClaw :18789
    participant AV as Ava (claude-sonnet-4-6)
    participant TTS as ElevenLabs / Azure TTS
    participant CRM as Step2Job CRM / Outcome-Log

    LEAD->>SIP: PSTN-Anruf an Step2Job-Nummer
    SIP->>AST: SIP INVITE (inbound)
    AST->>AST: Caller-ID extrahieren (+49...)
    AST->>AST: Dialplan-Routing: Context ava-inbound

    Note over AST: extensions.conf: exten => s,1,Stasis(ava-inbound)

    AST->>ARI: StasisStart-Event (Channel, Caller-ID)
    ARI->>AVA: WebSocket-Event: inbound call {callerId, channel_id}

    AVA->>OC: POST /v1/chat/completions {messages: [system_prompt, user: "inbound_call"], metadata: {callerId, context: "inbound"}}
    Note over OC,AV: Ava prüft ob Caller bekannt (Memory-Lookup)
    OC->>AV: Inbound-Kontext + evtl. bekannte Lead-Info
    AV-->>OC: Personalisierter oder generischer Begrüssungstext

    AVA->>AST: ARI: Answer-Befehl (Anruf annehmen)
    AST->>SIP: SIP 200 OK
    SIP->>LEAD: Verbindung hergestellt

    AVA->>AS: AudioSocket-Verbindung aufbauen
    OC-->>AVA: Begrüssungstext
    AVA->>TTS: Text → Audio
    TTS-->>AVA: Audio-Bytes
    AVA->>AS: Audio → Asterisk → Lead
    LEAD->>AS: "Hallo, ich rufe wegen..."

    loop Gesprächsverlauf
        AS->>AVA: Audio-Stream (Lead spricht)
        AVA->>STT: Transkription
        STT-->>AVA: Text
        AVA->>OC: POST /v1/chat/completions {history + neuer Input}
        OC->>AV: Antwort generieren

        alt Tool-Call: Termin vereinbaren
            AV->>OC: Tool-Call: schedule_appointment {lead_id, preferred_time}
            OC->>CRM: POST /api/appointments {lead_phone, time_slot}
            CRM-->>OC: Bestätigung {appointment_id, confirmed_time}
            OC->>AV: Termin bestätigt, Uhrzeit einfügen
            AV-->>OC: Bestätigungstext
        end

        alt Tool-Call: Rückruf planen
            AV->>OC: Tool-Call: schedule_callback {phone, time}
            OC->>CRM: Callback-Eintrag anlegen
            CRM-->>OC: OK
            AV-->>OC: Rückruf-Bestätigungstext
        end

        OC-->>AVA: Antwort-Text
        AVA->>TTS: Text → Audio
        TTS-->>AVA: Audio
        AVA->>AS: Audio → Lead
    end

    AVA->>ARI: Hangup nach Gesprächsende
    AVA->>CRM: Gespräch-Log {transcript, outcome, duration, callerId}
    AVA->>OC: Memory speichern (Lead-Infos, Outcome)
```

---

## 3. AMD: Voicemail erkannt

Was passiert wenn der Anrufbeantworter des Leads antwortet.

```mermaid
sequenceDiagram
    participant AST as Asterisk PBX
    participant AMD as AMD Engine (app_amd.so)
    participant SIP as Sipgate SIP Trunk
    participant LEAD as Lead (Anrufbeantworter)
    participant ARI as Asterisk ARI
    participant AVA as AVA Voice Agent
    participant OC as OpenClaw :18789
    participant AV as Ava (claude-sonnet-4-6)
    participant TTS as ElevenLabs / Azure TTS
    participant CAMP as Campaign Manager

    AST->>SIP: SIP INVITE (outbound call)
    SIP->>LEAD: PSTN klingelt
    LEAD->>SIP: SIP 200 OK (Anrufbeantworter nimmt ab)
    SIP->>AST: RTP Stream verbunden

    AST->>AMD: AMD() starten — Audio-Analyse
    Note over AMD: Begrüssungsansage erkannt: Länge > 1500ms
    Note over AMD: Stille nach Ansage (after_greeting_silence)
    Note over AMD: Charakteristische Ton-Muster einer Ansage

    AMD->>AST: AMDSTATUS=MACHINE, AMDCAUSE=LONG_GREETING

    AST->>AST: Dialplan-Branch: machineDetected

    alt Konfiguration: hangupOnMachine (Standard für hohem Volumen)
        AST->>SIP: SIP BYE (sofort auflegen)
        SIP->>LEAD: SIP BYE quittiert
        AST->>CAMP: AMI-Event: Hangup {cause: MACHINE_DETECTED, action: HANGUP}
        CAMP->>CAMP: Lead markieren: voicemail=true, retry_after=24h, voicemail_left=false

    else Konfiguration: leaveMessage (personalisierte Nachricht)
        AST->>ARI: StasisStart-Event {amdResult: MACHINE}
        ARI->>AVA: WebSocket-Event: voicemail_detected {lead_name, job_title, language}
        AVA->>OC: POST /v1/chat/completions {trigger: voicemail, metadata: {lead_name, job_title}}
        OC->>AV: Voicemail-Prompt: kurze Nachricht < 25 Sekunden
        AV-->>OC: Voicemail-Text ("Guten Tag Herr Mustermann, hier ist Ava von Step2Job...")
        OC-->>AVA: Text
        AVA->>TTS: Text → Audio (kompakte Ansage)
        TTS-->>AVA: Audio-Bytes (< 25 Sekunden)
        AVA->>AST: AudioSocket: Audio abspielen
        Note over LEAD: Voicemail-Ansage wird aufgenommen
        AVA->>ARI: Hangup nach Nachricht
        AST->>SIP: SIP BYE
        AST->>CAMP: AMI-Event: Hangup {cause: MACHINE, action: MESSAGE_LEFT}
        CAMP->>CAMP: Lead markieren: voicemail_left=true, retry_after=48h, retry_max=0
    end

    CAMP->>CAMP: Nächsten Lead aus Queue laden
```

---

## 4. Human Handoff

Ava erkennt, dass ein Fall menschliche Expertise erfordert und übergibt an einen echten Mitarbeiter.

```mermaid
sequenceDiagram
    participant LEAD as Lead (Telefon)
    participant AVA as AVA Voice Agent
    participant OC as OpenClaw :18789
    participant AV as Ava (claude-sonnet-4-6)
    participant AST as Asterisk PBX
    participant NOTIF as Notification System
    participant AGENT as Menschlicher Agent (Softphone)
    participant CRM as Step2Job CRM

    Note over AVA,AV: Gespräch läuft bereits seit einigen Turns

    LEAD->>AVA: "Ich möchte mit einem echten Menschen sprechen"
    AVA->>OC: Transkription senden
    OC->>AV: Kontext analysieren — Handoff-Trigger erkannt
    Note over AV: Trigger-Bedingungen:
    Note over AV: - Explizite Anfrage ("echten Menschen")
    Note over AV: - Komplexe Rechtsfrage / Vertragsfrage
    Note over AV: - Emotionale Eskalation erkannt
    Note over AV: - Dreifache Verständnisprobleme
    AV-->>OC: Decision: HANDOFF_REQUIRED {reason: "explicit_request", summary: "..."}
    OC-->>AVA: Handoff-Anweisung + Überbrückungstext

    AVA->>OC: Überbrückungstext generieren
    OC->>AV: "Bitte kurz warten, ich verbinde..."
    AV-->>OC: Überbrückungstext
    OC-->>AVA: Text
    AVA->>AST: TTS abspielen: "Einen Moment bitte, ich verbinde Sie mit einem Kollegen."

    par Gleichzeitig: Agent benachrichtigen + Warteschleife abspielen
        AVA->>NOTIF: POST /notify {agent_group: "step2job", lead_name, phone, summary, transcript_snippet}
        NOTIF->>AGENT: Push-Benachrichtigung / Anruf-Alert auf Softphone
        AVA->>AST: MOH (Music on Hold) oder Warteschleife-Audio abspielen
    end

    AGENT->>NOTIF: Agent nimmt Benachrichtigung an ("Accept")
    NOTIF->>AVA: Agent bereit {agent_extension: "SIP/agent-101"}

    AVA->>AST: ARI: Bridge erstellen (Lead-Channel + Agent-Channel)
    AST->>AST: Bridge: LEAD <-> AGENT direkt verbunden
    AST->>AGENT: SIP INVITE (eingehend vom System)
    AGENT->>AST: SIP 200 OK (Agent nimmt Gespräch an)

    Note over LEAD,AGENT: Direktes Gespräch zwischen Lead und Agent
    AVA->>AST: AVA verlässt Bridge (bleibt im Hintergrund als Observer)
    AVA->>CRM: Handoff-Event speichern {lead_id, agent_id, timestamp, reason, transcript}

    alt Agent beendet Gespräch
        AGENT->>AST: SIP BYE
        AST->>AVA: Bridge-Ende-Event
        AVA->>OC: Gespräch-Summary erstellen
        OC->>AV: Summary aus Transkript
        AV-->>OC: Strukturiertes Outcome
        AVA->>CRM: Finales Outcome speichern {outcome, notes, follow_up_required}
    end
```

---

## 5. Retry-Logik

Kein Abnehmer, besetzt oder kein Durchkommen — wann und wie wird erneut angerufen.

```mermaid
sequenceDiagram
    participant CAMP as Campaign Manager
    participant QUEUE as Retry-Queue (SQLite/JSON)
    participant AMI as Asterisk AMI
    participant AST as Asterisk PBX
    participant SIP as Sipgate SIP Trunk
    participant LEAD as Lead Telefon
    participant LOG as Outcome-Log

    CAMP->>AMI: Originate {phone: +49..., lead_id: 123}
    AMI->>AST: Call starten
    AST->>SIP: SIP INVITE
    SIP->>LEAD: Klingelt...

    alt Ergebnis: NO_ANSWER (klingelt, nimmt nicht ab)
        SIP->>AST: 480 No Answer (nach Timeout)
        AST->>CAMP: AMI Event: {cause: NO_ANSWER, lead_id: 123}
        CAMP->>QUEUE: Retry eintragen {lead_id: 123, attempt: 1, retry_after: now+2h, reason: no_answer}
        Note over QUEUE: Retry-Policy NO_ANSWER: max 3x, Delay 2h→4h→8h

    else Ergebnis: BUSY (Besetzt)
        SIP->>AST: 486 Busy
        AST->>CAMP: AMI Event: {cause: BUSY, lead_id: 123}
        CAMP->>QUEUE: Retry eintragen {lead_id: 123, attempt: 1, retry_after: now+30min}
        Note over QUEUE: Retry-Policy BUSY: max 2x, Delay 30min→60min

    else Ergebnis: VOICEMAIL (AMD erkannt, keine Nachricht hinterlassen)
        AST->>CAMP: AMI Event: {cause: MACHINE, action: HANGUP}
        CAMP->>QUEUE: Retry eintragen {lead_id: 123, attempt: 1, retry_after: now+24h, reason: voicemail}
        Note over QUEUE: Retry-Policy VOICEMAIL: max 1x, Delay 24h

    else Ergebnis: VOICEMAIL (AMD erkannt, Nachricht hinterlassen)
        AST->>CAMP: AMI Event: {cause: MACHINE, action: MESSAGE_LEFT}
        CAMP->>QUEUE: KEIN weiterer Retry — Nachricht wurde hinterlassen
        CAMP->>LOG: Final: voicemail_left=true, do_not_call_again=true
    end

    Note over QUEUE: Periodischer Check (alle 5 Minuten)
    loop Queue-Check alle 5 Minuten
        CAMP->>QUEUE: Fällige Retries abrufen (retry_after <= now)
        QUEUE-->>CAMP: [Liste fälliger Leads]

        loop Für jeden fälligen Lead
            CAMP->>QUEUE: Lead laden {attempt, lead_data}

            alt attempt >= max_retries
                CAMP->>LOG: Final: max_retries_exceeded, status=unreachable
                CAMP->>QUEUE: Lead aus Queue entfernen
            else attempt < max_retries
                CAMP->>AMI: Neuer Originate-Versuch {phone, lead_id, attempt+1}
                CAMP->>QUEUE: attempt+1, retry_after aktualisieren (exponentiell)
            end
        end
    end

    Note over LOG: Finale Outcomes werden täglich als JSONL gespeichert
    LOG->>LOG: /var/log/ava/outcomes/YYYY-MM-DD.jsonl
```

---

## 6. Memory-Flow

Was OpenClaw / Ava nach einem Gespräch speichert und wo.

```mermaid
sequenceDiagram
    participant AVA as AVA Voice Agent
    participant OC as OpenClaw :18789
    participant AV as Ava (claude-sonnet-4-6)
    participant MEM0 as mem0 (Port 8002, CCT-Server)
    participant QDRANT as Qdrant Vectors (Port 16333)
    participant NEO4J as Neo4j Graph (Port 7474)
    participant SUPER as Supermemory API
    participant LOG as Local JSONL Log

    Note over AVA: Gespräch ist beendet (Hangup erhalten)

    AVA->>OC: POST /v1/chat/completions {task: summarize_conversation, transcript: [...]}
    OC->>AV: Gesprächs-Zusammenfassung erstellen
    AV-->>OC: Strukturiertes Outcome:
    Note over AV: {lead_name, phone, outcome, qualification_score,
    Note over AV: key_facts: [job_preference, availability, location],
    Note over AV: next_action, conversation_summary, language}
    OC-->>AVA: Outcome-Objekt

    par Parallel: Mehrere Speicher-Ziele
        AVA->>LOG: JSONL-Zeile schreiben {timestamp, lead_id, outcome, summary}
        Note over LOG: /var/log/ava/outcomes/YYYY-MM-DD.jsonl

        AVA->>MEM0: POST /v1/memory/add {user_id: lead_phone, memory: summary, metadata: outcome}
        MEM0->>QDRANT: Vector-Embedding (bge-m3) + Speichern
        QDRANT-->>MEM0: Vector-ID gespeichert
        MEM0->>NEO4J: Graph-Knoten anlegen/aktualisieren (Lead <-> Gespräch <-> Outcome)
        NEO4J-->>MEM0: Knoten-ID
        MEM0-->>AVA: Memory-ID {id: "mem_xxx"}

        AVA->>SUPER: POST https://api.supermemory.ai/v3/documents {content: summary, containerTag: call-outcomes}
        SUPER-->>AVA: Document-ID gespeichert
    end

    Note over AVA: Memory gespeichert — nächster Call zu diesem Lead
    Note over AVA: wird Ava den Kontext aus mem0 abrufen

    Note over MEM0,NEO4J: Bei nächstem Gespräch mit demselben Lead:
    AVA->>MEM0: GET /v1/memory/search {query: lead_phone, top_k: 5}
    MEM0->>QDRANT: Semantische Suche nach ähnlichen Memories
    QDRANT-->>MEM0: Relevante Memory-Einträge
    MEM0-->>AVA: Vorherige Gesprächs-Kontexte
    AVA->>OC: System-Prompt anreichern mit Memory-Kontext
    Note over OC,AV: Ava "erinnert sich" an vorherige Gespräche
```

---

## 7. Error-Flow

STT-Fehler, LLM-Timeout, TTS-Fehler — Fallbacks und Fehlerbehandlung.

```mermaid
sequenceDiagram
    participant LEAD as Lead Telefon
    participant AVA as AVA Voice Agent
    participant STT as STT (Whisper/Deepgram)
    participant OC as OpenClaw :18789
    participant AV as Ava (claude-sonnet-4-6)
    participant TTS as TTS (ElevenLabs/Azure)
    participant AST as Asterisk PBX
    participant LOG as Error Log

    LEAD->>AVA: Audio-Eingang (Lead spricht)
    AVA->>STT: Audio-Chunk senden

    alt STT-Fehler: Transkription fehlgeschlagen
        STT-->>AVA: Error / Timeout (> 5 Sekunden)
        AVA->>LOG: ERROR: STT_TIMEOUT {timestamp, channel_id}

        alt Retry 1: Whisper-Fallback (falls Deepgram primär)
            AVA->>STT: Retry mit lokalem Whisper
            STT-->>AVA: Transkription (langsamer aber stabil)
            Note over AVA: Weiter mit Transkription
        else Retry 2: Stille-Handling
            AVA->>OC: POST {messages: [..., user: "[unverstaendlich]"]}
            OC->>AV: Rückfrage generieren
            AV-->>OC: "Entschuldigung, ich habe das nicht ganz verstanden. Könnten Sie das wiederholen?"
            OC-->>AVA: Text
            AVA->>TTS: Text → Audio
            AVA->>AST: Audio → Lead
        else Max-Retries erreicht (3x)
            AVA->>OC: Gesprächsabbruch signalisieren
            OC->>AV: Freundlicher Abbruchtext
            AV-->>OC: "Es tut mir leid, ich habe technische Probleme. Ich werde Sie zurückrufen."
            OC-->>AVA: Text
            AVA->>TTS: Abbruchtext → Audio
            AVA->>AST: Audio → Lead, dann Hangup
            AVA->>LOG: ERROR: CALL_ABORTED_STT_FAILURE {lead_id, attempts}
        end
    end

    AVA->>OC: POST /v1/chat/completions {messages: [...]}

    alt LLM-Timeout: OpenClaw / Anthropic antwortet nicht
        OC-->>AVA: Timeout (> 8 Sekunden)
        AVA->>LOG: ERROR: LLM_TIMEOUT {timestamp, channel_id, attempt}

        alt Retry 1: Sofortiger Retry
            AVA->>OC: Dieselbe Anfrage wiederholen
            OC->>AV: Antwort generieren (2. Versuch)
            AV-->>OC: Antwort
            OC-->>AVA: Text (Erfolg)
        else Retry 2: Vereinfachte Anfrage (kein langer Kontext)
            AVA->>OC: POST {messages: [system_prompt_short, last_user_turn_only]}
            Note over OC: Kürzere Anfrage = schnellere Antwort
            OC->>AV: Antwort mit reduziertem Kontext
            AV-->>OC: Antwort
            OC-->>AVA: Text
        else LLM komplett nicht erreichbar
            AVA->>AVA: Statische Fallback-Antwort laden (config/fallbacks.json)
            Note over AVA: Vordefinierte Antworten für häufige Situationen
            AVA->>TTS: Fallback-Text
            AVA->>LOG: ERROR: LLM_UNAVAILABLE, using fallback
            Note over AVA: Nach 2 Fallback-Turns: Gespräch beenden
            AVA->>AST: "Ich rufe Sie in Kürze zurück." + Hangup
        end
    end

    AVA->>TTS: Text-Antwort senden

    alt TTS-Fehler: ElevenLabs nicht erreichbar
        TTS-->>AVA: Error / HTTP 500 / Timeout
        AVA->>LOG: ERROR: TTS_ELEVENLABS_FAILED

        alt Fallback 1: Azure TTS
            AVA->>TTS: Dieselbe Text-Anfrage an Azure TTS
            TTS-->>AVA: Audio (Azure Stimme, de-DE-KatjaNeural)
            Note over AVA: Qualität etwas anders aber funktional
        else Fallback 2: Lokales TTS (Coqui/Piper)
            AVA->>TTS: POST http://localhost:5002/api/tts (Coqui lokale TTS)
            TTS-->>AVA: Audio (lokale DE-Stimme, geringere Qualität)
        else Alle TTS-Systeme ausgefallen
            AVA->>LOG: CRITICAL: ALL_TTS_FAILED
            AVA->>AST: Pre-recorded audio: "Technisches Problem, Rückruf folgt." + Hangup
            Note over AVA: Statische WAV-Datei aus /opt/ava/audio/fallback_de.wav
        end
    end

    alt Audio-Stream-Fehler: AudioSocket unterbrochen
        AS-->>AVA: Connection reset / broken pipe
        AVA->>LOG: ERROR: AUDIOSOCKET_DISCONNECTED {channel_id}
        AVA->>AST: ARI: Check channel state
        AST-->>AVA: Channel-Status

        alt Channel noch aktiv (Netzwerkunterbrechung)
            AVA->>AST: AudioSocket-Reconnect-Versuch (3x, 1s Delay)
            Note over AVA: Falls Reconnect erfolgreich: Gespräch fortsetzen
        else Channel bereits tot
            AVA->>LOG: INFO: Channel disconnected by remote party
            Note over AVA: Normaler Call-Abbruch durch Lead — kein Fehler
        end
    end
```
