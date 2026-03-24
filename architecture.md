# Architektur — AVA + Asterisk + OpenClaw

## ASCII-Gesamtarchitektur

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        STEP2JOB CALLCENTER STACK                        │
│                                                                         │
│  ┌──────────────┐    SIP/RTP    ┌─────────────────────────────────────┐ │
│  │   Sipgate    │◄─────────────►│          Asterisk PBX               │ │
│  │  SIP Trunk   │               │  ┌──────────────────────────────┐   │ │
│  │  (Flatrate)  │               │  │  chan_pjsip (SIP)             │   │ │
│  └──────────────┘               │  │  app_amd.so (AMD)             │   │ │
│                                 │  │  MixMonitor (Recording)       │   │ │
│                                 │  │  app_audiosocket.so           │   │ │
│                                 │  │  ARI (HTTP:8088)              │   │ │
│                                 │  │  AMI (TCP:5038)               │   │ │
│                                 │  └──────────┬───────────────────┘   │ │
│                                 └─────────────┼───────────────────────┘ │
│                                               │ ARI WebSocket           │
│                                               │ AudioSocket TCP:9092    │
│                                 ┌─────────────▼───────────────────────┐ │
│                                 │       AVA AI Voice Agent             │ │
│                                 │       (Python, Port 8080)            │ │
│                                 │  ┌────────────┐ ┌────────────────┐  │ │
│                                 │  │  STT       │ │  TTS           │  │ │
│                                 │  │  Whisper   │ │  ElevenLabs    │  │ │
│                                 │  │  (lokal)   │ │  Azure TTS     │  │ │
│                                 │  │  oder      │ │  (konfigurb.)  │  │ │
│                                 │  │  Deepgram  │ └────────────────┘  │ │
│                                 │  └────────────┘                     │ │
│                                 │         │ HTTP POST                 │ │
│                                 └─────────┼───────────────────────────┘ │
│                                           │                             │
│                                 ┌─────────▼───────────────────────────┐ │
│                                 │         OpenClaw API                 │ │
│                                 │         Port 18789                   │ │
│                                 │    ┌─────────────────────┐          │ │
│                                 │    │  Agent "Ava"         │          │ │
│                                 │    │  claude-sonnet-4-6   │          │ │
│                                 │    │  Skills + Memory     │          │ │
│                                 │    └──────────┬──────────┘          │ │
│                                 └──────────────┼────────────────────── │ │
│                                               │                        │
│                                  ┌────────────▼──────────────────────┐ │
│                                  │       Memory Layer                  │ │
│                                  │  mem0 (Port 8002) + Supermemory    │ │
│                                  └────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

## Mermaid: Outbound Call Flow

```mermaid
sequenceDiagram
    participant Script as batch-campaign.sh
    participant AMI as Asterisk AMI (5038)
    participant AST as Asterisk PBX
    participant SIP as Sipgate SIP Trunk
    participant Lead as Lead (Telefon)
    participant AMD as app_amd.so
    participant ARI as Asterisk ARI (8088)
    participant AVA as AVA Voice Agent
    participant STT as Whisper STT
    participant OC as OpenClaw / Ava
    participant TTS as ElevenLabs TTS

    Script->>AMI: Originate Action (Nummer, Context, Channel)
    AMI->>AST: Interner Originate-Befehl
    AST->>SIP: SIP INVITE (PJSIP)
    SIP->>Lead: Klingeln
    Lead-->>SIP: SIP 200 OK (Abgehoben)
    SIP-->>AST: Call Connected
    AST->>AMD: app_amd() ausloesen
    AMD-->>AST: HUMAN erkannt
    AST->>ARI: ChannelCreated + StasisStart Event
    ARI-->>AVA: WebSocket Event: Stasis Start
    AVA->>ARI: addChannel to Bridge (AudioSocket)
    AST->>AVA: AudioSocket TCP Stream (Audio IN)
    Lead->>AST: Spricht
    AST->>AVA: Audio-Frames (PCM 8kHz)
    AVA->>STT: Audio-Buffer senden
    STT-->>AVA: Transkription: "Hallo?"
    AVA->>OC: POST /v1/chat/completions (Transkription + Context)
    OC-->>AVA: Ava-Antwort: "Guten Tag, hier ist Ava..."
    AVA->>TTS: Text senden
    TTS-->>AVA: Audio-Stream (MP3/PCM)
    AVA->>AST: Audio-Frames via AudioSocket (Audio OUT)
    AST->>SIP: RTP Audio
    SIP->>Lead: Ava spricht
    Note over Lead,OC: Gespraech laeuft (mehrere Runden)
    Lead->>AST: Legt auf
    AST->>ARI: ChannelHangupRequest Event
    ARI-->>AVA: Hangup Event
    AVA->>OC: POST (Gespraech beenden, Memory speichern)
    OC-->>AVA: OK
    AVA->>Script: Ergebnis-Callback (Status, Notizen)
```

