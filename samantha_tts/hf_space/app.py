"""
Samantha Voice — HuggingFace Space
Coqui XTTS v2 voice cloning using samantha_reference.wav
Free CPU inference — no external TTS API needed.

Deploy to HuggingFace Spaces:
  1. Create new Space at huggingface.co/spaces (SDK: Gradio)
  2. Upload this file + requirements.txt + samantha_reference.wav
  3. Space URL becomes your TTS endpoint
"""

import os, io, hashlib, time
from pathlib import Path

# ── Load model at startup ──
print('[Samantha] Loading XTTS v2...')
from TTS.api import TTS
tts = TTS('tts_models/multilingual/multi-dataset/xtts_v2')
print('[Samantha] Model ready.')

REFERENCE = Path(__file__).parent / 'samantha_reference.wav'


def _cache_path(text: str, lang: str) -> Path:
    cache_dir = Path('/tmp/samantha_cache')
    cache_dir.mkdir(exist_ok=True)
    key = hashlib.md5(f'{text}:{lang}'.encode()).hexdigest()
    return cache_dir / f'{key}.wav'


def generate_speech(text: str, language: str = 'en') -> str:
    """Generate speech and return path to WAV file."""
    text = text.strip()[:500]
    if not text:
        return None

    cache = _cache_path(text, language)
    if cache.exists():
        return str(cache)

    tts.tts_to_file(
        text=text,
        speaker_wav=str(REFERENCE),
        language=language,
        file_path=str(cache),
    )
    return str(cache)


# ── Gradio interface ──
import gradio as gr

def synthesize(text, language):
    if not text.strip():
        return None
    start = time.time()
    path = generate_speech(text, language)
    elapsed = round(time.time() - start, 1)
    print(f'[Samantha TTS] Generated in {elapsed}s: {text[:60]}')
    return path


demo = gr.Interface(
    fn=synthesize,
    inputs=[
        gr.Textbox(label='Text', placeholder='Type what Samantha should say...', lines=3),
        gr.Dropdown(['en', 'hi'], value='en', label='Language'),
    ],
    outputs=gr.Audio(label='Samantha Voice', type='filepath'),
    title='Samantha Voice — XTTS v2',
    description='Custom voice cloning using Sudeep\'s reference audio. No external TTS API.',
    allow_flagging='never',
)

# Also expose a FastAPI endpoint for Lambda to call
from fastapi import FastAPI, Request
from fastapi.responses import FileResponse, JSONResponse
import uvicorn

api = FastAPI()

@api.post('/tts')
async def tts_endpoint(request: Request):
    data = await request.json()
    text = (data.get('text') or '').strip()
    lang = data.get('lang', 'en')
    if not text:
        return JSONResponse({'error': 'text required'}, status_code=400)
    path = generate_speech(text, lang)
    if path:
        return FileResponse(path, media_type='audio/wav')
    return JSONResponse({'error': 'generation failed'}, status_code=500)

@api.get('/health')
def health():
    return {'status': 'ready', 'model': 'xtts_v2'}

# Mount both
app = gr.mount_gradio_app(api, demo, path='/')

if __name__ == '__main__':
    uvicorn.run(app, host='0.0.0.0', port=7860)
