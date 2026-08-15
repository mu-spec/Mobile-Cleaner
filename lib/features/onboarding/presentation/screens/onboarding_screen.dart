import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/features/onboarding/data/onboarding_preferences.dart';
import 'package:mobile_cleaner/features/permissions/data/permission_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const List<_OnboardingPageData> _pages = <_OnboardingPageData>[
    _OnboardingPageData(
      title: 'Understand Your Storage',
      description: 'See what is using space on your phone with clear, useful categories.',
      icon: Icons.pie_chart_rounded,
    ),
    _OnboardingPageData(
      title: 'Clean Smarter',
      description: 'Find files worth reviewing and stay in control of everything you remove.',
      icon: Icons.auto_awesome_rounded,
    ),
    _OnboardingPageData(
      title: 'Private by Design',
      description: 'Your storage analysis stays on your device. Your files remain yours.',
      icon: Icons.shield_rounded,
    ),
  ];

  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isFinishing = false;

  bool get _isLastPage => _currentPage == _pages.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_isLastPage) {
      await _finish();
      return;
    }
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    if (_isFinishing) {
      return;
    }
    setState(() => _isFinishing = true);
    await OnboardingPreferences.markCompleted();
    final bool hasSeenPermissionEducation =
        await PermissionPreferences.isEducationSeen();
    if (mounted) {
      context.go(
        hasSeenPermissionEducation ? AppRoutes.home : AppRoutes.permissions,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('onboarding_skip'),
                  onPressed: _isFinishing ? null : _finish,
                  child: const Text('Skip'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (int index) {
                    setState(() => _currentPage = index);
                  },
                  itemBuilder: (BuildContext context, int index) {
                    return _OnboardingPage(data: _pages[index]);
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(_pages.length, (int index) {
                  final bool selected = index == _currentPage;
                  return AnimatedContainer(
                    key: Key('onboarding_indicator_$index'),
                    duration: const Duration(milliseconds: 200),
                    width: selected ? 28 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: selected ? colors.primary : colors.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  );
                }),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: FilledButton(
                  key: const Key('onboarding_next'),
                  onPressed: _isFinishing ? null : _next,
                  child: _isFinishing
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isLastPage ? 'Get started' : 'Next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.data});

  final _OnboardingPageData data;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 184,
            height: 184,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(data.icon, size: 84, color: colors.primary),
          ),
          const SizedBox(height: 48),
          Text(
            data.title,
            key: Key('onboarding_${data.title}'),
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            data.description,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: colors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;
}
