# AVA + Asterisk + OpenClaw — Autonomes AI-Callcenter

## Was dieser Stack macht

Dieses Blueprint beschreibt ein vollstaendig autonomes Outbound-Callcenter fuer Step2Job GmbH. Ava, der KI-Agent in OpenClaw, fuehrt eigenstaendig Telefongespreaehe mit Leads auf Deutsch und Bosnisch/Serbisch, erkennt Anrufbeantworter automatisch, speichert Gespraechsergebnisse und kann bei Bedarf an einen menschlichen Agenten uebergeben.

## Warum dieser Stack der beste fuer Denis ist

Denis hat bereits:
- Asterisk PBX (laeuft, konfiguriert)
- Sipgate SIP Trunk (aktiver Vertrag, Flatrate)
- OpenClaw auf Port 18789 mit Ava als Hauptagent (claude-sonnet-4-6)
- OpenClaw-kompatibler OpenAI-API-Endpunkt

Der Stack nutzt genau diese vorhandene Infrastruktur, ohne neue Drittanbieter einzufuehren.

## Komponentenverantwortung

### Was Asterisk nativ liefert
| Funktion | Asterisk-Mechanismus |
|---|---|
| SIP-Verbindung zu Sipgate | chan_pjsip |
| Outbound-Call-Initiierung | AMI Originate |
| Answering Machine Detection | app_amd.so (AMD) |
| DTMF-Erkennung | app_read, DTMF-Events |
| Gespraechsaufzeichnung | MixMonitor |
| Call-Routing | extensions.conf Dialplan |
| ARI-Schnittstelle | ari.conf (HTTP WebSocket) |
| AudioSocket-Bridge | app_audiosocket.so |

### Was AVA AI Voice Agent macht
| Funktion | Mechanismus |
|---|---|
| Verbindung zu Asterisk | ARI (Asterisk REST Interface) |
| Audio-Streaming | AudioSocket (TCP, bidirektional) |
| Sprache zu Text | Whisper (lokal) oder Deepgram (API) |
| LLM-Anfrage | HTTP POST an OpenClaw Port 18789 |
| Text zu Sprache | ElevenLabs oder Azure TTS |
| Audio zurueck | AudioSocket → Asterisk → Sipgate |
| Gespraechwsteuerung | ARI-Events (hangup, DTMF, etc.) |

### Was OpenClaw / Ava macht
| Funktion | Mechanismus |
|---|---|
| LLM-Reasoning | claude-sonnet-4-6 ueber OpenClaw |
| Gespraeehsstrategie | System-Prompt + Memory |
| Tool Calls | HTTP-Tools in OpenClaw konfiguriert |
| Memory nach Gespraech | mem0 / Supermemory |
| Lead-Qualifikation | Skill-basiertes Reasoning |
| Uebergabe-Entscheidung | Logik im System-Prompt |

## Vorteile gegenueber Vapi

| Kriterium | Vapi | Dieser Stack |
|---|---|---|
| Kosten pro Minute | ~$0.05-0.10 (Plus LLM) | Sipgate-Flatrate ($0 pro Call) |
| SIP-Trunk | Vapi-eigener Trunk | Eigener Sipgate-Trunk |
| LLM-Kontrolle | Vapi-Modelle | Beliebig (OpenClaw-Routing) |
| Datenschutz | Vapi-Server (USA) | Vollstaendig lokal/eigener Server |
| Vendor Lock-in | Hoch (Vapi-API) | Kein Lock-in (offene Standards) |
| AMD | Vapi-Blackbox | Asterisk app_amd.so, vollst. konfigurierbar |
| Recording | Vapi-Storage | Eigenes Storage |
| Debugging | Eingeschraenkt | Voller Asterisk CLI + AVA Logs |
| Sprachen | Via API-Konfiguration | Beliebig, per Prompt |
| Skalierung | Vapi-Limits | Asterisk-Kapazitaet (100+ Kanaele) |

## Sprachen

- Deutsch: Primaersprache fuer deutsche Leads
- Bosnisch/Serbisch: Fuer entsprechende Leads aus dem Balkanraum
- Ava erkennt die bevorzugte Sprache anhand des Lead-Datensatzes und fuehrt das gesamte Gespraech in dieser Sprache

## Einsatzbereiche bei Step2Job GmbH

1. Outbound Lead-Calling: Ava ruft qualifizierte Arbeitssuchende an
2. Termin-Vereinbarung: Ava bucht Erstgespraeche
3. Nachfass-Calls: Automatische Follow-ups nach X Tagen
4. Voicemail-Nachrichten: Strukturierte Nachricht bei Anrufbeantworter
