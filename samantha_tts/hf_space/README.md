---
title: Samantha Voice
emoji: 🎙️
colorFrom: blue
colorTo: purple
sdk: gradio
sdk_version: 4.44.0
app_file: app.py
pinned: true
---

# Samantha Voice — Custom TTS

Coqui XTTS v2 voice cloning using a custom reference audio.
No external TTS API. Runs entirely on this Space.

## API Usage (for Lambda)

```
POST /tts
{"text": "Hello Sudeep!", "lang": "en"}
→ returns WAV audio
```
