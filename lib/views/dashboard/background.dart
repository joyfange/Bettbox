import 'dart:io';

import 'package:bett_box/common/common.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class HomeBackgroundState {
  final String? light;
  final String? dark;
  final double blur; // 0.0 = no blur, 1.0 = max blur

  const HomeBackgroundState({
    this.light,
    this.dark,
    this.blur = 0.0,
  });

  String? pathOf(Brightness brightness) {
    return brightness == Brightness.dark ? dark : light;
  }

  HomeBackgroundState copyWith({
    String? light,
    String? dark,
    double? blur,
  }) {
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

  Future<bool> update(Brightness brightness) async {
    try {
      final sourcePath = await _pickImage();
      if (sourcePath == null) return false;
      final dataDir = await appPath.dataDir.future;
      final dir = Directory('${dataDir.path}${Platform.pathSeparator}backgrounds');
      await dir.create(recursive: true);
      final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'png';
      final destPath =
          '${dir.path}${Platform.pathSeparator}home_bg_${brightness.name}.${ext}';
      final destFile = File(destPath);
      if (await destFile.exists()) {
        await destFile.delete();
      }
      await File(sourcePath).copy(destPath);
      await _persist(brightness, destPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear(Brightness brightness) async {
    final path = state.pathOf(brightness);
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    await _persist(brightness, null);
  }

  Future<void> updateBlur(double value) async {
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
      prefs?.remove(
        brightness == Brightness.dark
            ? homeBackgroundDarkKey
            : homeBackgroundLightKey,
      );
    } else {
      prefs?.setString(
        brightness == Brightness.dark
            ? homeBackgroundDarkKey
            : homeBackgroundLightKey,
        path,
      );
    }
  }
}

/// Renders a home background image (light/dark aware) behind [child],
/// with a scrim overlay and optional blur to keep content readable.
class HomeBackground extends ConsumerWidget {
  final Widget child;

  const HomeBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeBackgroundProvider);
    final brightness = Theme.of(context).brightness;
    final rawPath = state.pathOf(brightness);
    final hasImage = rawPath != null && File(rawPath!).existsSync();
    if (!hasImage) {
      return child;
    }
    final imagePath = rawPath!;
    final blur = state.blur;
    return Stack(
      children: [
        Positioned.fill(
          child: Image.file(
            File(imagePath),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox(),
          ),
        ),
        if (blur > 0.01)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: blur * 20.0,
                sigmaY: blur * 20.0,
              ),
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

String _tr(BuildContext context, String zh, String en) {
  final locale = Localizations.maybeLocaleOf(context);
  return locale?.languageCode == 'zh' ? zh : en;
}

void showHomeBackgroundSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: _HomeBackgroundSheetBody(),
        ),
      );
    },
  );
}

class _HomeBackgroundSheetBody extends ConsumerWidget {
  const _HomeBackgroundSheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeBackgroundProvider);
    final notifier = ref.read(homeBackgroundProvider.notifier);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BackgroundTile(
            title: _tr(context, '白天模式背景', 'Light mode background'),
            path: state.light,
            brightness: Brightness.light,
          ),
          const SizedBox(height: 12),
          _BackgroundTile(
            title: _tr(context, '夜晚模式背景', 'Dark mode background'),
            path: state.dark,
            brightness: Brightness.dark,
          ),
          const SizedBox(height: 20),
          Text(
            _tr(context, '背景模糊度', 'Background blur'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.blur_off,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              Expanded(
                child: Slider(
                  value: state.blur,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: '${(state.blur * 100).round()}%',
                  onChanged: (v) => notifier.updateBlur(v),
                ),
              ),
              Icon(
                Icons.blur_on,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _tr(
              context,
              '点击选择图片，长按清除背景；滑动调节模糊度，切换昼夜模式时自动更换对应图片。',
              'Tap to pick an image, long press to clear; drag to adjust blur; auto-switches with light/dark mode.',
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _BackgroundTile extends ConsumerWidget {
  final String title;
  final String? path;
  final Brightness brightness;

  const _BackgroundTile({
    required this.title,
    required this.path,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(homeBackgroundProvider.notifier);
    final hasImage = path != null && File(path!).existsSync();
    final tilePath = path!;
    return GestureDetector(
      onLongPress: () {
        HapticFeedback.lightImpact();
        notifier.clear(brightness);
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => notifier.update(brightness),
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            image: hasImage
                ? DecorationImage(
                    image: FileImage(File(tilePath)),
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
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (hasImage)
                  const Icon(Icons.check_circle, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
