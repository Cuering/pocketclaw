import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../core/pocketclaw_theme.dart';
import '../core/status_words.dart';
import '../models/user_prefs.dart';
import '../services/device_actions_service.dart';
import '../services/gemma_service.dart';
import '../services/overlay_controller_service.dart';
import '../services/prefs_service.dart';
import '../services/primitive_engine/primitive_engine.dart';

/// First-launch onboarding. Three steps:
///   1. Welcome + name input
///   2. Download prompt (1.5 GB explainer, single tap to start)
///   3. Download/loading progress (in-flight)
///
/// Setup starts only after the user taps "下载爪爪". Onboarding does not
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
            _权限Step(
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
              on重试: () {
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
            '认识爪爪',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '你的私有端侧 AI 助理。'
            '一切都留在手机上——无服务器、无追踪，'
            '设置完成后无需联网。',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            '希望爪爪怎么称呼你？',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(hintText: '你的名字（可选）'),
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
              child: const Text('继续'),
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
            "开始设置爪爪",
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _Bullet(
            icon: Icons.download_outlined,
            title: '一次性下载',
            body:
                '爪爪由 Gemma 4（Google DeepMind 开源模型）驱动。模型约 1.5 GB，下载一次后即可'
                '完全离线运行。数据不会离开你的手机。',
          ),
          const SizedBox(height: 12),
          _Bullet(
            icon: Icons.wifi_outlined,
            title: '尽量使用 Wi‑Fi',
            body:
                '移动网络也可以，但会消耗流量。连接中断时会'
                '暂停。',
          ),
          const SizedBox(height: 12),
          _Bullet(
            icon: Icons.lock_outline,
            title: '天生隐私',
            body:
                '对话只保存在本机。不会'
                '发送到服务器。',
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onStartDownload,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('下载爪爪'),
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
  const _ProgressStep({required this.status, required this.on重试});

  final String status;
  final VoidCallback on重试;

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
                    isError ? '出了点问题' : '$status...',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isError
                        ? "设置未能完成。请检查网络后重试。"
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
                            progress > 0 ? '$progress%' : '连接中…',
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
                            progress > 0 ? '$progress%' : '连接中…',
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
                        onPressed: on重试,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('重试'),
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
        return "正在设置爪爪（Gemma 4 驱动）。稍等片刻…";
      case GemmaState.loading:
      case GemmaState.installed:
        if (embedder == EmbedderState.installing) {
          return "快好了。正在配置文档理解能力…";
        }
        return '快好了。再等几秒…';
      case GemmaState.ready:
      case GemmaState.generating:
        if (embedder == EmbedderState.installing) {
          return '马上完成——正在收尾设置…';
        }
        return '点按开始聊天。';
      default:
        return '正在设置…';
    }
  }
}

class _权限Step extends StatefulWidget {
  const _权限Step({required this.onNext});

  final VoidCallback onNext;

  @override
  State<_权限Step> createState() => _权限StepState();
}

class _权限StepState extends State<_权限Step>
    with WidgetsBindingObserver {
  bool _overlay授权ed = false;
  bool _mic授权ed = false;
  // ignore: unused_field
  bool _camera授权ed = false;
  // ignore: unused_field
  bool _notification授权ed = false;
  bool _accessibility授权ed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check权限();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check权限();
    }
  }

  Future<void> _check权限() async {
    final overlay = await Flutter悬浮窗Window.isPermission授权ed();
    final status = await DeviceActionsService.instance.checkApp权限();
    final accessibility = await PrimitiveEngine.instance.is无障碍Enabled();
    if (!mounted) return;
    setState(() {
      _overlay授权ed = overlay;
      _mic授权ed = status['mic'] ?? false;
      _camera授权ed = status['camera'] ?? false;
      _notification授权ed = status['notifications'] ?? false;
      _accessibility授权ed = accessibility;
    });
  }

  Future<void> _grant悬浮窗() async {
    await 悬浮窗ControllerService.instance.ensurePermission();
    await _check权限();
  }

  Future<void> _grantSystem() async {
    await DeviceActionsService.instance.requestApp权限();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _check权限();
  }

  Future<void> _grant无障碍() async {
    await PrimitiveEngine.instance.open无障碍Settings();
    // 授权 detected on resume via didChangeAppLifecycleState
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
            '权限',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'PocketClaw 需要若干权限才能原生工作。可先跳过，之后再开启。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          _PermissionRow(
            icon: Icons.open_in_new,
            title: '显示在其他应用上层',
            description: '绘制悬浮气泡。',
            granted: _overlay授权ed,
            on授权: _grant悬浮窗,
          ),
          const SizedBox(height: 12),
          _PermissionRow(
            icon: Icons.mic_none,
            title: '麦克风',
            description: '用于聊天内语音输入。',
            granted: _mic授权ed,
            on授权: _grantSystem,
          ),
          const SizedBox(height: 12),
          _PermissionRow(
            icon: Icons.accessibility_new,
            title: '无障碍',
            description: '让爪爪点击、输入并读取屏幕以运行技能。',
            granted: _accessibility授权ed,
            on授权: _grant无障碍,
          ),
          // const SizedBox(height: 12),
          // _PermissionRow(
          //   icon: Icons.camera_alt_outlined,
          //   title: '相机与视觉',
          //   description: '用于截图与视觉分析。',
          //   granted: _camera授权ed,
          //   on授权: _grantSystem,
          // ),
          // const SizedBox(height: 12),
          // _PermissionRow(
          //   icon: Icons.notifications_none,
          //   title: '通知',
          //   description: '显示后台辅助通知。',
          //   granted: _notification授权ed,
          //   on授权: _grantSystem,
          // ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: widget.onNext,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('继续'),
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
    required this.on授权,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool granted;
  final VoidCallback on授权;

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
            onPressed: granted ? null : on授权,
            style: TextButton.styleFrom(
              foregroundColor: PocketClawTheme.cyan,
              disabledForegroundColor: PocketClawTheme.mint,
            ),
            child: Text(
              granted ? '已开启' : '授权',
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
