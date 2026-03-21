"""
Samantha Voice — HuggingFace Space
Coqui XTTS v2 voice cloning using samantha_reference.wav
CPU inference — no external TTS API needed.

Endpoints:
  POST /tts  {"text": "...", "lang": "en"}  → WAV audio bytes
  GET  /health                               → {"status": "ready"}
  GET  /      → Gradio UI
"""

import os, io, hashlib, time, base64
from pathlib import Path

REFERENCE = Path(__file__).parent / 'samantha_reference.wav'
CACHE_DIR = Path('/tmp/samantha_cache')
CACHE_DIR.mkdir(exist_ok=True)

# ── Load model at startup ──
print('[Samantha] Loading XTTS v2...')
from TTS.api import TTS
tts = TTS('tts_models/multilingual/multi-dataset/xtts_v2')
print('[Samantha] Model ready.')


def _cache_path(text: str, lang: str) -> Path:
    key = hashlib.md5(f'{text}:{lang}'.encode()).hexdigest()
    return CACHE_DIR / f'{key}.wav'


def generate_speech(text: str, language: str = 'en') -> bytes:
    """Generate speech, return raw WAV bytes."""
    text = text.strip()[:500]
    if not text:
        return None
    cache = _cache_path(text, language)
    if cache.exists():
        return cache.read_bytes()
    tts.tts_to_file(
        text=text,
        speaker_wav=str(REFERENCE),
        language=language,
        file_path=str(cache),
    )
    return cache.read_bytes()


# ── FastAPI (Lambda calls /tts and /health) ──
from fastapi import FastAPI, Request
from fastapi.responses import Response, JSONResponse

api = FastAPI()

@api.post('/tts')
async def tts_endpoint(request: Request):
    data = await request.json()
    text = (data.get('text') or '').strip()
    lang = data.get('lang', 'en')
    if not text:
        return JSONResponse({'error': 'text required'}, status_code=400)
    try:
        start = time.time()
        audio = generate_speech(text, lang)
        elapsed = round(time.time() - start, 1)
        if audio:
            return Response(
                content=audio,
                media_type='audio/wav',
                headers={'X-Generation-Time': str(elapsed)},
            )
        return JSONResponse({'error': 'generation failed'}, status_code=500)
    except Exception as e:
        return JSONResponse({'error': str(e)}, status_code=500)

@api.get('/health')
def health():
    return {'status': 'ready', 'model': 'xtts_v2', 'reference': REFERENCE.name}


# ── Gradio UI (mounted at /) ──
import gradio as gr

def synthesize(text, language):
    if not text.strip():
        return None
    start = time.time()
    audio = generate_speech(text, language)
    elapsed = round(time.time() - start, 1)
    print(f'[Samantha TTS] {elapsed}s: {text[:60]}')
    if audio:
        # Gradio type='filepath' — write to a temp file and return path
        out = CACHE_DIR / f'gradio_{hashlib.md5(text.encode()).hexdigest()}.wav'
        out.write_bytes(audio)
        return str(out)
    return None

demo = gr.Interface(
    fn=synthesize,
    inputs=[
        gr.Textbox(label='Text', placeholder='Type what Samantha should say...', lines=3),
        gr.Dropdown(['en', 'hi'], value='en', label='Language'),
    ],
    outputs=gr.Audio(label='Samantha Voice', type='filepath'),
    title='Samantha Voice — XTTS v2',
    description='Custom voice cloning. No external TTS API.',
    allow_flagging='never',
)

app = gr.mount_gradio_app(api, demo, path='/')

if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='0.0.0.0', port=7860)
