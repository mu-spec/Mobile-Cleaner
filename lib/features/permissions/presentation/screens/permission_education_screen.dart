import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/features/cleaner/domain/scan_launch_target.dart';
import 'package:mobile_cleaner/features/permissions/data/permission_gateway.dart';
import 'package:mobile_cleaner/features/permissions/data/permission_preferences.dart';
import 'package:mobile_cleaner/features/permissions/domain/app_permission_status.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class PermissionEducationScreen extends ConsumerStatefulWidget {
  const PermissionEducationScreen({this.scanTarget, super.key});

  final ScanLaunchTarget? scanTarget;

  @override
  ConsumerState<PermissionEducationScreen> createState() =>
      _PermissionEducationScreenState();
}

class _PermissionEducationScreenState
    extends ConsumerState<PermissionEducationScreen> {
  _PermissionViewState _state = _PermissionViewState.checking;

  @override
  void initState() {
    super.initState();
    _checkCurrentStatus();
  }

  Future<void> _checkCurrentStatus() async {
    try {
      final AppPermissionStatus status = await ref
          .read(permissionGatewayProvider)
          .checkMediaAndStorage();
      if (!mounted) {
        return;
      }
      setState(() {
        _state = switch (status) {
          AppPermissionStatus.granted => _PermissionViewState.granted,
          AppPermissionStatus.denied => _PermissionViewState.education,
          AppPermissionStatus.permanentlyDenied =>
            _PermissionViewState.permanentlyDenied,
        };
      });
    } catch (_) {
      if (mounted) {
        setState(() => _state = _PermissionViewState.education);
      }
    }
  }

  Future<void> _requestPermission() async {
    setState(() => _state = _PermissionViewState.requesting);
    try {
      final AppPermissionStatus status = await ref
          .read(permissionGatewayProvider)
          .requestMediaAndStorage();
      if (!mounted) {
        return;
      }
      setState(() {
        _state = switch (status) {
          AppPermissionStatus.granted => _PermissionViewState.granted,
          AppPermissionStatus.denied => _PermissionViewState.denied,
          AppPermissionStatus.permanentlyDenied =>
            _PermissionViewState.permanentlyDenied,
        };
      });
    } catch (_) {
      if (mounted) {
        setState(() => _state = _PermissionViewState.denied);
      }
    }
  }

  Future<void> _openSettings() async {
    await ref.read(permissionGatewayProvider).openSettings();
    await _checkCurrentStatus();
  }

  Future<void> _leaveScreen() async {
    await PermissionPreferences.markEducationSeen();
    if (!mounted) {
      return;
    }
    if (GoRouter.of(context).canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  void _goBack() {
    if (GoRouter.of(context).canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _continueAfterGrant() async {
    await PermissionPreferences.markEducationSeen();
    if (!mounted) {
      return;
    }
    final ScanLaunchTarget? target = widget.scanTarget;
    if (target == null) {
      await _leaveScreen();
      return;
    }
    context.replace(AppRoutes.progressForScan(target));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('permission_back_button'),
          tooltip: 'Back',
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Storage access'),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final _PermissionCopy copy = _permissionCopy(widget.scanTarget);
    return switch (_state) {
      _PermissionViewState.checking ||
      _PermissionViewState.requesting => const _LoadingView(),
      _PermissionViewState.education => _PermissionMessage(
        key: const Key('permission_education'),
        eyebrow: copy.eyebrow,
        icon: copy.icon,
        title: copy.title,
        description: copy.description,
        primaryLabel: 'Allow access',
        onPrimary: _requestPermission,
        secondaryLabel: 'Not now',
        onSecondary: _leaveScreen,
        warmAction: true,
      ),
      _PermissionViewState.granted => _PermissionMessage(
        key: const Key('permission_granted'),
        eyebrow: 'READY TO CONTINUE',
        icon: PhosphorIconsDuotone.shieldCheck,
        title: 'Access granted',
        description: copy.grantedDescription,
        primaryLabel: 'Continue',
        onPrimary: _continueAfterGrant,
      ),
      _PermissionViewState.denied => _PermissionMessage(
        key: const Key('permission_denied'),
        eyebrow: 'ACCESS NOT ENABLED',
        icon: PhosphorIconsDuotone.info,
        title: 'Permission denied',
        description:
            'Storage results will stay limited until access is allowed. '
            'You can try again whenever you are ready.',
        primaryLabel: 'Try again',
        onPrimary: _requestPermission,
        secondaryLabel: 'Continue without access',
        onSecondary: _leaveScreen,
      ),
      _PermissionViewState.permanentlyDenied => _PermissionMessage(
        key: const Key('permission_permanently_denied'),
        eyebrow: 'SYSTEM SETTINGS REQUIRED',
        icon: PhosphorIconsDuotone.gearSix,
        title: 'Permission blocked',
        description:
            'Android will no longer show the permission prompt. Open system '
            'settings to allow media and storage access.',
        primaryLabel: 'Open settings',
        onPrimary: _openSettings,
        secondaryLabel: 'Continue without access',
        onSecondary: _leaveScreen,
        warmAction: true,
      ),
    };
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[AppColors.actionBlue, AppColors.brandBlue],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.actionBlue.withValues(alpha: 0.28),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Padding(
              padding: EdgeInsets.all(27),
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Checking access...',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _PermissionMessage extends StatelessWidget {
  const _PermissionMessage({
    required this.eyebrow,
    required this.icon,
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.warmAction = false,
    super.key,
  });

  final String eyebrow;
  final IconData icon;
  final String title;
  final String description;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool warmAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
      child: Column(
        children: <Widget>[
          Container(
            key: const Key('permission_premium_hero'),
            width: double.infinity,
            height: 190,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[AppColors.brandBlue, AppColors.actionBlue],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.actionBlue.withValues(alpha: 0.24),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              children: <Widget>[
                Positioned(
                  right: -34,
                  top: -28,
                  child: _HeroRing(
                    size: 130,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                Positioned(
                  left: -22,
                  bottom: -38,
                  child: _HeroRing(
                    size: 112,
                    color: AppColors.cleanupOrange.withValues(alpha: 0.17),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          eyebrow,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(
                          icon,
                          size: 40,
                          color: AppColors.actionBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: dark ? AppColors.darkTextPrimary : AppColors.navy,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: dark ? AppColors.darkSurfaceElevated : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: dark ? AppColors.darkBorder : AppColors.border,
              ),
            ),
            child: const Column(
              children: <Widget>[
                _AccessBenefit(
                  icon: PhosphorIconsDuotone.lockKey,
                  title: 'Private and on-device',
                  subtitle: 'Your files are never uploaded.',
                ),
                Divider(height: 1, indent: 46),
                _AccessBenefit(
                  icon: PhosphorIconsDuotone.eye,
                  title: 'You stay in control',
                  subtitle: 'Review everything before cleaning.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              key: const Key('permission_primary_action'),
              style: FilledButton.styleFrom(
                backgroundColor: warmAction
                    ? AppColors.cleanupOrange
                    : AppColors.actionBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
                elevation: 0,
              ),
              onPressed: onPrimary,
              icon: Icon(
                primaryLabel == 'Continue'
                    ? PhosphorIconsDuotone.arrowRight
                    : PhosphorIconsDuotone.shieldCheck,
                size: 20,
              ),
              label: Text(
                primaryLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          if (secondaryLabel != null) ...<Widget>[
            const SizedBox(height: 8),
            TextButton(
              key: const Key('permission_secondary_action'),
              onPressed: onSecondary,
              child: Text(secondaryLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroRing extends StatelessWidget {
  const _HeroRing({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 18),
      ),
    );
  }
}

class _AccessBenefit extends StatelessWidget {
  const _AccessBenefit({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.softBlue,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: AppColors.actionBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCopy {
  const _PermissionCopy({
    required this.eyebrow,
    required this.icon,
    required this.title,
    required this.description,
    required this.grantedDescription,
  });

  final String eyebrow;
  final IconData icon;
  final String title;
  final String description;
  final String grantedDescription;
}

_PermissionCopy _permissionCopy(ScanLaunchTarget? target) => switch (target) {
  ScanLaunchTarget.photoCleanup ||
  ScanLaunchTarget.screenshots ||
  ScanLaunchTarget.duplicates => const _PermissionCopy(
    eyebrow: 'PHOTO ACCESS',
    icon: PhosphorIconsDuotone.imagesSquare,
    title: 'Allow access to your photos',
    description:
        'Find screenshots, duplicates, and large photos while keeping every '
        'decision in your hands.',
    grantedDescription:
        'Mobile Cleaner can now scan supported photos on this device.',
  ),
  ScanLaunchTarget.files ||
  ScanLaunchTarget.largeVideos => const _PermissionCopy(
    eyebrow: 'FILE ACCESS',
    icon: PhosphorIconsDuotone.folderOpen,
    title: 'Allow access to your files',
    description:
        'Review large files, downloads, videos, audio, and installers using '
        'real storage information from this device.',
    grantedDescription:
        'Mobile Cleaner can now scan supported file categories on this device.',
  ),
  ScanLaunchTarget.apps => const _PermissionCopy(
    eyebrow: 'APP ANALYSIS',
    icon: PhosphorIconsDuotone.squaresFour,
    title: 'Allow access before app analysis',
    description:
        'Connect installed-app insights with related storage cleanup while '
        'keeping all analysis on this device.',
    grantedDescription:
        'Mobile Cleaner can now analyze installed apps and related storage.',
  ),
  ScanLaunchTarget.smartScan => const _PermissionCopy(
    eyebrow: 'SMART CLEANUP',
    icon: PhosphorIconsDuotone.sparkle,
    title: 'Allow access for Smart Scan',
    description:
        'Scan supported storage categories and build safe cleanup suggestions '
        'from real files on this device.',
    grantedDescription:
        'Mobile Cleaner is ready to run a complete on-device Smart Scan.',
  ),
  null => const _PermissionCopy(
    eyebrow: 'PRIVATE ACCESS',
    icon: PhosphorIconsDuotone.shieldCheck,
    title: 'Allow media and storage access',
    description:
        'See what uses space and review supported files without uploading '
        'anything from this device.',
    grantedDescription: 'Mobile Cleaner can now analyze supported media and storage categories.',
  ),
};

enum _PermissionViewState {
  checking,
  education,
  requesting,
  granted,
  denied,
  permanentlyDenied,
}
