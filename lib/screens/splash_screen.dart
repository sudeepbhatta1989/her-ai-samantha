import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _masterController;
  late AnimationController _pulseController;
  late AnimationController _particleController;
  late AnimationController _scanController;

  final String _title = 'SAMANTHA';
  final List<double> _letterOpacity = [];
  final List<double> _letterOffset = [];
  bool _subtitleVisible = false;
  bool _taglineVisible = false;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < _title.length; i++) {
      _letterOpacity.add(0.0);
      _letterOffset.add(20.0);
    }

    _masterController = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..forward();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
    _particleController = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _scanController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

    for (int i = 0; i < _title.length; i++) {
      Future.delayed(Duration(milliseconds: 600 + i * 120), () {
        if (mounted) setState(() { _letterOpacity[i] = 1.0; _letterOffset[i] = 0.0; });
      });
    }
    Future.delayed(const Duration(milliseconds: 1800), () { if (mounted) setState(() => _subtitleVisible = true); });
    Future.delayed(const Duration(milliseconds: 2300), () { if (mounted) setState(() => _taglineVisible = true); });
    Future.delayed(const Duration(milliseconds: 4400), () {
      if (mounted) Navigator.of(context).pushReplacementNamed('/home');
    });
  }

  @override
  void dispose() {
    _masterController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06060F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: _particleController,
            builder: (_, __) => CustomPaint(painter: _NeuralParticlePainter(_particleController.value)),
          ),
          AnimatedBuilder(
            animation: _scanController,
            builder: (_, __) => CustomPaint(painter: _ScanLinePainter(_scanController.value)),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (_, __) {
                    final pulse = _pulseController.value;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        for (int r = 3; r >= 1; r--)
                          Container(
                            width: 80.0 + r * 28 + pulse * 12,
                            height: 80.0 + r * 28 + pulse * 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF7C3AED).withOpacity(0.08 * r * (0.5 + pulse * 0.5)),
                                width: 1.0,
                              ),
                            ),
                          ),
                        Container(
                          width: 110 + pulse * 6,
                          height: 110 + pulse * 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF00D4FF).withOpacity(0.3 + pulse * 0.2),
                              width: 1.5,
                            ),
                          ),
                        ),
                        Container(
                          width: 84 + pulse * 4,
                          height: 84 + pulse * 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Color.lerp(const Color(0xFF00D4FF), const Color(0xFF7C3AED), pulse)!,
                                const Color(0xFF7C3AED).withOpacity(0.6),
                                const Color(0xFF1A0A2E),
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.4 + pulse * 0.3), blurRadius: 30 + pulse * 20, spreadRadius: 2),
                              BoxShadow(color: const Color(0xFF7C3AED).withOpacity(0.3), blurRadius: 50, spreadRadius: 5),
                            ],
                          ),
                          child: Center(child: CustomPaint(size: const Size(40, 40), painter: _AIPainter(pulse))),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 44),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_title.length, (i) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutBack,
                      transform: Matrix4.translationValues(0, _letterOffset[i], 0),
                      child: AnimatedOpacity(
                        opacity: _letterOpacity[i],
                        duration: const Duration(milliseconds: 350),
                        child: Text(
                          _title[i],
                          style: TextStyle(
                            fontSize: 36, fontWeight: FontWeight.w200,
                            color: Colors.white, letterSpacing: 12,
                            shadows: [Shadow(color: const Color(0xFF00D4FF).withOpacity(0.6), blurRadius: 16)],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                AnimatedOpacity(
                  opacity: _subtitleVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 600),
                  child: const Text('YOUR PERSONAL AI',
                    style: TextStyle(fontSize: 11, color: Color(0xFF00D4FF), letterSpacing: 6, fontWeight: FontWeight.w400)),
                ),
                const SizedBox(height: 8),
                AnimatedOpacity(
                  opacity: _taglineVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 600),
                  child: Text('Think less. Live more.',
                    style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.35), letterSpacing: 2, fontStyle: FontStyle.italic)),
                ),
                const SizedBox(height: 60),
                AnimatedBuilder(
                  animation: _masterController,
                  builder: (_, __) => Column(
                    children: [
                      Container(
                        width: 160, height: 2,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: Colors.white.withOpacity(0.06)),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: _masterController.value,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF00D4FF)]),
                              boxShadow: [BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.5), blurRadius: 6)],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _masterController.value < 0.3 ? 'Initializing neural core...'
                            : _masterController.value < 0.6 ? 'Loading your life data...'
                            : _masterController.value < 0.85 ? 'Syncing with Jarvis...'
                            : 'Ready.',
                        style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.3), letterSpacing: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(top: 52, left: 24,
            child: AnimatedOpacity(opacity: _subtitleVisible ? 1.0 : 0.0, duration: const Duration(milliseconds: 800),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_hud('SYS.ONLINE'), const SizedBox(height: 4), _hud('AI.CORE.ACTIVE')]))),
          Positioned(top: 52, right: 24,
            child: AnimatedOpacity(opacity: _subtitleVisible ? 1.0 : 0.0, duration: const Duration(milliseconds: 800),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [_hud('v4.0.0'), const SizedBox(height: 4), _hud('HER.AI')]))),
          Positioned(bottom: 44, left: 24,
            child: AnimatedOpacity(opacity: _taglineVisible ? 1.0 : 0.0, duration: const Duration(milliseconds: 800),
              child: _hud('SUDEEP // USER.01'))),
          Positioned(bottom: 48, right: 24,
            child: AnimatedBuilder(animation: _pulseController, builder: (_, __) => Row(children: [
              _hud('LIVE'), const SizedBox(width: 6),
              Container(width: 6, height: 6, decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00FF88).withOpacity(0.6 + _pulseController.value * 0.4),
                boxShadow: [BoxShadow(color: const Color(0xFF00FF88).withOpacity(0.5), blurRadius: 6)],
              )),
            ]))),
        ],
      ),
    );
  }

  Widget _hud(String text) => Text(text,
    style: TextStyle(fontSize: 9, color: const Color(0xFF00D4FF).withOpacity(0.4), letterSpacing: 2, fontWeight: FontWeight.w500));
}

