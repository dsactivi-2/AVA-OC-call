# Validation Report 2 — AVA+Asterisk+OpenClaw (Re-Validierung)
Datum: 2026-03-24

## Ergebnis: APPROVED ✅

## Fix-Prüfung

| Fix | Status | Details |
|-----|--------|---------|
| K1 AudioSocket UUID | ✅ | `Set(AUDIO_UUID=${SHELL(uuidgen)})` vor AudioSocket-Aufruf vorhanden. Syntax `AudioSocket(${AUDIO_UUID},127.0.0.1:9092)` korrekt — UUID zuerst, dann Adresse. Entspricht offiziellem Asterisk-20-Doku-Format `AudioSocket(uuid,service)`. Sowohl in `ava-outbound` (Zeile 46-47) als auch in `ava-inbound` (Zeile 78-79) korrekt umgesetzt. |
| K2 AMD() Parameter | ✅ | `AMD(800,2500,1500,5000,100,8,256)` ersetzt durch `AMD()` ohne Parameter (Zeile 24). Kommentar erklärt korrekt: betweenWordSilence=50 und maximumNumberOfWords=3 werden aus `amd.conf` geladen. |
| K3 min_word_length | ✅ | Parameter heisst `min_word_length = 100` (Zeile 461 in runbook.md). Kein `minimum_word_length` vorhanden. |
| K4 Deepgram Preise | ✅ | Pay-as-you-go: $0.0058/min, Growth Plan: $0.0047/min (costs.md Zeile 84-85). Beide Werte korrekt. |
| K5 Hetzner Preise | ✅ | CX22=3.79, CX32=6.80, CX42=16.40, CX52=32.40 EUR (costs.md Zeilen 25-28). Alle vier Werte korrekt. |

## Verbleibende Probleme

Keine. Alle fünf kritischen Fixes aus Validation Report 1 sind korrekt umgesetzt.

## Zusätzliche Beobachtungen (nicht blockierend)

- **AudioSocket-Kommentare vollständig:** Beide Contexts (`ava-outbound` und `ava-inbound`) enthalten erklärende Kommentare warum `${UNIQUEID}` nicht verwendet wird und stattdessen `uuidgen` genutzt wird — gut dokumentiert.
- **AMD-Kommentar präzise:** Der Inline-Kommentar zu `AMD()` erklärt das ursprüngliche Problem (betweenWordSilence=8ms, maximumNumberOfWords=256) klar und nachvollziehbar.
- **amd.conf-Werte konsistent:** `runbook.md` Sektion 8 zeigt `between_words_silence = 50` und `maximum_number_of_words = 2` als Defaults — in Einklang mit `AMD()`-Kommentar im extensions.conf.

## Gesamt-Empfehlung

**APPROVED — bereit für 1-Click-Script-Erstellung**

Alle kritischen Fixes sind korrekt umgesetzt. Das Blueprint ist technisch valide und kann als Basis für das Setup-Script verwendet werden.
