import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/features/permissions/data/permission_gateway.dart';
import 'package:mobile_cleaner/features/permissions/data/permission_preferences.dart';
import 'package:mobile_cleaner/features/permissions/domain/app_permission_status.dart';

class PermissionEducationScreen extends ConsumerStatefulWidget {
  const PermissionEducationScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Storage access'),
        ),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return switch (_state) {
      _PermissionViewState.checking || _PermissionViewState.requesting =>
        const _LoadingView(),
      _PermissionViewState.education => _PermissionMessage(
          key: const Key('permission_education'),
          icon: Icons.folder_copy_rounded,
          title: 'Allow access to your media',
          description:
              'Mobile Cleaner needs access to photos, videos, audio, and storage so it can show what is using space. Nothing is deleted without your approval.',
          primaryLabel: 'Allow access',
          onPrimary: _requestPermission,
          secondaryLabel: 'Not now',
          onSecondary: _leaveScreen,
        ),
      _PermissionViewState.granted => _PermissionMessage(
          key: const Key('permission_granted'),
          icon: Icons.verified_user_rounded,
          title: 'Access granted',
          description:
              'Mobile Cleaner can now analyze supported media and storage categories on this device.',
          primaryLabel: 'Continue',
          onPrimary: _leaveScreen,
        ),
      _PermissionViewState.denied => _PermissionMessage(
          key: const Key('permission_denied'),
          icon: Icons.info_rounded,
          title: 'Permission denied',
          description:
              'You can still use the app, but storage results will be limited. You can try again whenever you are ready.',
          primaryLabel: 'Try again',
          onPrimary: _requestPermission,
          secondaryLabel: 'Continue without access',
          onSecondary: _leaveScreen,
        ),
      _PermissionViewState.permanentlyDenied => _PermissionMessage(
          key: const Key('permission_permanently_denied'),
          icon: Icons.settings_rounded,
          title: 'Permission blocked',
          description:
              'Android will no longer show the permission prompt. Open system settings to allow media and storage access.',
          primaryLabel: 'Open settings',
          onPrimary: _openSettings,
          secondaryLabel: 'Continue without access',
          onSecondary: _leaveScreen,
        ),
    };
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _PermissionMessage extends StatelessWidget {
  const _PermissionMessage({
    required this.icon,
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 144,
              height: 144,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 68, color: colors.primary),
            ),
            const SizedBox(height: 36),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton(
              key: const Key('permission_primary_action'),
              onPressed: onPrimary,
              child: Text(primaryLabel),
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
      ),
    );
  }
}

enum _PermissionViewState {
  checking,
  education,
  requesting,
  granted,
  denied,
  permanentlyDenied,
}