// ── Neural particle field ──
class _NeuralParticlePainter extends CustomPainter {
  final double t;
  static final _rng = math.Random(42);
  static final List<_Particle> _ps = List.generate(50, (_) => _Particle(_rng));
  _NeuralParticlePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    final positions = _ps.map((p) => Offset(
      ((p.x + p.vx * t * 60) % 1.0) * size.width,
      ((p.y + p.vy * t * 60) % 1.0) * size.height,
    )).toList();

    for (int i = 0; i < _ps.length; i++) {
      final p = _ps[i];
      paint.color = Color.lerp(const Color(0xFF7C3AED), const Color(0xFF00D4FF), p.colorT)!
          .withOpacity(p.opacity * (0.5 + 0.5 * math.sin(t * math.pi * 2 + p.phase)));
      paint.strokeWidth = p.size;
      canvas.drawPoints(ui.PointMode.points, [positions[i]], paint);

      for (int j = i + 1; j < _ps.length; j++) {
        final dist = (positions[i] - positions[j]).distance;
        if (dist < 90) {
          paint.color = const Color(0xFF7C3AED).withOpacity((1 - dist / 90) * 0.10);
          paint.strokeWidth = 0.5;
          canvas.drawLine(positions[i], positions[j], paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_NeuralParticlePainter o) => o.t != t;
}

class _Particle {
  final double x, y, vx, vy, size, opacity, colorT, phase;
  _Particle(math.Random r)
      : x = r.nextDouble(), y = r.nextDouble(),
        vx = (r.nextDouble() - 0.5) * 0.0015, vy = (r.nextDouble() - 0.5) * 0.0015,
        size = r.nextDouble() * 2 + 1, opacity = r.nextDouble() * 0.5 + 0.1,
        colorT = r.nextDouble(), phase = r.nextDouble() * math.pi * 2;
}

// ── Scan line ──
class _ScanLinePainter extends CustomPainter {
  final double t;
  _ScanLinePainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final y = t * size.height;
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, y - 40), Offset(0, y + 40),
        [Colors.transparent, const Color(0xFF00D4FF).withOpacity(0.06), const Color(0xFF00D4FF).withOpacity(0.10), const Color(0xFF00D4FF).withOpacity(0.06), Colors.transparent],
        [0, 0.3, 0.5, 0.7, 1.0],
      );
    canvas.drawRect(Rect.fromLTWH(0, y - 40, size.width, 80), paint);
  }
  @override
  bool shouldRepaint(_ScanLinePainter o) => o.t != t;
}

// ── AI orb symbol ──
class _AIPainter extends CustomPainter {
  final double pulse;
  _AIPainter(this.pulse);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final r = size.width * 0.22 + pulse * 2;
    for (int i = 0; i < 3; i++) {
      final angle = i * math.pi * 2 / 3;
      canvas.drawCircle(Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle)), r, paint);
    }
    paint.style = PaintingStyle.fill;
    paint.color = Colors.white.withOpacity(0.95);
    canvas.drawCircle(center, 3 + pulse * 1.5, paint);
  }
  @override
  bool shouldRepaint(_AIPainter o) => o.pulse != pulse;
}
