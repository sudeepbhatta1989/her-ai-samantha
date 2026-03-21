"""
Samantha Custom TTS Server
Runs locally on Windows PC using Coqui XTTS v2 voice cloning.
Uses samantha_reference.wav as the voice character — no external API needed.

Start: python samantha_tts_server.py
Port: 8765
"""

from flask import Flask, request, jsonify, send_file
import torch, os, io, hashlib, time, threading
from pathlib import Path

app = Flask(__name__)

# ── Paths ──
BASE_DIR = Path(__file__).parent
REFERENCE_WAV = BASE_DIR / 'samantha_reference.wav'
CACHE_DIR = BASE_DIR / 'audio_cache'
CACHE_DIR.mkdir(exist_ok=True)

# ── Model (loaded once at startup) ──
tts_model = None
model_lock = threading.Lock()
MODEL_LOADING = False

def load_model():
    global tts_model, MODEL_LOADING
    MODEL_LOADING = True
    print('[Samantha TTS] Loading XTTS v2 model...')
    try:
        from TTS.api import TTS
        tts_model = TTS('tts_models/multilingual/multi-dataset/xtts_v2')
        print('[Samantha TTS] Model ready.')
    except Exception as e:
        print(f'[Samantha TTS] Model load failed: {e}')
        print('[Samantha TTS] Run: pip install TTS')
    MODEL_LOADING = False


def get_cache_path(text: str, lang: str) -> Path:
    key = hashlib.md5(f'{text}:{lang}'.encode()).hexdigest()
    return CACHE_DIR / f'{key}.wav'


def synthesize(text: str, lang: str = 'en') -> bytes:
    """Synthesize text using XTTS v2 with Samantha reference voice."""
    cache_path = get_cache_path(text, lang)
    if cache_path.exists():
        with open(cache_path, 'rb') as f:
            return f.read()

    with model_lock:
        if tts_model is None:
            raise RuntimeError('Model not loaded yet. Retry in a moment.')

        output_path = CACHE_DIR / f'tmp_{int(time.time()*1000)}.wav'
        tts_model.tts_to_file(
            text=text,
            speaker_wav=str(REFERENCE_WAV),
            language=lang,
            file_path=str(output_path),
        )

        # Rename to cache
        output_path.rename(cache_path)
        with open(cache_path, 'rb') as f:
            return f.read()


# ── Routes ──

@app.route('/health')
def health():
    return jsonify({
        'status': 'ready' if tts_model is not None else ('loading' if MODEL_LOADING else 'error'),
        'model': 'xtts_v2',
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
    if len(text) > 500:
        text = text[:500]   # XTTS v2 handles ~500 chars well

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
    # Load model in background thread so server starts immediately
    t = threading.Thread(target=load_model, daemon=True)
    t.start()

    print('\n' + '='*50)
    print('  Samantha TTS Server')
    print('  Voice: samantha_reference.wav (XTTS v2)')
    print('  http://localhost:8765/health')
    print('  http://localhost:8765/tts  [POST]')
    print('='*50 + '\n')

    app.run(host='0.0.0.0', port=8765, debug=False, threaded=True)
