import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../i18n.dart';

/// Kill switch: `--dart-define=SPLASH_ANIMATION=false`. Off by default under
/// MOCK_AUTH so UAT and widget runs are not delayed by it.
const bool kSplashAnimation = bool.fromEnvironment(
  'SPLASH_ANIMATION',
  defaultValue: !bool.fromEnvironment('MOCK_AUTH'),
);

// Light system dark mode: near-black ground, Volt accents.
const _bg0 = Color(0xFF090A0A);
const _bg1 = Color(0xFF151716);
const _teal = Color(0xFFC8F04A); // Volt
const _sky = Color(0xFFE6F7A8); // pale Volt

/// Total length of the logo animation, in seconds.
const double kSplashLogoSeconds = 1.9;
const double _total = 2.6;

double _clamp(double v) => v.clamp(0.0, 1.0);
double _seg(double t, double a, double b) => _clamp((t - a) / (b - a));
double _easeOut(double p) => 1 - math.pow(1 - p, 3).toDouble();
double _easeOutBack(double p) {
  const c1 = 1.70158, c3 = c1 + 1;
  return 1 + c3 * math.pow(p - 1, 3) + c1 * math.pow(p - 1, 2);
}

double _bounce(double x) {
  const n1 = 7.5625, d1 = 2.75;
  if (x < 1 / d1) return n1 * x * x;
  if (x < 2 / d1) return n1 * (x -= 1.5 / d1) * x + 0.75;
  if (x < 2.5 / d1) return n1 * (x -= 2.25 / d1) * x + 0.9375;
  return n1 * (x -= 2.625 / d1) * x + 0.984375;
}

/// The line under "FitFlex Africa" on the splash: the English tagline in
/// English; in Swahili no line at all (owner 2026-10-19: "Pamoja tuna
/// nguvu" removed from the splash, nothing in its place).
String? splashTagline(FFLocale locale) =>
    locale.locale.languageCode == 'sw' ? null : locale.t('splash.tagline');

/// Plays once per cold start over [child], then fades away and is removed.
/// Tap to skip. With "reduce motion" it shows the finished logo briefly.
class KineticSplashGate extends StatefulWidget {
  const KineticSplashGate({
    super.key,
    required this.child,
    this.tagline,
    this.enabled = kSplashAnimation,
  });

  final Widget child;

  /// The line under "FitFlex Africa"; null shows no line (Swahili, owner
  /// 2026-10-19: "Pamoja tuna nguvu" removed, nothing in its place).
  final String? tagline;
  final bool enabled;

  @override
  State<KineticSplashGate> createState() => _KineticSplashGateState();
}

