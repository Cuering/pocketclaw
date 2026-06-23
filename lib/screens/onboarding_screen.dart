import 'package:flutter/material.dart';
// import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../core/pocketclaw_theme.dart';
import '../core/status_words.dart';
import '../models/user_prefs.dart';
import '../services/device_actions_service.dart';
import '../services/gemma_service.dart';
// import '../services/overlay_controller_service.dart';
import '../services/prefs_service.dart';
import '../services/primitive_engine/primitive_engine.dart';

/// First-launch onboarding. Three steps:
///   1. Welcome + name input
///   2. Download prompt (1.5 GB explainer, single tap to start)
///   3. Download/loading progress (in-flight)
///
/// Setup starts only after the user taps "Download Claw". Onboarding does not
/// complete until both the chat model and the embedding model are ready.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  /// Called when onboarding completes. Parent routes to chat screen.
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final _nameController = TextEditingController();
  int _currentStep = 0;
  bool _bootstrapStarted = false;
  String _setupStatus = StatusWords.random();

  @override
  void initState() {
    super.initState();
    // Listen for model ready so we can auto-advance to "done" state.
    GemmaService.instance.state.addListener(_onGemmaStateChange);
    GemmaService.instance.embedderState.addListener(_onGemmaStateChange);
  }

  @override
  void dispose() {
    GemmaService.instance.state.removeListener(_onGemmaStateChange);
    GemmaService.instance.embedderState.removeListener(_onGemmaStateChange);
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onGemmaStateChange() {
    if (!mounted) return;
    final state = GemmaService.instance.state.value;
    final embedderState = GemmaService.instance.embedderState.value;
    if (state == GemmaState.ready &&
        embedderState == EmbedderState.installed &&
        _currentStep == 3) {
      _completeOnboarding();
    } else {
      // Force rebuild for progress UI
      setState(() {});
    }
  }

  Future<void> _completeOnboarding() async {
    final name = _nameController.text.trim();
    final prefs = UserPrefs(
      name: name.isEmpty ? null : name,
      onboardingCompleted: true,
      overlayEnabled: PrefsService.instance.current.overlayEnabled,
    );
    await PrefsService.instance.update(prefs);
    if (!mounted) return;
    widget.onDone();
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Kick off the model bootstrap in background. Idempotent — safe if
  /// already in flight or already done.
  Future<void> _startBootstrap() async {
    if (_bootstrapStarted) return;
    _bootstrapStarted = true;
    setState(() => _setupStatus = StatusWords.random());

    try {
      if (GemmaService.instance.state.value == GemmaState.error) {
        await GemmaService.instance.init();
      }
      // Step 1: download + register inference model.
      await GemmaService.instance.ensureInstalled();

      // Step 2 + 3 in parallel.
      final loadFuture = GemmaService.instance.ensureLoaded();
      final embedderFuture = GemmaService.instance.installEmbedder();

      await Future.wait([loadFuture, embedderFuture], eagerError: false);
    } catch (e) {
      debugPrint('🐾 ONBOARDING: bootstrap error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _WelcomeStep(
              nameController: _nameController,
              onNext: () {
                _goToStep(1);
              },
            ),
            _PermissionsStep(
              onNext: () {
                _goToStep(2);
              },
            ),
            _DownloadExplainerStep(
              onStartDownload: () {
                _startBootstrap();
                _goToStep(3);
              },
            ),
            _ProgressStep(
              status: _setupStatus,
              onRetry: () {
                _bootstrapStarted = false;
                _setupStatus = StatusWords.random();
                _startBootstrap();
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 1: Welcome + name ──────────────────────────────────────────────

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.nameController, required this.onNext});

  final TextEditingController nameController;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          DecoratedBox(
            decoration: PocketClawTheme.panel(
              color: PocketClawTheme.bg2,
              border: PocketClawTheme.cyan,
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/images/pocketclaw_icon.png',
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Meet Claw',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your private, on-device AI assistant. '
            'Everything stays on your phone — no servers, no tracking, '
            'no internet required after setup.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'What should Claw call you?',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Your name (optional)'),
            onSubmitted: (_) => onNext(),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onNext,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Continue'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Step 2: Download explainer ──────────────────────────────────────────

class _DownloadExplainerStep extends StatelessWidget {
  const _DownloadExplainerStep({required this.onStartDownload});

  final VoidCallback onStartDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          DecoratedBox(
            decoration: PocketClawTheme.panel(
              color: PocketClawTheme.bg3,
              border: PocketClawTheme.mint,
            ),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Icon(
                Icons.cloud_download_outlined,
                size: 44,
                color: PocketClawTheme.cyan,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Let's set up Claw",
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _Bullet(
            icon: Icons.download_outlined,
            title: 'One-time download',
            body:
                'Claw is powered by Gemma 4 — Google DeepMind’s open model. The brain is about 1.5 GB, downloads once, then runs '
                'entirely offline. No data leaves your phone.',
          ),
          const SizedBox(height: 12),
          _Bullet(
            icon: Icons.wifi_outlined,
            title: 'Use Wi-Fi if you can',
            body:
                'Cellular works but uses your data. We pause if the '
                'connection drops.',
          ),
          const SizedBox(height: 12),
          _Bullet(
            icon: Icons.lock_outline,
            title: 'Private by design',
            body:
                'Your conversations stay on this device. Nothing is '
                'sent to a server.',
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onStartDownload,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Download Claw'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: PocketClawTheme.panel(
            color: PocketClawTheme.bg3,
            border: PocketClawTheme.cyan,
            radius: 6,
            shadow: false,
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18, color: PocketClawTheme.cyan),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Step 3: Progress ────────────────────────────────────────────────────

class _ProgressStep extends StatelessWidget {
  const _ProgressStep({required this.status, required this.onRetry});

  final String status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ValueListenableBuilder<GemmaState>(
        valueListenable: GemmaService.instance.state,
        builder: (context, state, _) {
          return ValueListenableBuilder<EmbedderState>(
            valueListenable: GemmaService.instance.embedderState,
            builder: (context, embedderState, _) {
              final isError =
                  state == GemmaState.error ||
                  embedderState == EmbedderState.error;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  if (isError)
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: theme.colorScheme.error,
                    )
                  else
                    DecoratedBox(
                      decoration: PocketClawTheme.panel(
                        color: PocketClawTheme.bg2,
                        border: PocketClawTheme.cyan,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.asset(
                            'assets/images/pocketclaw_icon.png',
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    isError ? 'Something went wrong' : '$status...',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isError
                        ? "Couldn't finish setting up. Check your connection and try again."
                        : _subtitleFor(state),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (state == GemmaState.installing)
                    ValueListenableBuilder<int>(
                      valueListenable: GemmaService.instance.downloadProgress,
                      builder: (context, progress, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: progress > 0 ? progress / 100 : null,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            progress > 0 ? '$progress%' : 'Connecting...',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    )
                  else if (embedderState == EmbedderState.installing)
                    ValueListenableBuilder<int>(
                      valueListenable:
                          GemmaService.instance.embedderDownloadProgress,
                      builder: (context, progress, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: progress > 0 ? progress / 100 : null,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            progress > 0 ? '$progress%' : 'Connecting...',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    )
                  else if (!isError)
                    const LinearProgressIndicator(),
                  const Spacer(),
                  if (isError)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onRetry,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Retry'),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _subtitleFor(GemmaState state) {
    final embedder = GemmaService.instance.embedderState.value;
    switch (state) {
      case GemmaState.installing:
        return "Setting up Claw — powered by Gemma 4. This takes a moment…";
      case GemmaState.loading:
      case GemmaState.installed:
        if (embedder == EmbedderState.installing) {
          return "Almost ready. Setting things up so Claw can read documents too…";
        }
        return 'Almost ready. Just a few seconds…';
      case GemmaState.ready:
      case GemmaState.generating:
        if (embedder == EmbedderState.installing) {
          return 'Almost done — finishing the last bit of setup…';
        }
        return 'Tap to start chatting.';
      default:
        return 'Setting things up…';
    }
  }
}

class _PermissionsStep extends StatefulWidget {
  const _PermissionsStep({required this.onNext});

  final VoidCallback onNext;

  @override
  State<_PermissionsStep> createState() => _PermissionsStepState();
}

class _PermissionsStepState extends State<_PermissionsStep>
    with WidgetsBindingObserver {
  // ignore: unused_field
  bool _overlayGranted = false;
  bool _micGranted = false;
  // ignore: unused_field
  bool _cameraGranted = false;
  // ignore: unused_field
  bool _notificationGranted = false;
  bool _accessibilityGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    // final overlay = await FlutterOverlayWindow.isPermissionGranted();
    const overlay = false;
    final status = await DeviceActionsService.instance.checkAppPermissions();
    final accessibility = await PrimitiveEngine.instance.isAccessibilityEnabled();
    if (!mounted) return;
    setState(() {
      _overlayGranted = overlay;
      _micGranted = status['mic'] ?? false;
      _cameraGranted = status['camera'] ?? false;
      _notificationGranted = status['notifications'] ?? false;
      _accessibilityGranted = accessibility;
    });
  }

  // ignore: unused_element
  Future<void> _grantOverlay() async {
    // await OverlayControllerService.instance.ensurePermission();
    await _checkPermissions();
  }

  Future<void> _grantSystem() async {
    await DeviceActionsService.instance.requestAppPermissions();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _checkPermissions();
  }

  Future<void> _grantAccessibility() async {
    await PrimitiveEngine.instance.openAccessibilitySettings();
    // Grant detected on resume via didChangeAppLifecycleState
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Text(
            'Permissions',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'PocketClaw requires a few permissions to function natively. You can skip any and enable them later.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          // _PermissionRow(
          //   icon: Icons.open_in_new,
          //   title: 'Display Over Apps',
          //   description: 'Draw the floating bubble overlay.',
          //   granted: _overlayGranted,
          //   onGrant: _grantOverlay,
          // ),
          const SizedBox(height: 12),
          _PermissionRow(
            icon: Icons.mic_none,
            title: 'Microphone',
            description: 'For voice dictation inside the chat.',
            granted: _micGranted,
            onGrant: _grantSystem,
          ),
          const SizedBox(height: 12),
          _PermissionRow(
            icon: Icons.accessibility_new,
            title: 'Accessibility',
            description: 'Lets Claw tap, type, and read the screen to run skills.',
            granted: _accessibilityGranted,
            onGrant: _grantAccessibility,
          ),
          // const SizedBox(height: 12),
          // _PermissionRow(
          //   icon: Icons.camera_alt_outlined,
          //   title: 'Camera & Vision',
          //   description: 'For screenshot and vision analysis.',
          //   granted: _cameraGranted,
          //   onGrant: _grantSystem,
          // ),
          // const SizedBox(height: 12),
          // _PermissionRow(
          //   icon: Icons.notifications_none,
          //   title: 'Notifications',
          //   description: 'Draw background helper notification.',
          //   granted: _notificationGranted,
          //   onGrant: _grantSystem,
          // ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: widget.onNext,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Continue'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    required this.onGrant,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        DecoratedBox(
          decoration: PocketClawTheme.panel(
            color: PocketClawTheme.bg3,
            border: granted ? PocketClawTheme.mint : PocketClawTheme.cyan,
            radius: 8,
            shadow: false,
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 20,
              color: granted ? PocketClawTheme.mint : PocketClawTheme.cyan,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: TextButton(
            onPressed: granted ? null : onGrant,
            style: TextButton.styleFrom(
              foregroundColor: PocketClawTheme.cyan,
              disabledForegroundColor: PocketClawTheme.mint,
            ),
            child: Text(
              granted ? 'Active' : 'Grant',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: granted ? PocketClawTheme.mint : PocketClawTheme.cyan,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