## Mermaid: Inbound Call Flow

```mermaid
sequenceDiagram
    participant Lead as Lead (Telefon)
    participant SIP as Sipgate SIP Trunk
    participant AST as Asterisk PBX
    participant ARI as Asterisk ARI (8088)
    participant AVA as AVA Voice Agent
    participant OC as OpenClaw / Ava

    Lead->>SIP: Waehlt Step2Job-Nummer
    SIP->>AST: SIP INVITE (Inbound)
    AST->>AST: extensions.conf: Inbound-Context
    AST->>AST: Answer(), Wait(1)
    AST->>ARI: StasisStart Event (Inbound)
    ARI-->>AVA: WebSocket: Neuer Inbound Call
    AVA->>ARI: Bridge erstellen + Channel hinzufuegen
    AVA->>OC: POST (System: Inbound Call, Caller-ID: +49xxx)
    OC-->>AVA: Begruessungstext (Ava stellt sich vor)
    AVA->>AST: TTS-Audio abspielen
    Note over Lead,OC: Gespraech laeuft wie Outbound
    Note over AVA,OC: Caller-ID wird gegen Lead-DB abgeglichen
```

## Mermaid: AMD / Voicemail Detection Flow

```mermaid
sequenceDiagram
    participant AST as Asterisk PBX
    participant AMD as app_amd.so
    participant AVA as AVA Voice Agent
    participant OC as OpenClaw / Ava
    participant TTS as ElevenLabs TTS

    AST->>AMD: AMD(800,2500,1500,5000,100,8,256)
    Note over AMD: Analysiert Audio: Silence-Pattern, Greeting-Laenge
    alt HUMAN erkannt
        AMD-->>AST: AMDSTATUS=HUMAN
        AST->>ARI: StasisStart (normal)
        ARI-->>AVA: Call Event
        AVA->>OC: Gespraech starten
    else MACHINE erkannt
        AMD-->>AST: AMDSTATUS=MACHINE
        AST->>AST: Warte auf BEEP (AMDCause=AFTERBEEP)
        AST->>TTS: Voicemail-Nachricht generieren
        TTS-->>AST: Audio
        AST->>AST: Playback(voicemail-msg)
        AST->>AST: Hangup()
        AST->>AVA: HTTP Callback: AMD=MACHINE, Aktion=VOICEMAIL_LEFT
    else NOTSURE / TIMEOUT
        AMD-->>AST: AMDSTATUS=NOTSURE
        AST->>AST: Hangup() — Retry in 2h
        AST->>AVA: HTTP Callback: AMD=NOTSURE, Aktion=RETRY
    end
```

## Mermaid: Human Handoff Flow

```mermaid
sequenceDiagram
    participant Lead as Lead
    participant AVA as AVA Voice Agent
    participant OC as OpenClaw / Ava
    participant AST as Asterisk PBX
    participant Agent as Menschlicher Agent

    Note over AVA,OC: Ava erkennt Handoff-Trigger (Wunsch, Beschwerde, komplexe Frage)
    OC-->>AVA: Tool Call: human_handoff(reason="Lead moechte sprechen")
    AVA->>AVA: Handoff-Ankuendigung abspielen
    AVA->>AST: ARI: Transfer Channel to Queue/Extension
    AST->>Agent: SIP INVITE (Ring Agent-Telefon)
    Agent-->>AST: Abgehoben
    AST->>AST: Bridge: Lead <-> Agent (direkt)
    AVA->>OC: POST: Handoff-Summary speichern
    OC->>OC: Memory: Gespraechszusammenfassung + Grund
    Note over Agent: Agent sieht: Name, Gespraechszusammenfassung im CRM
    Agent->>Lead: Uebernimmt Gespraech
```

