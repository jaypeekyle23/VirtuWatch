import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

/// Key used in [SharedPreferences] to remember that onboarding has been
/// shown once on this device, so [AuthGate] only presents it on a
/// genuine first launch.
const String onboardingSeenPrefsKey = 'has_seen_onboarding';

class _OnboardingPage {
  final String imagePath;
  final IconData fallbackIcon;
  final String title;
  final String body;
  const _OnboardingPage(
      this.imagePath, this.fallbackIcon, this.title, this.body);
}

const List<_OnboardingPage> _pages = [
  _OnboardingPage(
    'assets/images/onboarding/wrist_measure.jpg',
    Icons.straighten_outlined,
    'Know Your Perfect Fit',
    'Measure your wrist size in seconds using just your phone\'s camera — no tape measure needed.',
  ),
  _OnboardingPage(
    'assets/images/onboarding/ar_try_on.jpg',
    Icons.view_in_ar_outlined,
    'Try It On, Virtually',
    'See any watch on your own wrist in real time with AR before you decide.',
  ),
  _OnboardingPage(
    'assets/images/onboarding/outfit_scan.jpg',
    Icons.checkroom_outlined,
    'Match Your Style',
    'Scan your outfit and get watch picks that actually match your colors and style.',
  ),
  _OnboardingPage(
    'assets/images/onboarding/style_match.jpg',
    Icons.auto_awesome_outlined,
    'Know Exactly Why It Fits',
    'Every watch comes with an AI style match score, based on your fit, style, and outfit.',
  ),
];

/// Shown once, on a device's genuine first launch, before [AuthGate]'s
/// normal login/session check. Purely a local UI preference (see
/// [onboardingSeenPrefsKey]) — has nothing to do with the user's account,
/// so it's stored on-device rather than in Firestore.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(onboardingSeenPrefsKey, true);
    } finally {
      widget.onDone();
    }
  }

  void _next() {
    if (_currentPage == _pages.length - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 20, 0),
                child: TextButton(
                  onPressed: _finishing ? null : _finish,
                  child: Text(
                    'Skip',
                    style: GoogleFonts.sora(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) => _pageView(_pages[index]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _currentPage ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _currentPage
                        ? AppTheme.gold
                        : AppTheme.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _finishing ? null : _next,
                  child: _finishing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isLastPage ? 'Get Started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageView(_OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: double.infinity,
            height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.gold, width: 1.5),
            ),
            // ClipRRect (rather than clipping the outer Container itself)
            // with a radius inset by the border width — clipping the
            // Container directly clips right up to the border stroke,
            // so the image's square corners cover the curve and the
            // border looks like it vanishes at each corner.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22.5),
              child: Image.asset(
                page.imagePath,
                fit: BoxFit.cover,
                // Falls back to the old icon treatment if the image asset
                // hasn't been added yet, so the screen never breaks —
                // just drop a matching file in assets/images/onboarding/
                // and it'll show up automatically, no code change needed.
                errorBuilder: (context, error, stackTrace) => Container(
                  color: AppTheme.surface,
                  child: Icon(page.fallbackIcon,
                      color: AppTheme.gold, size: 60),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 24,
                ),
          ),
          const SizedBox(height: 14),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }
}