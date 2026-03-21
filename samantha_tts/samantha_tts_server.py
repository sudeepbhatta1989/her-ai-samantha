"""
Samantha Custom TTS Server
Runs locally on Windows PC using XTTS v2 voice cloning.
Uses samantha_reference.wav as the voice character — no external API needed.

Primary: Coqui TTS (XTTS v2) — best quality, voice cloning
Fallback: pyttsx3 (system TTS) — if Coqui not installed

Start: python samantha_tts_server.py
Port: 8765
"""

from flask import Flask, request, jsonify, send_file
import os, io, hashlib, time, threading
from pathlib import Path

app = Flask(__name__)

# ── Paths ──
BASE_DIR = Path(__file__).parent
REFERENCE_WAV = BASE_DIR / 'samantha_reference.wav'
CACHE_DIR = BASE_DIR / 'audio_cache'
CACHE_DIR.mkdir(exist_ok=True)

# ── Backend detection ──
TTS_BACKEND = None   # 'coqui' | 'pyttsx3'
tts_model = None
model_lock = threading.Lock()
MODEL_LOADING = False


def load_model():
    global tts_model, TTS_BACKEND, MODEL_LOADING
    MODEL_LOADING = True

    # ── Try Coqui XTTS v2 ──
    try:
        import torch
        from TTS.api import TTS
        print('[Samantha TTS] Loading XTTS v2 model... (first run downloads ~1.8 GB)')
        tts_model = TTS('tts_models/multilingual/multi-dataset/xtts_v2')
        TTS_BACKEND = 'coqui'
        cuda = torch.cuda.is_available()
        print(f'[Samantha TTS] XTTS v2 ready. CUDA: {cuda}')
        MODEL_LOADING = False
        return
    except ImportError:
        print('[Samantha TTS] Coqui TTS not installed.')
    except Exception as e:
        print(f'[Samantha TTS] Coqui TTS failed: {e}')

    # ── Fallback: pyttsx3 ──
    try:
        import pyttsx3
        engine = pyttsx3.init()
        # Try to use a female voice
        voices = engine.getProperty('voices')
        for v in voices:
            if 'zira' in v.name.lower() or 'female' in v.name.lower():
                engine.setProperty('voice', v.id)
                break
        engine.setProperty('rate', 155)
        engine.setProperty('volume', 0.95)
        tts_model = engine
        TTS_BACKEND = 'pyttsx3'
        print('[Samantha TTS] Using pyttsx3 fallback TTS.')
    except Exception as e:
        print(f'[Samantha TTS] pyttsx3 also failed: {e}')
        print('[Samantha TTS] Install Coqui TTS: pip install TTS --prefer-binary')

    MODEL_LOADING = False


def get_cache_path(text: str, lang: str) -> Path:
    key = hashlib.md5(f'{text}:{lang}'.encode()).hexdigest()
    return CACHE_DIR / f'{key}.wav'


def synthesize_coqui(text: str, lang: str) -> bytes:
    cache_path = get_cache_path(text, lang)
    if cache_path.exists():
        return cache_path.read_bytes()

    with model_lock:
        output_path = CACHE_DIR / f'tmp_{int(time.time()*1000)}.wav'
        tts_model.tts_to_file(
            text=text,
            speaker_wav=str(REFERENCE_WAV),
            language=lang,
            file_path=str(output_path),
        )
        output_path.rename(cache_path)
        return cache_path.read_bytes()


def synthesize_pyttsx3(text: str) -> bytes:
    cache_path = get_cache_path(text, 'sys')
    if cache_path.exists():
        return cache_path.read_bytes()

    with model_lock:
        tmp = str(CACHE_DIR / f'tmp_{int(time.time()*1000)}.wav')
        tts_model.save_to_file(text, tmp)
        tts_model.runAndWait()
        import shutil
        shutil.move(tmp, str(cache_path))
        return cache_path.read_bytes()


def synthesize(text: str, lang: str = 'en') -> bytes:
    if tts_model is None:
        raise RuntimeError('Model not loaded yet. Retry in a moment.')
    if TTS_BACKEND == 'coqui':
        return synthesize_coqui(text, lang)
    elif TTS_BACKEND == 'pyttsx3':
        return synthesize_pyttsx3(text)
    raise RuntimeError('No TTS backend available.')


# ── Routes ──

@app.route('/health')
def health():
    status = 'ready' if tts_model is not None else ('loading' if MODEL_LOADING else 'unavailable')
    return jsonify({
        'status': status,
        'backend': TTS_BACKEND or 'none',
        'model': 'xtts_v2' if TTS_BACKEND == 'coqui' else TTS_BACKEND,
        'reference': str(REFERENCE_WAV),
        'cache_size': len(list(CACHE_DIR.glob('*.wav'))),
    })


@app.route('/tts', methods=['POST'])
def tts():
    data = request.get_json(force=True)
    text = (data.get('text') or '').strip()
    lang = data.get('lang', 'en')

    if not text:
        return jsonify({'error': 'text is required'}), 400
    text = text[:500]

    try:
        start = time.time()
        audio_bytes = synthesize(text, lang)
        elapsed = round(time.time() - start, 2)
        return send_file(
            io.BytesIO(audio_bytes),
            mimetype='audio/wav',
            as_attachment=False,
            download_name='samantha.wav',
        ), 200, {'X-Generation-Time': str(elapsed)}

    except RuntimeError as e:
        return jsonify({'error': str(e), 'retry_after': 10}), 503
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/clear_cache', methods=['POST'])
def clear_cache():
    for f in CACHE_DIR.glob('*.wav'):
        f.unlink()
    return jsonify({'cleared': True})


if __name__ == '__main__':
    t = threading.Thread(target=load_model, daemon=True)
    t.start()

    print('\n' + '='*50)
    print('  Samantha TTS Server')
    print('  Voice: samantha_reference.wav (XTTS v2)')
    print('  http://localhost:8765/health')
    print('  http://localhost:8765/tts  [POST]')
    print('='*50 + '\n')

    app.run(host='0.0.0.0', port=8765, debug=False, threaded=True)
