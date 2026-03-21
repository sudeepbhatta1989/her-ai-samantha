"""
Samantha Voice — HuggingFace Space
Microsoft Edge TTS: en-IN-NeerjaNeural (Indian English) + hi-IN-SwaraNeural (Hindi)
No API key. No model download. Instant startup.

Endpoints:
  POST /tts    {"text": "...", "lang": "en|hi"}  → MP3 audio bytes
  GET  /health → {"status": "ready"}
  GET  /       → Gradio UI
"""

import os, io, asyncio, hashlib, time
from pathlib import Path
import edge_tts

CACHE_DIR = Path('/tmp/samantha_cache')
CACHE_DIR.mkdir(exist_ok=True)

VOICES = {
    'en': 'en-IN-NeerjaNeural',   # Indian English female
    'hi': 'hi-IN-SwaraNeural',    # Hindi female, fluent
}

print('[Samantha] Edge TTS ready — en-IN-NeerjaNeural / hi-IN-SwaraNeural')


def _cache_path(text: str, lang: str) -> Path:
    key = hashlib.md5(f'{text}:{lang}'.encode()).hexdigest()
    return CACHE_DIR / f'{key}.mp3'


async def _generate(text: str, voice: str) -> bytes:
    communicate = edge_tts.Communicate(text, voice)
    buf = io.BytesIO()
    async for chunk in communicate.stream():
        if chunk['type'] == 'audio':
            buf.write(chunk['data'])
    return buf.getvalue()


def generate_speech(text: str, language: str = 'en') -> bytes:
    text = text.strip()[:300]
    if not text:
        return None
    voice = VOICES.get(language, VOICES['en'])
    cache = _cache_path(text, language)
    if cache.exists():
        print(f'[Samantha] Cache hit: {text[:40]}')
        return cache.read_bytes()
    start = time.time()
    audio = asyncio.run(_generate(text, voice))
    print(f'[Samantha] {voice} generated {len(audio)}B in {round(time.time()-start,1)}s')
    if audio:
        cache.write_bytes(audio)
    return audio


# ── FastAPI endpoints ──
from fastapi import FastAPI, Request
from fastapi.responses import Response, JSONResponse
import gradio as gr

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
            return Response(content=audio, media_type='audio/mpeg')
        return JSONResponse({'error': 'generation failed'}, status_code=500)
    except Exception as e:
        return JSONResponse({'error': str(e)}, status_code=500)

@api.get('/health')
def health():
    return {'status': 'ready', 'voices': list(VOICES.values())}


# ── Gradio UI ──
def synthesize(text: str, language: str) -> str:
    audio = generate_speech(text, language)
    if not audio:
        return None
    out = CACHE_DIR / f'ui_{hashlib.md5(text.encode()).hexdigest()}.mp3'
    out.write_bytes(audio)
    return str(out)

with gr.Blocks(title='Samantha Voice') as demo:
    gr.Markdown('## 🎙️ Samantha Voice\n**en-IN-NeerjaNeural** (Indian English) · **hi-IN-SwaraNeural** (Hindi)')
    with gr.Row():
        text_in = gr.Textbox(label='Text', lines=3, placeholder='Type in English or Hindi...')
        lang_in = gr.Radio(['en', 'hi'], value='en', label='Language')
    audio_out = gr.Audio(label='Output', type='filepath')
    gr.Button('Generate', variant='primary').click(
        fn=synthesize, inputs=[text_in, lang_in], outputs=[audio_out]
    )

app = gr.mount_gradio_app(api, demo, path='/')

if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='0.0.0.0', port=7860)
