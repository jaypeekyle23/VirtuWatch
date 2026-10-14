import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/luxe.dart';

/// Key used in [SharedPreferences] to remember that onboarding has been
/// shown once on this device, so [AuthGate] only presents it on a
/// genuine first launch.
const String onboardingSeenPrefsKey = 'has_seen_onboarding';

/// (image asset, fallback icon, title, body). The icon shows if the image
/// asset hasn't been added yet, so the screen never breaks: drop a matching
/// file in assets/images/onboarding/ and it appears with no code change.
const _pages = [
  (
    'assets/images/onboarding/wrist_measure.jpg',
    Icons.straighten_outlined,
    'Know Your Perfect Fit',
    "Measure your wrist size in seconds using just your phone's camera — no tape measure needed.",
  ),
  (
    'assets/images/onboarding/ar_try_on.jpg',
    Icons.view_in_ar_outlined,
    'Try It On, Virtually',
    'See any watch on your own wrist in real time with AR before you decide.',
  ),
  (
    'assets/images/onboarding/outfit_scan.jpg',
    Icons.checkroom_outlined,
    'Match Your Style',
    'Scan your outfit and get watch picks that actually match your colors and style.',
  ),
  (
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
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: _finishing ? null : _finish,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Text('SKIP',
                      style: kLabelStyle.copyWith(color: AppTheme.textPrimary)),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, index) {
                  final (image, icon, title, body) = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 280,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Image.asset(
                            image,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Icon(
                                icon,
                                color: AppTheme.textSecondary,
                                size: 56),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(title, style: AppTheme.serif(size: 32)),
                        const SizedBox(height: 8),
                        Text(
                          body,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _currentPage ? 22 : 8,
                    height: 4,
                    decoration: BoxDecoration(
                      color: i == _currentPage
                          ? AppTheme.textPrimary
                          : AppTheme.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
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
}