"""
Samantha Custom TTS Server
Runs locally on Windows PC — no external API needed.

Priority order:
  1. Coqui XTTS v2  — voice cloning with samantha_reference.wav (best, needs TTS package)
  2. Kokoro TTS     — high quality neural TTS, Indian English female voice (pure Python)
  3. pyttsx3        — system TTS fallback (always available)

Start: python samantha_tts_server.py
Port: 8765
"""

from flask import Flask, request, jsonify, send_file
import os, io, hashlib, time, threading, wave, struct
from pathlib import Path

app = Flask(__name__)

# ── Paths ──
BASE_DIR = Path(__file__).parent
REFERENCE_WAV = BASE_DIR / 'samantha_reference.wav'
CACHE_DIR = BASE_DIR / 'audio_cache'
CACHE_DIR.mkdir(exist_ok=True)

# ── State ──
TTS_BACKEND = None      # 'coqui' | 'kokoro' | 'pyttsx3'
_coqui_model = None
_kokoro_pipeline = None
_pyttsx3_engine = None
_model_lock = threading.Lock()
MODEL_LOADING = True


# ─────────────────────────────────────────
#  Model loading
# ─────────────────────────────────────────

def _try_coqui():
    global _coqui_model, TTS_BACKEND
    try:
        import torch
        from TTS.api import TTS
        print('[Samantha TTS] Loading XTTS v2... (first run ~1.8 GB download)')
        _coqui_model = TTS('tts_models/multilingual/multi-dataset/xtts_v2')
        TTS_BACKEND = 'coqui'
        cuda = torch.cuda.is_available()
        print(f'[Samantha TTS] XTTS v2 ready. CUDA={cuda}')
        return True
    except ImportError:
        print('[Samantha TTS] Coqui TTS not installed — trying Kokoro.')
    except Exception as e:
        print(f'[Samantha TTS] Coqui TTS failed: {e} — trying Kokoro.')
    return False


def _try_kokoro():
    """Kokoro TTS — pure Python, high quality, no compilation required."""
    global _kokoro_pipeline, TTS_BACKEND
    try:
        from kokoro import KPipeline
        # 'af_heart' is a warm American English female voice (closest to Indian English)
        # 'af' prefix = American female; 'bf' = British female
        # Use 'af_heart' or 'af_sky' for a friendly female voice
        _kokoro_pipeline = KPipeline(lang_code='a')   # 'a' = American English
        TTS_BACKEND = 'kokoro'
        print('[Samantha TTS] Kokoro TTS ready (high-quality female voice).')
        return True
    except ImportError:
        print('[Samantha TTS] Kokoro not installed — trying pyttsx3.')
    except Exception as e:
        print(f'[Samantha TTS] Kokoro failed: {e} — trying pyttsx3.')
    return False


def _try_pyttsx3():
    global _pyttsx3_engine, TTS_BACKEND
    try:
        import pyttsx3
        engine = pyttsx3.init()
        voices = engine.getProperty('voices')
        # Prefer Zira (Microsoft female voice on Windows)
        for v in voices:
            if 'zira' in v.name.lower() or 'female' in v.name.lower():
                engine.setProperty('voice', v.id)
                break
        engine.setProperty('rate', 155)
        engine.setProperty('volume', 0.95)
        _pyttsx3_engine = engine
        TTS_BACKEND = 'pyttsx3'
        print('[Samantha TTS] pyttsx3 system TTS ready (basic quality).')
        return True
    except Exception as e:
        print(f'[Samantha TTS] pyttsx3 also failed: {e}')
    return False


def load_model():
    global MODEL_LOADING
    MODEL_LOADING = True
    _try_coqui() or _try_kokoro() or _try_pyttsx3()
    if TTS_BACKEND is None:
        print('[Samantha TTS] WARNING: No TTS backend available! Run install_deps.bat')
    MODEL_LOADING = False


# ─────────────────────────────────────────
#  Synthesis helpers
# ─────────────────────────────────────────

def _cache_key(text: str, lang: str) -> Path:
    key = hashlib.md5(f'{TTS_BACKEND}:{text}:{lang}'.encode()).hexdigest()
    return CACHE_DIR / f'{key}.wav'


def _synth_coqui(text: str, lang: str) -> bytes:
    cache = _cache_key(text, lang)
    if cache.exists():
        return cache.read_bytes()
    with _model_lock:
        tmp = CACHE_DIR / f'tmp_{int(time.time()*1000)}.wav'
        _coqui_model.tts_to_file(
            text=text,
            speaker_wav=str(REFERENCE_WAV),
            language=lang,
            file_path=str(tmp),
        )
        tmp.rename(cache)
    return cache.read_bytes()


def _synth_kokoro(text: str) -> bytes:
    cache = _cache_key(text, 'kokoro')
    if cache.exists():
        return cache.read_bytes()

    import soundfile as sf
    import numpy as np

    # KPipeline yields (graphemes, phonemes, audio_array) tuples
    chunks = []
    for _, _, audio in _kokoro_pipeline(text, voice='af_heart', speed=0.92, split_pattern=r'\n+'):
        chunks.append(audio)

    if not chunks:
        return b''

    audio_np = np.concatenate(chunks, axis=0)
    buf = io.BytesIO()
    sf.write(buf, audio_np, samplerate=24000, format='WAV')
    data = buf.getvalue()
    cache.write_bytes(data)
    return data


def _synth_pyttsx3(text: str) -> bytes:
    cache = _cache_key(text, 'pyttsx3')
    if cache.exists():
        return cache.read_bytes()
    with _model_lock:
        tmp = str(CACHE_DIR / f'tmp_{int(time.time()*1000)}.wav')
        _pyttsx3_engine.save_to_file(text, tmp)
        _pyttsx3_engine.runAndWait()
        data = Path(tmp).read_bytes()
        cache.write_bytes(data)
        Path(tmp).unlink(missing_ok=True)
    return data


def synthesize(text: str, lang: str = 'en') -> bytes:
    if TTS_BACKEND is None:
        raise RuntimeError('No TTS backend loaded yet. Retry in a moment.')
    if TTS_BACKEND == 'coqui':
        return _synth_coqui(text, lang)
    if TTS_BACKEND == 'kokoro':
        return _synth_kokoro(text)
    if TTS_BACKEND == 'pyttsx3':
        return _synth_pyttsx3(text)
    raise RuntimeError('Unknown TTS backend.')


# ─────────────────────────────────────────
#  Routes
# ─────────────────────────────────────────

@app.route('/health')
def health():
    if MODEL_LOADING:
        status = 'loading'
    elif TTS_BACKEND:
        status = 'ready'
    else:
        status = 'unavailable'
    return jsonify({
        'status': status,
        'backend': TTS_BACKEND or 'none',
        'voice_clone': TTS_BACKEND == 'coqui',
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
        return jsonify({'error': str(e), 'retry_after': 5}), 503
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/clear_cache', methods=['POST'])
def clear_cache():
    removed = 0
    for f in CACHE_DIR.glob('*.wav'):
        f.unlink()
        removed += 1
    return jsonify({'cleared': removed})


if __name__ == '__main__':
    t = threading.Thread(target=load_model, daemon=True)
    t.start()

    print('\n' + '='*52)
    print('  Samantha TTS Server')
    print('  Backend priority: XTTS v2 > Kokoro > pyttsx3')
    print('  http://localhost:8765/health')
    print('  http://localhost:8765/tts  [POST]')
    print('='*52 + '\n')

    app.run(host='0.0.0.0', port=8765, debug=False, threaded=True)