class _KineticSplashGateState extends State<KineticSplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _done = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _done = !widget.enabled;
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_total * 1000).round()),
    );
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _done = true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || _done) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      // Static logo for a moment, no motion.
      _c.value = kSplashLogoSeconds / _total;
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _done = true);
      });
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _skip() {
    if (!_done) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _skip,
            child: Semantics(
              label: 'FitFlex',
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = _c.value * _total;
                  // Fade the whole splash out over the last 0.35 s.
                  final out = 1 - _seg(t, _total - 0.35, _total);
                  return Opacity(
                    opacity: out,
                    child: _SplashFrame(t: t, tagline: widget.tagline),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SplashFrame extends StatelessWidget {
  const _SplashFrame({required this.t, this.tagline});

  final double t;
  final String? tagline;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final size = math.min(w * 0.62, 280.0);
    final textIn = _easeOut(_seg(t, 1.45, 2.0));
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_bg1, _bg0],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            KineticLogo(t: t, size: size),
            const SizedBox(height: 28),
            Opacity(
              opacity: textIn,
              child: Transform.translate(
                offset: Offset(0, (1 - textIn) * 14),
                child: Column(
                  children: [
                    const Text(
                      'FitFlex Africa',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    if (tagline case final line?) ...[
                      const SizedBox(height: 6),
                      Text(
                        line,
                        style: const TextStyle(
                          color: _teal,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The real logo, split into pin + runner layers, animated as a pure function
/// of [t] seconds: pin drops and lands, runner dashes in with ghosts and speed
/// lines, arm flexes, then it settles into the exact artwork.
class KineticLogo extends StatelessWidget {
  const KineticLogo({super.key, required this.t, this.size = 280});

  final double t;
  final double size;

  @override
  Widget build(BuildContext context) {
    final u = size / 300;

    // 1. pin drop
    final dp = _clamp((t - 0.1) / 0.65);
    final pinY = dp < 1 ? (1 - _bounce(dp)) * -(560 * u) : 0.0;
    final land = _seg(t, 0.62, 0.74) * (1 - _seg(t, 0.74, 1.05));
    final pinOp = _seg(t, 0.1, 0.22);

    // 2. runner dash
    final rp = _seg(t, 0.55, 1.3);
    final rx = (1 - _easeOutBack(rp)) * -(700 * u);
    final skew = (1 - _easeOut(rp)) * -16 * math.pi / 180;
    final blur = (1 - _easeOut(rp)) * 7;
    final rOp = _seg(t, 0.55, 0.7);

    // 3. flex
    final fp = _seg(t, 1.25, 1.85);
    final pulse = math.sin(fp * math.pi);
    final flex = 1 + 0.055 * pulse;

    // 4. idle breathing
    final idle = _seg(t, kSplashLogoSeconds, kSplashLogoSeconds + 0.6);
    final bob = math.sin(t * 1.6) * 3 * u * idle;

    final rip = _seg(t, 0.68, 1.5);

    Widget layer(String name, {double opacity = 1, double blurSigma = 0}) {
      Widget img = Image.asset(
        'assets/brand/$name.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
      if (blurSigma > 0.05) {
        img = ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
          ),
          child: img,
        );
      }
      return Opacity(opacity: _clamp(opacity), child: img);
    }

    final pinWidget = Transform.translate(
      offset: Offset(0, pinY),
      child: Transform(
        alignment: const Alignment(0, 0.84),
        transform: Matrix4.diagonal3Values(1 + 0.07 * land, 1 - 0.1 * land, 1),
        child: Stack(
          children: [
            // Rim light so the navy pin reads on the dark background.
            ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Color(0xFFE6F7A8),
                BlendMode.srcATop,
              ),
              child: layer('logo-pin', opacity: pinOp * 0.55, blurSigma: 3),
            ),
            layer('logo-pin', opacity: pinOp),
          ],
        ),
      ),
    );

    Widget runner({
      double opacity = 1,
      double sigma = 0,
      double extraX = 0,
      double scale = 1,
    }) {
      return Transform.translate(
        offset: Offset(rx + extraX, 0),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.skewX(skew),
          child: Transform.scale(
            scale: scale,
            alignment: const Alignment(0.44, -0.24),
            child: layer('logo-runner', opacity: opacity, blurSigma: sigma),
          ),
        ),
      );
    }

    return Transform.translate(
      offset: Offset(0, bob),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // stage light
            Positioned(
              left: -size * 0.22,
              top: -size * 0.22,
              right: -size * 0.22,
              bottom: -size * 0.22,
              child: Opacity(
                opacity: _seg(t, 0, 0.9) * 0.9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _teal.withValues(alpha: 0.25),
                        _teal.withValues(alpha: 0.06),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.55, 0.75],
                    ),
                  ),
                ),
              ),
            ),
            // landing ripple
            if (rip > 0 && rip < 1)
              Positioned(
                left: size * 0.05,
                top: size * 0.80,
                width: size * 0.9,
                height: size * 0.22,
                child: Opacity(
                  opacity: (1 - rip) * 0.9,
                  child: Transform.scale(
                    scale: 0.15 + rip * 1.1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _teal, width: 2 * u),
                      ),
                    ),
                  ),
                ),
              ),
            pinWidget,
            // speed lines
            for (var i = 0; i < 4; i++) ..._speedLine(i, size, u),
            // runner ghosts
            for (var i = 0; i < 3; i++)
              if (rp < 1)
                runner(
                  opacity: rOp * [0.32, 0.2, 0.1][i] * (1 - rp),
                  sigma: 2.0 + i * 2,
                  extraX: -(i + 1) * 60 * u * (1 - rp),
                ),
            runner(opacity: rOp, sigma: blur, scale: flex),
            // bicep flash
            if (pulse > 0.01)
              Positioned(
                left: size * 0.73 - size * 0.17,
                top: size * 0.30 - size * 0.17,
                width: size * 0.34,
                height: size * 0.34,
                child: Opacity(
                  opacity: pulse * 0.85,
                  child: Transform.scale(
                    scale: 0.6 + pulse * 0.7,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Color(0xCCFFD36B),
                            Color(0x44F5B942),
                            Colors.transparent,
                          ],
                          stops: [0, 0.55, 1],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _speedLine(int i, double size, double u) {
    final p = _seg(t, 0.6 + i * 0.05, 1.15 + i * 0.05);
    final o = math.sin(p * math.pi);
    if (o <= 0.01) return const [];
    final y = [0.38, 0.46, 0.54, 0.62][i];
    return [
      Positioned(
        left: size * (-0.18 + i * 0.03),
        top: size * y,
        width: size * (0.30 - i * 0.03),
        height: math.max(2.0, 3 * u),
        child: Opacity(
          opacity: o * 0.8,
          child: Transform.scale(
            scaleX: 0.2 + p * 0.8,
            alignment: Alignment.centerRight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  colors: [Colors.transparent, i.isOdd ? _sky : _teal],
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}
