import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Full-screen branded loading state shown while the app works out who is
/// signed in (see AuthGate) — replaces the plain spinner that used to sit
/// on this screen.
///
/// The logo fades and scales in once, then settles into a slow "breathing"
/// pulse for as long as loading continues. Both animations are plain
/// transforms on a single image, so this stays cheap on low-end phones.
/// If the device has "remove animations" turned on, the logo is shown
/// static instead.
class LogoLoadingScreen extends StatefulWidget {
  const LogoLoadingScreen({super.key});

  @override
  State<LogoLoadingScreen> createState() => _LogoLoadingScreenState();
}

class _LogoLoadingScreenState extends State<LogoLoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  late final Animation<double> _fade =
      CurvedAnimation(parent: _intro, curve: Curves.easeOut);
  late final Animation<double> _introScale = Tween<double>(
    begin: 0.85,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));
  late final Animation<double> _pulseScale = Tween<double>(
    begin: 1.0,
    end: 1.04,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    _intro.forward().whenComplete(() {
      if (mounted) _pulse.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Widget _logo() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: FractionallySizedBox(
        widthFactor: 0.85,
        child: Image.asset(
          'assets/images/branding/logo.png',
          fit: BoxFit.contain,
          // The source PNG is 2000x2000 (~16MB decoded). Decoding it at a
          // screen-appropriate size keeps the first frame quick, so the
          // fade-in doesn't start late or stutter.
          cacheWidth: 1000,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Semantics(
        label: 'Loading VirtuWatch',
        child: Center(
          child: reduceMotion
              ? _logo()
              : AnimatedBuilder(
                  animation: Listenable.merge([_intro, _pulse]),
                  child: _logo(),
                  builder: (context, child) => Opacity(
                    opacity: _fade.value,
                    child: Transform.scale(
                      scale: _introScale.value * _pulseScale.value,
                      child: child,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}