import 'package:flutter/material.dart';

import '../models/user_prefs.dart';
import '../services/gemma_service.dart';
import '../services/prefs_service.dart';

/// First-launch onboarding. Three steps:
///   1. Welcome + name input
///   2. Download prompt (1.5 GB explainer, single tap to start)
///   3. Download/loading progress (in-flight)
///
/// Background work happens in parallel with the UI:
///   - As soon as the user finishes step 1, [ensureInstalled] starts.
///   - As soon as it finishes (or model is already on disk), [ensureLoaded]
///     starts. Progress is reflected via GemmaService.state +
///     GemmaService.downloadProgress.
///   - When state == ready, we mark prefs.onboardingCompleted and pop
///     to the chat screen.
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

  @override
  void initState() {
    super.initState();
    // Listen for model ready so we can auto-advance to "done" state.
    GemmaService.instance.state.addListener(_onGemmaStateChange);
  }

  @override
  void dispose() {
    GemmaService.instance.state.removeListener(_onGemmaStateChange);
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onGemmaStateChange() {
    if (!mounted) return;
    final state = GemmaService.instance.state.value;
    if (state == GemmaState.ready && _currentStep == 2) {
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

    // We sequence the downloads but parallelize what makes sense:
    //   1. ensureInstalled() — downloads Gemma 4 E2B (1.5 GB)
    //   2. ensureLoaded() — pushes weights to GPU (~10-18s, NO disk I/O)
    //   3. installEmbedder() — downloads Gecko 110M (110 MB)
    //
    // Steps 2 and 3 run concurrently: GPU loading the inference model
    // doesn't touch the network, and downloading the embedder doesn't
    // touch the GPU. Net effect: the embedder download is hidden by the
    // model load wait that the user would see anyway. Free 7s saving.

    try {
      // Step 1: download + register inference model.
      await GemmaService.instance.ensureInstalled();

      // Step 2 + 3 in parallel.
      final loadFuture = GemmaService.instance.ensureLoaded();
      final embedderFuture = GemmaService.instance.installEmbedder();

      // We await both. If either throws, the catch block handles it.
      // Use Future.wait with eagerError:false so a slow embedder doesn't
      // mask a load error and vice versa — we'll see whichever finishes
      // first via state listeners.
      await Future.wait([loadFuture, embedderFuture], eagerError: false);
    } catch (e) {
      // Errors propagate via GemmaService.state -> we render an error
      // banner on step 3. Nothing else to do here.
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
                // Pre-warm: trigger bootstrap as soon as the user has named
                // themselves. Even if they sit on step 2 for a while, the
                // download starts. We re-call on step 3 but that's a no-op.
                _startBootstrap();
                _goToStep(1);
              },
            ),
            _DownloadExplainerStep(
              onStartDownload: () {
                _startBootstrap();
                _goToStep(2);
              },
            ),
            _ProgressStep(
              name: _nameController.text.trim(),
              onRetry: () {
                _bootstrapStarted = false;
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
          const Text('🐾', style: TextStyle(fontSize: 64)),
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
            decoration: InputDecoration(
              hintText: 'Your name (optional)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
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
          Icon(
            Icons.cloud_download_outlined,
            size: 64,
            color: theme.colorScheme.primary,
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
            body: 'Claw is about 1.5 GB. It downloads once, then runs '
                'entirely offline.',
          ),
          const SizedBox(height: 12),
          _Bullet(
            icon: Icons.wifi_outlined,
            title: 'Use Wi-Fi if you can',
            body: 'Cellular works but uses your data. We pause if the '
                'connection drops.',
          ),
          const SizedBox(height: 12),
          _Bullet(
            icon: Icons.lock_outline,
            title: 'Private by design',
            body: 'Your conversations stay on this device. Nothing is '
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
  const _Bullet({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.primary),
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
  const _ProgressStep({required this.name, required this.onRetry});

  final String name;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ValueListenableBuilder<GemmaState>(
        valueListenable: GemmaService.instance.state,
        builder: (context, state, _) {
          final isError = state == GemmaState.error;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Icon(
                isError ? Icons.error_outline : Icons.psychology_outlined,
                size: 64,
                color: isError
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                isError ? 'Something went wrong' : _titleFor(state, name),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isError
                    ? "Couldn't download Claw. Check your connection and try again."
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
                        progress > 0 ? '$progress%' : 'Connecting…',
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
      ),
    );
  }

  String _titleFor(GemmaState state, String name) {
    final greeting = name.isEmpty ? 'Almost ready' : 'Almost ready, $name';
    switch (state) {
      case GemmaState.installing:
        return 'Downloading Claw';
      case GemmaState.loading:
      case GemmaState.installed:
        return 'Loading Claw';
      case GemmaState.ready:
      case GemmaState.generating:
        return greeting;
      default:
        return greeting;
    }
  }

  String _subtitleFor(GemmaState state) {
    final embedder = GemmaService.instance.embedderState.value;
    switch (state) {
      case GemmaState.installing:
        return "We're fetching Claw's main brain (1.5 GB). This takes a few minutes — feel free to leave the screen on.";
      case GemmaState.loading:
      case GemmaState.installed:
        if (embedder == EmbedderState.installing) {
          return "Bringing Claw to life and downloading the document understanding brain (110 MB) in parallel…";
        }
        return 'Bringing Claw to life. Just a few seconds…';
      case GemmaState.ready:
      case GemmaState.generating:
        if (embedder == EmbedderState.installing) {
          return 'Almost done — finishing the document understanding download…';
        }
        return 'Tap to start chatting.';
      default:
        return 'Setting things up…';
    }
  }
}
