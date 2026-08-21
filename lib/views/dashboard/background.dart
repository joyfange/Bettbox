import 'dart:io';
import 'dart:ui';

import 'package:bett_box/common/common.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class HomeBackgroundState {
  final String? light;
  final String? dark;
  final double blur;

  const HomeBackgroundState({this.light, this.dark, this.blur = 0.0});

  String? pathOf(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  HomeBackgroundState copyWith(
      {String? light, String? dark, double? blur}) {
    return HomeBackgroundState(
      light: light ?? this.light,
      dark: dark ?? this.dark,
      blur: blur ?? this.blur,
    );
  }
}

final homeBackgroundProvider =
    StateNotifierProvider<HomeBackgroundNotifier, HomeBackgroundState>((ref) {
      return HomeBackgroundNotifier();
    });

class HomeBackgroundNotifier extends StateNotifier<HomeBackgroundState> {
  HomeBackgroundNotifier() : super(const HomeBackgroundState()) {
    _init();
  }

  Future<void> _init() async {
    final prefs = await preferences.sharedPreferencesCompleter.future;
    state = HomeBackgroundState(
      light: prefs?.getString(homeBackgroundLightKey),
      dark: prefs?.getString(homeBackgroundDarkKey),
      blur: (prefs?.getDouble(homeBackgroundBlurKey) ?? 0.0).clamp(0.0, 1.0),
    );
  }

  Future<String?> _pickImage() async {
    if (system.isAndroid || Platform.isIOS) {
      final xFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      return xFile?.path;
    }
    final file = await picker.pickerFile(
      withData: false,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
    );
    return file?.path;
  }

  Future<bool> setBackground(Brightness brightness) async {
    try {
      final sourcePath = await _pickImage();
      if (sourcePath == null) return false;
      final dataDir = await appPath.dataDir.future;
      final dir = Directory(
          '${dataDir.path}${Platform.pathSeparator}backgrounds');
      await dir.create(recursive: true);
      final ext = sourcePath.contains('.')
          ? sourcePath.split('.').last
          : 'png';
      final destPath =
          '${dir.path}${Platform.pathSeparator}home_bg_${brightness.name}.$ext';
      final destFile = File(destPath);
      if (await destFile.exists()) await destFile.delete();
      await File(sourcePath).copy(destPath);
      await _persist(brightness, destPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearBackground(Brightness brightness) async {
    final path = state.pathOf(brightness);
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await _persist(brightness, null);
  }

  Future<void> setBlur(double value) async {
    state = state.copyWith(blur: value);
    final prefs = await preferences.sharedPreferencesCompleter.future;
    prefs?.setDouble(homeBackgroundBlurKey, value);
  }

  Future<void> _persist(Brightness brightness, String? path) async {
    state = brightness == Brightness.dark
        ? HomeBackgroundState(light: state.light, dark: path, blur: state.blur)
        : HomeBackgroundState(light: path, dark: state.dark, blur: state.blur);
    final prefs = await preferences.sharedPreferencesCompleter.future;
    if (path == null) {
      prefs?.remove(brightness == Brightness.dark
          ? homeBackgroundDarkKey
          : homeBackgroundLightKey);
    } else {
      prefs?.setString(brightness == Brightness.dark
          ? homeBackgroundDarkKey
          : homeBackgroundLightKey, path);
    }
  }
}

/// 首页背景层：图片 + 模糊 + 遮罩
class HomeBackground extends ConsumerWidget {
  final Widget child;

  const HomeBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeBackgroundProvider);
    final brightness = Theme.of(context).brightness;
    final rawPath = state.pathOf(brightness);
    final hasImage = rawPath != null && File(rawPath!).existsSync();
    if (!hasImage) return child;
    final blur = state.blur;
    return Stack(
      children: [
        Positioned.fill(
          child: Image.file(
            File(rawPath!),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox(),
          ),
        ),
        if (blur > 0.01)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur * 20, sigmaY: blur * 20),
              child: const SizedBox.expand(),
            ),
          ),
        Positioned.fill(
          child: ColoredBox(
            color: brightness == Brightness.dark
                ? Colors.black.withValues(alpha: 0.30 + blur * 0.20)
                : Colors.white.withValues(alpha: 0.40 + blur * 0.20),
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

/// 背景设置入口：在 CommonScaffold 的 actions 里使用
List<Widget> buildHomeBackgroundActions(BuildContext context) {
  return [
    IconButton(
      tooltip: '背景',
      onPressed: () => _showBackgroundSheet(context),
      icon: const Icon(Icons.wallpaper),
    ),
  ];
}

void _showBackgroundSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _BackgroundSheet(),
  );
}

class _BackgroundSheet extends ConsumerWidget {
  const _BackgroundSheet();

  String _tr(BuildContext context, String zh, String en) {
    final locale = Localizations.maybeLocaleOf(context);
    return locale?.languageCode == 'zh' ? zh : en;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeBackgroundProvider);
    final notifier = ref.read(homeBackgroundProvider.notifier);
    final brightness = Theme.of(context).brightness;
    final currentPath = state.pathOf(brightness);
    final hasImage = currentPath != null && File(currentPath).existsSync();
    final label = brightness == Brightness.dark ? '夜晚' : '白天';

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _tr(context, '设置首页背景', 'Home background'),
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            Flexible(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shrinkWrap: true,
                children: [
                  // 当前模式背景
                  _ModeTile(
                    label: '$label 模式背景',
                    path: currentPath,
                    onTap: () => notifier.setBackground(brightness),
                    onClear: () => notifier.clearBackground(brightness),
                    hasImage: hasImage,
                  ),
                  const SizedBox(height: 12),
                  // 模糊度
                  Text(
                    _tr(context, '背景模糊度', 'Blur'),
                    style: Theme.of(ctx).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.blur_off, size: 18,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                      Expanded(
                        child: Slider(
                          value: state.blur,
                          min: 0.0,
                          max: 1.0,
                          divisions: 20,
                          label: '${(state.blur * 100).round()}%',
                          onChanged: (v) => notifier.setBlur(v),
                        ),
                      ),
                      Icon(Icons.blur_on, size: 18,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _tr(
                      context,
                      '调节模糊度可以降低背景对操作界面的干扰，0% 为原图清晰度，100% 为最强模糊。',
                      'Drag to adjust blur. 0% = sharp, 100% = maximum blur.',
                    ),
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final String label;
  final String? path;
  final VoidCallback onTap;
  final VoidCallback onClear;
  final bool hasImage;

  const _ModeTile({
    required this.label,
    required this.path,
    required this.onTap,
    required this.onClear,
    required this.hasImage,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onClear,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 88,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          image: hasImage
              ? DecorationImage(
                  image: FileImage(File(path!)),
                  fit: BoxFit.cover,
                )
              : null,
          color: hasImage
              ? null
              : Theme.of(context).colorScheme.surfaceContainerHigh,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.black.withValues(alpha: 0.35),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(
                hasImage ? Icons.wallpaper : Icons.add_photo_alternate_outlined,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (hasImage)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                      onPressed: onClear,
                      child: const Text('清除'),
                    ),
                  ],
                )
              else
                const Icon(Icons.add, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
