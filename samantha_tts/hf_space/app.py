"""
Samantha Voice — HuggingFace Space
Coqui XTTS v2 voice cloning using samantha_reference.wav (32s, 10 best clips)
CPU inference — no external TTS API needed.

Endpoints:
  POST /tts  {"text": "...", "lang": "en"}  → WAV audio bytes
  GET  /health                               → {"status": "ready"}
"""

import os, hashlib, time
from pathlib import Path

# Accept Coqui XTTS v2 non-commercial license (CPML) automatically
os.environ['COQUI_TOS_AGREED'] = '1'

REFERENCE = Path(__file__).parent / 'samantha_reference.wav'
CACHE_DIR = Path('/tmp/samantha_cache')
CACHE_DIR.mkdir(exist_ok=True)

# ── Load XTTS v2 at startup ──
print('[Samantha] Loading XTTS v2...')
from TTS.api import TTS
tts = TTS('tts_models/multilingual/multi-dataset/xtts_v2')
print('[Samantha] Model ready.')


def _cache_path(text: str, lang: str) -> Path:
    key = hashlib.md5(f'{text}:{lang}'.encode()).hexdigest()
    return CACHE_DIR / f'{key}.wav'


def generate_speech(text: str, language: str = 'en') -> bytes:
    text = text.strip()[:200]
    if not text:
        return None
    cache = _cache_path(text, language)
    if cache.exists():
        print(f'[Samantha] Cache hit: {text[:40]}')
        return cache.read_bytes()
    start = time.time()
    tts.tts_to_file(
        text=text,
        speaker_wav=str(REFERENCE),
        language=language,
        file_path=str(cache),
    )
    print(f'[Samantha] Generated in {round(time.time()-start,1)}s: {text[:60]}')
    return cache.read_bytes()


# ── Gradio Blocks UI (avoids gr.Dropdown schema bug in 4.44.0) ──
import gradio as gr

def synthesize(text: str) -> str:
    """Gradio handler — English only for simplicity."""
    audio = generate_speech(text, 'en')
    if not audio:
        return None
    out = CACHE_DIR / f'ui_{hashlib.md5(text.encode()).hexdigest()}.wav'
    out.write_bytes(audio)
    return str(out)

with gr.Blocks(title='Samantha Voice') as demo:
    gr.Markdown('## 🎙️ Samantha Voice — XTTS v2\nCustom voice cloning from 128 training clips.')
    text_in  = gr.Textbox(label='Text', lines=3, placeholder='Type what Samantha should say...')
    audio_out = gr.Audio(label='Samantha Voice')
    btn = gr.Button('Generate', variant='primary')
    btn.click(fn=synthesize, inputs=[text_in], outputs=[audio_out])


# ── FastAPI endpoints (Lambda calls these) ──
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
        audio = generate_speech(text, lang)
        if audio:
            return Response(content=audio, media_type='audio/wav')
        return JSONResponse({'error': 'generation failed'}, status_code=500)
    except Exception as e:
        print(f'[Samantha] /tts error: {e}')
        return JSONResponse({'error': str(e)}, status_code=500)

@api.get('/health')
def health():
    return {'status': 'ready', 'model': 'xtts_v2'}

# Mount Gradio onto FastAPI
app = gr.mount_gradio_app(api, demo, path='/')

if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='0.0.0.0', port=7860)
