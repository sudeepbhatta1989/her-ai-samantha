import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

const String LAMBDA_URL =
    'https://aybg83gr69.execute-api.ap-south-1.amazonaws.com/prod/chat';
const String USER_ID = 'user1';
const String GOOGLE_TTS_KEY = 'YOUR_GOOGLE_TTS_API_KEY_HERE';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _textController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();

  // Each Talk session gets unique ID for history grouping
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();

  // Feedback state: msgId → 1 (thumbs up) or -1 (thumbs down)
  final Map<String, int> _feedback = {};

  bool _isListening = false;
  bool _isLoading = false;
  bool _isSpeaking = false;
  bool _sttAvailable = false;
  bool _isMuted = false;
  bool _isOrbMode = false;
  String _liveText = '';
  double _micLevel = 0.0;

  // Document Q&A
  String? _attachedDocText;
  String? _attachedDocName;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _orbFloatController;
  late AnimationController _thinkController;
  late AnimationController _speakWaveController;
  late AnimationController _micRingController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(_pulseController);

    _orbFloatController = AnimationController(
      vsync: this, duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _thinkController = AnimationController(
      vsync: this, duration: const Duration(seconds: 2),
    );

    _speakWaveController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _micRingController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400),
    )..repeat();

    _messages.add({
      'role': 'samantha',
      'agent': '',
      'text': 'Hey Sudeep! Ready when you are — what\'s on your mind?'
    });

    _initAll();

    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (mounted) setState(() => _isSpeaking = false);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _orbFloatController.dispose();
    _thinkController.dispose();
    _speakWaveController.dispose();
    _micRingController.dispose();
    _audioPlayer.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initAll() async {
    await _initMic();
    await _initTts();
  }

  Future<void> _initMic() async {
    _sttAvailable = await _stt.initialize(
      onError: (e) => debugPrint('STT error: $e'),
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );
    setState(() {});
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage('en-IN');
    // Try to pick the enhanced Indian English female voice (Lekha on iOS)
    try {
      final voices = await _flutterTts.getVoices as List?;
      if (voices != null) {
        final indianFemale = voices.firstWhere(
          (v) => v is Map &&
              (v['locale']?.toString().contains('IN') ?? false) &&
              (v['gender']?.toString().toLowerCase() == 'female' ||
               v['name']?.toString().toLowerCase().contains('lekha') == true ||
               v['name']?.toString().toLowerCase().contains('female') == true),
          orElse: () => null,
        );
        if (indianFemale != null) {
          await _flutterTts.setVoice(Map<String, String>.from(indianFemale as Map));
        }
      }
    } catch (_) {}
    await _flutterTts.setSpeechRate(0.48);   // slightly slower = more natural
    await _flutterTts.setPitch(1.12);         // slightly higher = more feminine
    await _flutterTts.setVolume(1.0);
    _flutterTts.setStartHandler(() => setState(() => _isSpeaking = true));
    _flutterTts.setCompletionHandler(() => setState(() => _isSpeaking = false));
  }

  Future<void> _speak(String text) async {
    if (_isMuted || text.isEmpty) return;
    setState(() => _isSpeaking = true);
    // Try custom Samantha voice first (XTTS v2, no external API)
    final success = await _speakSamanthaVoice(text);
    if (!success) {
      // Fallback to flutter_tts (device voice)
      await _flutterTts.speak(text);
    }
  }

  /// Detect if text is primarily Hindi (Devanagari script)
  String _detectLang(String text) {
    final devanagari = RegExp(r'[\u0900-\u097F]');
    final hindiChars = devanagari.allMatches(text).length;
    return hindiChars > text.length * 0.2 ? 'hi' : 'en';
  }

  Future<bool> _speakSamanthaVoice(String text) async {
    try {
      // Trim long responses — edge-tts is fast but keep it snappy
      final ttsText = text.length > 280
          ? '${text.substring(0, text.lastIndexOf(' ', 280))}...'
          : text;

      final lang = _detectLang(ttsText);

      final response = await http.post(
        Uri.parse(LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': USER_ID,
          'action': 'tts',
          'text': ttsText,
          'lang': lang,  // 'en' → en-IN-NeerjaNeural, 'hi' → hi-IN-SwaraNeural
        }),
      ).timeout(const Duration(seconds: 20));  // edge-tts is fast, 20s is plenty

      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      final audioB64 = data['audio_b64'] as String?;
      if (audioB64 == null || audioB64.isEmpty) return false;

      final audioBytes = base64Decode(audioB64);
      await _playAudioBytes(audioBytes);
      return true;
    } catch (e) {
      debugPrint('[Samantha TTS] Custom voice failed: $e');
      return false;
    }
  }

  Future<void> _speakGoogleTTS(String text) async {
    try {
      final speakText = text.length > 600 ? '${text.substring(0, 600)}...' : text;
      final response = await http.post(
        Uri.parse('https://texttospeech.googleapis.com/v1/text:synthesize?key=$GOOGLE_TTS_KEY'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'input': {'text': speakText},
          'voice': {
            'languageCode': 'hi-IN',
            'name': 'hi-IN-Neural2-A',
            'ssmlGender': 'FEMALE'
          },
          'audioConfig': {
            'audioEncoding': 'MP3',
            'speakingRate': 0.95,
            'pitch': 2.0,
            'volumeGainDb': 2.0,
            'effectsProfileId': ['headphone-class-device']
          }
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final audioContent = data['audioContent'] as String;
        final audioBytes = base64Decode(audioContent);
        await _playAudioBytes(audioBytes);
      } else {
        await _flutterTts.speak(text);
        setState(() => _isSpeaking = false);
      }
    } catch (e) {
      await _flutterTts.speak(text);
      setState(() => _isSpeaking = false);
    }
  }

  Future<void> _playAudioBytes(List<int> bytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/samantha_tts.mp3');
      await file.writeAsBytes(bytes);
      await _audioPlayer.setFilePath(file.path);
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('Audio play error: $e');
      setState(() => _isSpeaking = false);
    }
  }

  Future<void> _stopSpeaking() async {
    await _flutterTts.stop();
    await _audioPlayer.stop();
    setState(() => _isSpeaking = false);
  }

  Future<void> _startListening() async {
    if (!_sttAvailable) {
      _sttAvailable = await _stt.initialize();
      if (!_sttAvailable) return;
    }
    await _stopSpeaking();
    setState(() { _isListening = true; _liveText = ''; _micLevel = 0.0; });
    await _stt.listen(
      onResult: (result) {
        setState(() => _liveText = result.recognizedWords);
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          _sendMessage(result.recognizedWords);
        }
      },
      onSoundLevelChange: (level) {
        setState(() => _micLevel = ((level + 2) / 12).clamp(0.0, 1.0));
      },
      listenFor: const Duration(seconds: 120),
      pauseFor: const Duration(seconds: 6),
      localeId: 'en_IN',
    );
  }

  Future<void> _stopListening() async {
    await _stt.stop();
    setState(() { _isListening = false; _micLevel = 0.0; });
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
        backgroundColor: Color(0xFF1A1A24),
      ),
    );
  }

  Future<void> _sendFeedback(String msgId, int rating) async {
    setState(() => _feedback[msgId] = rating);
    // Find the message and its preceding user message for context
    final msgIdx = _messages.indexWhere((m) => m['id'] == msgId);
    final responseText = msgIdx >= 0 ? (_messages[msgIdx]['text'] ?? '') as String : '';
    final userText = msgIdx > 0 ? (_messages[msgIdx - 1]['text'] ?? '') as String : '';
    try {
      await http.post(
        Uri.parse(LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': USER_ID,
          'action': 'feedback',
          'rating': rating == 1 ? 'up' : 'down',
          'message': userText,
          'response': responseText,
          'context': _messages[msgIdx]['agent'] ?? '',
        }),
      ).timeout(const Duration(seconds: 10));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(rating == 1 ? '👍 Feedback saved' : '👎 Noted — Samantha will improve'),
          duration: const Duration(seconds: 2),
          backgroundColor: rating == 1 ? const Color(0xFF00D4FF) : const Color(0xFF7C3AED),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {}
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    await _stopListening();
    _textController.clear();
    setState(() {
      _messages.add({'role': 'user', 'text': text, 'agent': ''});
      _isLoading = true;
      _liveText = '';
    });
    _scrollToBottom();
    _thinkController.repeat();

    // If doc attached, add it to this message and clear after sending
    final docText = _attachedDocText;
    final docName = _attachedDocName;
    if (docText != null) {
      setState(() { _attachedDocText = null; _attachedDocName = null; });
    }

    try {
      final payload = <String, dynamic>{
        'userId': USER_ID,
        'message': text,
        'session_id': _sessionId,
      };
      if (docText != null) {
        payload['doc_content'] = docText;
        payload['doc_name'] = docName ?? 'document';
      }
      final response = await http.post(
        Uri.parse(LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);
      // Defensive extraction — handle any Lambda error shape
      final reply = (data['reply'] as String?)?.isNotEmpty == true
          ? data['reply'] as String
          : (data['error'] as String?)?.isNotEmpty == true
              ? "Samantha hit a snag: ${(data['error'] as String).substring(0, 80)}. Try again!"
              : 'Try again in a moment — Samantha is thinking.';
      final planUpdated = data['plan_updated'] == true;
      final agentUsed = (data['agent'] ?? 'samantha_core') as String;

      _thinkController.stop();
      _thinkController.reset();
      setState(() {
        _messages.add({
          'role': 'samantha',
          'text': reply,
          'agent': agentUsed,
          'id': '${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}',
        });
        _isLoading = false;
      });
      _scrollToBottom();
      // Fire TTS async — don't block UI waiting for voice (HF Space can take 5-25s)
      _speak(reply);

      // If plan was rescheduled, show a banner prompting user to check Plan tab
      if (planUpdated && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.black, size: 16),
                SizedBox(width: 8),
                Text('Plan screen updated! Tap Plan tab to see.', style: TextStyle(color: Colors.black)),
              ],
            ),
            backgroundColor: const Color(0xFF00D4FF),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'OPEN',
              textColor: Colors.black,
              onPressed: () {
                // Navigate to plan tab (index 2) - handled via snackbar tap
              },
            ),
          ),
        );
      }
    } catch (e) {
      _thinkController.stop();
      _thinkController.reset();
      setState(() {
        _messages.add({'role': 'samantha', 'text': 'Connection hiccup — try again in a sec.', 'agent': ''});
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    if (_isMuted) _stopSpeaking();
  }

  void _toggleOrbMode() => setState(() => _isOrbMode = !_isOrbMode);

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'pdf', 'doc', 'docx', 'csv', 'json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      String content = '';
      if (file.bytes != null) {
        content = String.fromCharCodes(file.bytes!.where((b) => b >= 32 || b == 10 || b == 13));
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      }
      // Trim to 8000 chars to fit Lambda context
      if (content.length > 8000) content = content.substring(0, 8000) + '... [truncated]';
      setState(() {
        _attachedDocText = content;
        _attachedDocName = file.name;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read file: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _applyChip(String prompt) {
    _textController.text = prompt;
    _textController.selection = TextSelection.fromPosition(
      TextPosition(offset: prompt.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _isOrbMode ? _buildFullScreenOrb() : _buildChatMode();
  }

  // ─── FULL SCREEN NEURAL ORB ───────────────────────────────────────────────

  Widget _buildFullScreenOrb() {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [

          // Ambient background glow
          AnimatedBuilder(
            animation: Listenable.merge([_orbFloatController, _speakWaveController]),
            builder: (context, _) {
              final glowR = _isListening
                  ? (size.width * 0.9) + (_micLevel * 100)
                  : _isSpeaking
                      ? (size.width * 0.85) + (_speakWaveController.value * 70)
                      : size.width * 0.75;
              final glowC = _isListening
                  ? const Color(0xFF0055CC)
                  : _isSpeaking
                      ? const Color(0xFF5511AA)
                      : _isLoading
                          ? const Color(0xFF3300AA)
                          : const Color(0xFF002277);
              return Center(
                child: Container(
                  width: glowR, height: glowR,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      glowC.withOpacity(0.20),
                      glowC.withOpacity(0.07),
                      Colors.transparent,
                    ], stops: const [0.0, 0.5, 1.0]),
                  ),
                ),
              );
            },
          ),

          // Expanding particle rings
          ..._buildExpandingRings(size),

          // Central orb
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_orbFloatController, _speakWaveController, _thinkController]),
              builder: (context, _) {
                final floatY = math.sin(_orbFloatController.value * math.pi) * 14;
                final micPulse = _isListening ? (1.0 + _micLevel * 0.45) : 1.0;
                final speakPulse = _isSpeaking
                    ? (1.0 + math.sin(_speakWaveController.value * math.pi) * 0.10)
                    : 1.0;
                return Transform.translate(
                  offset: Offset(0, floatY),
                  child: Transform.scale(
                    scale: micPulse * speakPulse,
                    child: _buildNeuralOrb(size),
                  ),
                );
              },
            ),
          ),

          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: _toggleOrbMode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.15)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.chat_bubble_outline, size: 13, color: Colors.white60),
                        SizedBox(width: 6),
                        Text('Chat', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      ]),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _isListening ? 'Listening...'
                          : _isLoading ? 'Thinking...'
                          : _isSpeaking ? 'Speaking...'
                          : 'Samantha',
                      key: ValueKey(_isListening ? 'l' : _isLoading ? 't' : _isSpeaking ? 's' : 'i'),
                      style: TextStyle(
                        color: _isListening ? const Color(0xFF00D4FF)
                            : _isSpeaking ? const Color(0xFFAA88FF)
                            : _isLoading ? const Color(0xFF7C3AED)
                            : Colors.white38,
                        fontSize: 13,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _toggleMute,
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: _isMuted
                            ? const Color(0xFF7C3AED).withOpacity(0.3)
                            : Colors.white.withOpacity(0.08),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isMuted ? const Color(0xFF7C3AED) : Colors.white.withOpacity(0.15),
                        ),
                      ),
                      child: Icon(
                        _isMuted ? Icons.volume_off : Icons.volume_up,
                        size: 16,
                        color: _isMuted ? const Color(0xFF7C3AED) : Colors.white54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Samantha reply text
          Positioned(
            left: 28, right: 28, bottom: 190,
            child: Builder(builder: (context) {
              final lastSam = _messages.lastWhere(
                (m) => m['role'] == 'samantha', orElse: () => {},
              );
              if (lastSam.isEmpty) return const SizedBox.shrink();
              return AnimatedOpacity(
                opacity: _isSpeaking ? 0.9 : 0.4,
                duration: const Duration(milliseconds: 400),
                child: Text(
                  lastSam['text'] ?? '',
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.65,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              );
            }),
          ),

          // Live voice text
          if (_liveText.isNotEmpty)
            Positioned(
              left: 28, right: 28, bottom: 295,
              child: Text(
                _liveText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF00D4FF),
                  fontSize: 14,
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

          // Bottom mic button
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 44),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _isListening ? _stopListening : _startListening,
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (ctx, child) => Transform.scale(
                          scale: _isListening ? _pulseAnimation.value : 1.0,
                          child: Container(
                            width: 80, height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isListening
                                  ? const Color(0xFF00D4FF)
                                  : Colors.white.withOpacity(0.10),
                              border: Border.all(
                                color: _isListening
                                    ? const Color(0xFF00D4FF)
                                    : Colors.white.withOpacity(0.25),
                                width: 2,
                              ),
                              boxShadow: _isListening
                                  ? [BoxShadow(
                                      color: const Color(0xFF00D4FF).withOpacity(0.55),
                                      blurRadius: 30, spreadRadius: 8)]
                                  : [],
                            ),
                            child: Icon(
                              _isListening ? Icons.stop_rounded : Icons.mic,
                              color: _isListening ? Colors.black : Colors.white70,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isListening ? 'Tap to stop' : 'Tap to speak',
                      style: const TextStyle(color: Colors.white30, fontSize: 12, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNeuralOrb(Size size) {
    final orbSize = size.width * 0.60;
    final c1 = _isListening ? const Color(0xFF00DDFF)
        : _isSpeaking ? const Color(0xFFCC99FF)
        : _isLoading ? const Color(0xFF9966EE)
        : const Color(0xFF4477FF);
    final c2 = _isListening ? const Color(0xFF0033BB)
        : _isSpeaking ? const Color(0xFF6600CC)
        : _isLoading ? const Color(0xFF330099)
        : const Color(0xFF001188);

    return SizedBox(
      width: orbSize + 60,
      height: orbSize + 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow
          Container(
            width: orbSize + 60,
            height: orbSize + 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: c1.withOpacity(0.35), blurRadius: 70, spreadRadius: 20),
                BoxShadow(color: c2.withOpacity(0.25), blurRadius: 110, spreadRadius: 40),
              ],
            ),
          ),

          // Thinking spinner
          if (_isLoading)
            Transform.rotate(
              angle: _thinkController.value * 2 * math.pi,
              child: Container(
                width: orbSize + 40,
                height: orbSize + 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(colors: [
                    Colors.transparent,
                    const Color(0xFFAA88FF).withOpacity(0.85),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),

          // Core orb
          Container(
            width: orbSize,
            height: orbSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.3),
                colors: [c1, c1.withOpacity(0.65), c2, Colors.black.withOpacity(0.85)],
                stops: const [0.0, 0.28, 0.65, 1.0],
              ),
            ),
          ),

          // Highlight glint
          Positioned(
            top: orbSize * 0.09,
            left: orbSize * 0.19,
            child: Container(
              width: orbSize * 0.22,
              height: orbSize * 0.10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(50),
                gradient: LinearGradient(colors: [
                  Colors.white.withOpacity(0.50),
                  Colors.transparent,
                ]),
              ),
            ),
          ),

          // Wave bars when speaking
          if (_isSpeaking)
            AnimatedBuilder(
              animation: _speakWaveController,
              builder: (context, _) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(9, (i) {
                    final phase = (i / 9) * math.pi;
                    final h = (orbSize * 0.10) +
                        (orbSize * 0.22) *
                            math.sin(_speakWaveController.value * math.pi + phase).abs();
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      width: 4,
                      height: h,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                );
              },
            ),
        ],
      ),
    );
  }

  List<Widget> _buildExpandingRings(Size size) {
    if (!_isListening && !_isSpeaking) return [];
    return List.generate(3, (i) {
      return AnimatedBuilder(
        animation: _micRingController,
        builder: (context, _) {
          final progress = (_micRingController.value + i / 3) % 1.0;
          final ringSize = (size.width * 0.45) + (progress * size.width * 0.7);
          final opacity = _isListening
              ? (1.0 - progress) * _micLevel * 0.55
              : (1.0 - progress) * 0.22;
          final color = _isListening
              ? const Color(0xFF00D4FF)
              : const Color(0xFFAA88FF);
          return Center(
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Container(
                width: ringSize, height: ringSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.0),
                ),
              ),
            ),
          );
        },
      );
    });
  }

  // ─── CHAT MODE ────────────────────────────────────────────────────────────

  Widget _buildChatMode() {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131A),
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isSpeaking ? const Color(0xFF7C3AED) : const Color(0xFF00D4FF),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Samantha',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            if (_isSpeaking) ...[
              const SizedBox(width: 8),
              const Text('speaking...',
                  style: TextStyle(fontSize: 11, color: Color(0xFF7C3AED))),
            ]
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up,
                color: _isMuted ? const Color(0xFF7C3AED) : Colors.white54, size: 20),
            onPressed: _toggleMute,
          ),
          IconButton(
            icon: const Icon(Icons.radio_button_checked,
                color: Color(0xFF00D4FF), size: 22),
            tooltip: 'Voice mode',
            onPressed: _toggleOrbMode,
          ),
          if (_isSpeaking)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined, color: Color(0xFF7C3AED)),
              onPressed: _stopSpeaking,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF2A2A3A)),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == _messages.length && _isLoading) return _buildTypingIndicator();
                return _buildMessage(_messages[i]);
              },
            ),
          ),
          // Live voice transcript
          if (_liveText.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF16161F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00D4FF), width: 0.5),
              ),
              child: Text(_liveText,
                  style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 13)),
            ),

          // Attached doc indicator
          if (_attachedDocName != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.attach_file, color: Color(0xFFF59E0B), size: 14),
                const SizedBox(width: 6),
                Expanded(child: Text(_attachedDocName!,
                    style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12),
                    overflow: TextOverflow.ellipsis)),
                GestureDetector(
                  onTap: () => setState(() { _attachedDocText = null; _attachedDocName = null; }),
                  child: const Icon(Icons.close, color: Color(0xFFF59E0B), size: 14),
                ),
              ]),
            ),

          // Quick-action chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(children: [
              _buildChip('📹 PKG Script', 'Create a Phokat Ka Gyan awareness script for today'),
              _buildChip('⚔️ Kurukshetra', 'Corporate Kurukshetra script — Chapter '),
              _buildChip('💡 Video Ideas', 'Give me 5 unique Phokat Ka Gyan video ideas about '),
              _buildChip('📝 Long Video', 'Help me plan a detailed YouTube video on '),
              _buildChip('🔍 Research', 'Research this topic and give me key facts for a video: '),
              _buildChip('🌐 Web Search', 'Search the web for latest news about '),
              _buildChip('📖 Doc Q&A', 'Based on the document I uploaded, answer: '),
              _buildChip('🎯 Hook Line', 'Write 5 powerful hook lines for a video about '),
              _buildChip('📊 Analyse', 'Analyse my week and suggest improvements'),
            ]),
          ),

          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 28),
            decoration: const BoxDecoration(
              color: Color(0xFF13131A),
              border: Border(top: BorderSide(color: Color(0xFF2A2A3A))),
            ),
            child: Row(
              children: [
                // Attachment button
                GestureDetector(
                  onTap: _pickDocument,
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _attachedDocName != null
                          ? const Color(0xFFF59E0B).withOpacity(0.2)
                          : const Color(0xFF1A1A24),
                      border: Border.all(
                        color: _attachedDocName != null
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF2A2A3A),
                      ),
                    ),
                    child: Icon(Icons.attach_file,
                        color: _attachedDocName != null
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF7A7590),
                        size: 18),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A24),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF2A2A3A)),
                    ),
                    child: TextField(
                      controller: _textController,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 3,
                      minLines: 1,
                      decoration: const InputDecoration(
                        hintText: 'Ask anything — research, scripts, plans...',
                        hintStyle: TextStyle(color: Color(0xFF7A7590), fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: _sendMessage,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _sendMessage(_textController.text),
                  child: Container(
                    width: 42, height: 42,
                    decoration: const BoxDecoration(color: Color(0xFF7C3AED), shape: BoxShape.circle),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isListening ? _stopListening : _startListening,
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (ctx, child) => Transform.scale(
                      scale: _isListening ? _pulseAnimation.value : 1.0,
                      child: Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isListening ? const Color(0xFF00D4FF) : const Color(0xFF1A1A24),
                          border: Border.all(color: const Color(0xFF00D4FF), width: 2),
                          boxShadow: _isListening
                              ? [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.4),
                                  blurRadius: 16, spreadRadius: 4)]
                              : [],
                        ),
                        child: Icon(
                          _isListening ? Icons.stop : Icons.mic,
                          color: _isListening ? Colors.black : const Color(0xFF00D4FF),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, String prompt) {
    return GestureDetector(
      onTap: () => _applyChip(prompt),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF16161F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2A2A3A)),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 12, color: Color(0xFFB0B0C8))),
      ),
    );
  }

  // Maps agent name → badge label + color
  Map<String, Map<String, dynamic>> get _agentBadges => {
    'research_agent':   {'label': '🔍 Jarvis Research',  'color': const Color(0xFF5FB8A0)},
    'planner_agent':    {'label': '📅 Jarvis Planner',   'color': const Color(0xFF7C3AED)},
    'reflection_agent': {'label': '🪞 Jarvis Reflect',   'color': const Color(0xFFC9A96E)},
    'habit_agent':      {'label': '🔥 Habit Logged',     'color': const Color(0xFFE07070)},
    'reschedule':       {'label': '⚡ Plan Rescheduled', 'color': const Color(0xFF00D4FF)},
  };

  Widget _buildMessage(Map<String, dynamic> msg) {
    final isSamantha = msg['role'] == 'samantha';
    final agent = (msg['agent'] ?? '') as String;
    final badge = _agentBadges[agent];

    return Align(
      alignment: isSamantha ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.80),
        child: Column(
          crossAxisAlignment: isSamantha ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            if (isSamantha) ...[
              // Agent badge — shows when a Jarvis agent handled the message
              if (badge != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (badge['color'] as Color).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: (badge['color'] as Color).withOpacity(0.4)),
                    ),
                    child: Text(
                      badge['label'] as String,
                      style: TextStyle(
                        fontSize: 10,
                        color: badge['color'] as Color,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 4),
                  child: Text('Samantha',
                      style: TextStyle(fontSize: 10, color: Color(0xFF00D4FF), letterSpacing: 0.5)),
                ),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSamantha ? const Color(0xFF1A1A24) : const Color(0xFF7C3AED),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isSamantha ? 4 : 16),
                  bottomRight: Radius.circular(isSamantha ? 16 : 4),
                ),
                border: isSamantha
                    ? Border.all(
                        color: badge != null
                            ? (badge['color'] as Color).withOpacity(0.25)
                            : const Color(0xFF2A2A3A),
                      )
                    : null,
              ),
              child: Text(msg['text'] ?? '',
                  style: const TextStyle(fontSize: 14, height: 1.55)),
            ),
            if (isSamantha) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Copy
                    InkWell(
                      onTap: () => _copyMessage(msg['text'] ?? ''),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: const [
                            Icon(Icons.copy_rounded, size: 12, color: Color(0xFF4A4A6A)),
                            SizedBox(width: 3),
                            Text('Copy', style: TextStyle(fontSize: 10, color: Color(0xFF4A4A6A))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Thumbs up
                    InkWell(
                      onTap: () {
                        final id = msg['id'] as String?;
                        if (id != null) _sendFeedback(id, 1);
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          _feedback[msg['id']] == 1
                              ? Icons.thumb_up
                              : Icons.thumb_up_outlined,
                          size: 13,
                          color: _feedback[msg['id']] == 1
                              ? const Color(0xFF00D4FF)
                              : const Color(0xFF4A4A6A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Thumbs down
                    InkWell(
                      onTap: () {
                        final id = msg['id'] as String?;
                        if (id != null) _sendFeedback(id, -1);
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          _feedback[msg['id']] == -1
                              ? Icons.thumb_down
                              : Icons.thumb_down_outlined,
                          size: 13,
                          color: _feedback[msg['id']] == -1
                              ? const Color(0xFF7C3AED)
                              : const Color(0xFF4A4A6A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF2A2A3A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [_buildDot(0), const SizedBox(width: 5), _buildDot(150), const SizedBox(width: 5), _buildDot(300)],
        ),
      ),
    );
  }

  Widget _buildDot(int delayMs) {
    return AnimatedBuilder(
      animation: _orbFloatController,
      builder: (ctx, child) {
        final offset = math.sin((_orbFloatController.value * 2 * math.pi) + (delayMs / 300)) * 4;
        return Transform.translate(
          offset: Offset(0, offset),
          child: Container(width: 7, height: 7,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF7A7590))),
        );
      },
    );
  }
}