## Mermaid: OpenClaw HTTP Tool Call Flow

```mermaid
sequenceDiagram
    participant AVA as AVA Voice Agent
    participant OC as OpenClaw Port 18789
    participant Ava as Agent "Ava"
    participant Tool as HTTP Tool (Lead-DB / CRM)
    participant Mem as mem0 Memory

    AVA->>OC: POST /v1/chat/completions\n{model, messages, tools}
    OC->>Ava: Routing zu Agent "Ava"
    Ava->>Ava: Reasoning: Tool needed?
    alt Tool Call noetig
        Ava->>OC: Tool Call Request: get_lead_info(id=123)
        OC->>Tool: HTTP GET /api/leads/123
        Tool-->>OC: Lead-Daten (Name, Status, Notizen)
        OC->>Ava: Tool Result
        Ava->>Ava: Antwort formulieren mit Lead-Kontext
    end
    Ava->>Mem: search_memories("Lead 123")
    Mem-->>Ava: Vorherige Gespraeche
    Ava-->>OC: Antwort-Text
    OC-->>AVA: completion response\n{content: "Guten Tag Herr Mustermann..."}
```

## Komponentenliste

| Komponente | Version | Port | Rolle | Laeuft auf |
|---|---|---|---|---|
| Asterisk PBX | 20.x | 5060 (SIP), 10000-20000 (RTP) | SIP-Gateway, AMD, Recording, Routing | Lokal / Server |
| Asterisk ARI | 20.x | 8088 (HTTP/WS) | Programmatic Call Control | Lokal / Server |
| Asterisk AMI | 20.x | 5038 (TCP) | Call Origination via Script | Lokal / Server |
| Sipgate SIP Trunk | - | - | Externer SIP-Carrier (PSTN) | Sipgate-Cloud |
| AVA AI Voice Agent | latest | 8080 (HTTP intern) | STT/TTS-Bridge, ARI-Client | Lokal / Server |
| Whisper STT | large-v3 | lokal (keine) | Speech-to-Text | Lokal / Server |
| Deepgram STT | API | - | Speech-to-Text (Alternative) | Deepgram-Cloud |
| ElevenLabs TTS | API | - | Text-to-Speech (HQ) | ElevenLabs-Cloud |
| Azure Cognitive TTS | API | - | Text-to-Speech (Alternative) | Azure-Cloud |
| OpenClaw | latest | 18789 | LLM-Router + Agent-Runtime | Lokal (Mac) |
| Agent "Ava" | claude-sonnet-4-6 | via OpenClaw | Conversational AI | via OpenClaw |
| mem0 | latest | 8002 | Memory-Persistence | CCT Server |

## Netzwerk-Diagramm: Offene Ports

```
EINGEHEND (Firewall freigeben):
  UDP 5060       — SIP Signaling (Sipgate → Asterisk)
  UDP 10000-20000 — RTP Media (Sipgate → Asterisk)
  TCP 8088       — ARI HTTP/WebSocket (AVA → Asterisk) [nur lokal/LAN]
  TCP 5038       — AMI (Scripts → Asterisk) [nur lokal/LAN]
  TCP 9092       — AudioSocket (Asterisk → AVA) [nur lokal/LAN]

AUSGEHEND (keine spezielle Freigabe noetig):
  TCP 443        — ElevenLabs TTS API
  TCP 443        — Deepgram STT API
  TCP 443        — Sipgate API
  TCP 18789      — OpenClaw API (lokal)
  TCP 8002       — mem0 API (via SSH-Tunnel)

INTERNE KOMMUNIKATION (lokal, kein Internet):
  AVA → Asterisk ARI:       HTTP/WS auf 127.0.0.1:8088
  AVA → Asterisk AudioSocket: TCP auf 127.0.0.1:9092
  AVA → OpenClaw:           HTTP auf 127.0.0.1:18789
  Scripts → Asterisk AMI:   TCP auf 127.0.0.1:5038
```
