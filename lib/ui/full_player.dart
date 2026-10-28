import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/player_service.dart';
import 'theme.dart';

String _formatTime(Duration d) =>
    '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

final Map<String, Future<Color>> _tintCache = {};

/// Average colour of the artwork, pushed towards a rich, readable tone so the
/// immersive desktop player can fade the cover into it.
Future<Color> artworkTint(String? path, Color fallback) {
  if (path == null) return Future.value(fallback);
  return _tintCache.putIfAbsent(path, () async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 1,
        targetHeight: 1,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null) return fallback;
      final Uint8List px = data.buffer.asUint8List();
      final hsl = HSLColor.fromColor(Color.fromARGB(255, px[0], px[1], px[2]));
      return hsl
          .withSaturation(hsl.saturation.clamp(0.45, 0.85))
          .withLightness(hsl.lightness.clamp(0.30, 0.45))
          .toColor();
    } catch (_) {
      return fallback;
    }
  });
}

/// Full-screen player shown as an animated sheet.
///
/// Narrow screens get the "Now Playing" layout (artwork, waveform, big play
/// button). Wide windows get an immersive layout where the cover fades into
/// a colour wash with the title and controls centred underneath.
class FullPlayerSheet extends StatelessWidget {
  const FullPlayerSheet({super.key, required this.handler});

  final PlaylistAudioHandler handler;

  static Future<void> show(BuildContext context, PlaylistAudioHandler handler) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fechar reprodutor',
      barrierColor: Colors.black.withValues(alpha: 0.58),
      transitionDuration: const Duration(milliseconds: 420),
      pageBuilder: (context, animation, secondaryAnimation) =>
          FullPlayerSheet(handler: handler),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        if (desktop) {
          return Material(
            color: Colors.black,
            child: _ImmersivePlayer(handler: handler),
          );
        }
        return Material(
          color: t.card,
          child: SafeArea(child: _NowPlaying(handler: handler)),
        );
      },
    );
  }
}

// ------------------------------------------------------------------- mobile

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.handler});
  final PlaylistAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = context.tokens;

    return LayoutBuilder(
      builder: (context, constraints) {
        final art = math
            .min(constraints.maxWidth - 64, constraints.maxHeight * 0.42)
            .clamp(160.0, 440.0)
            .toDouble();
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 32,
                ),
                child: StreamBuilder<void>(
                  stream: handler.activePlayerStream,
                  builder: (context, _) => StreamBuilder<MediaItem?>(
                    stream: handler.mediaItem,
                    initialData: handler.mediaItem.value,
                    builder: (context, snapshot) {
                      final item = snapshot.data;
                      if (item == null) return const SizedBox.shrink();
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                tooltip: 'Fechar reprodutor',
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 30,
                                ),
                              ),
                              Text(
                                'A reproduzir',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Fila',
                                onPressed: () => showQueue(context, handler),
                                icon: const Icon(Icons.queue_music_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: art,
                            height: art,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(34),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.28),
                                  blurRadius: 36,
                                  offset: const Offset(0, 18),
                                ),
                              ],
                            ),
                            child: _NowPlayingArtwork(item: item, radius: 34),
                          ),
                          const SizedBox(height: 28),
                          Row(
                            children: [
                              PopupMenuButton<double>(
                                tooltip: 'Velocidade',
                                initialValue: handler.player.speed,
                                onSelected: handler.setSpeed,
                                itemBuilder: (_) =>
                                    const [0.75, 1.0, 1.25, 1.5, 2.0]
                                        .map(
                                          (v) => PopupMenuItem<double>(
                                            value: v,
                                            child: Text('${v}x'),
                                          ),
                                        )
                                        .toList(),
                                icon: Icon(
                                  Icons.speed_rounded,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 360),
                                  child: Text(
                                    item.title,
                                    key: ValueKey(item.id),
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.4,
                                        ),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Volume',
                                onPressed: () => _showVolume(context),
                                icon: Icon(
                                  Icons.more_horiz_rounded,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.artist ?? 'YouTube',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 26),
                          _WaveformProgress(handler: handler, seed: item.id),
                          const SizedBox(height: 22),
                          TransportControls(
                            handler: handler,
                            iconColor: scheme.onSurface,
                            playBackground: t.accent,
                            playForeground: t.onAccent,
                            playSize: 74,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showVolume(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Row(
          children: [
            const Icon(Icons.volume_down_rounded),
            Expanded(
              child: StreamBuilder<double>(
                stream: handler.player.volumeStream,
                initialData: handler.player.volume,
                builder: (_, volume) => Slider(
                  value: (volume.data ?? 1).clamp(0, 1),
                  onChanged: handler.setVolume,
                ),
              ),
            ),
            const Icon(Icons.volume_up_rounded),
          ],
        ),
      ),
    );
  }
}

/// Opens the playback queue as a bottom sheet.
void showQueue(BuildContext context, PlaylistAudioHandler handler) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: BoxConstraints(
      maxWidth: 560,
      maxHeight: MediaQuery.sizeOf(context).height * 0.7,
    ),
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: _Queue(handler: handler),
    ),
  );
}

class _NowPlayingArtwork extends StatelessWidget {
  const _NowPlayingArtwork({required this.item, this.radius = 22});
  final MediaItem item;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = item.artUri?.toFilePath();
    return Hero(
      tag: 'playlist-mp3-artwork',
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: ClipRRect(
          key: ValueKey(item.id),
          borderRadius: BorderRadius.circular(radius),
          child: AspectRatio(
            aspectRatio: 1,
            child: path == null
                ? _placeholder(context)
                : Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _placeholder(context),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => Container(
    color: const Color(0xFF14141A),
    child: const Icon(Icons.music_note_rounded, size: 90, color: Colors.white),
  );
}

// ----------------------------------------------------------------- waveform

class _WaveformProgress extends StatelessWidget {
  const _WaveformProgress({required this.handler, required this.seed});
  final PlaylistAudioHandler handler;
  final String seed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return StreamBuilder<Duration?>(
      stream: handler.durationStream,
      initialData: handler.player.duration,
      builder: (_, duration) => StreamBuilder<Duration>(
        stream: handler.positionStream,
        initialData: handler.player.position,
        builder: (_, position) {
          final total = duration.data ?? Duration.zero;
          final current = position.data ?? Duration.zero;
          final value = total.inMilliseconds == 0
              ? 0.0
              : (current.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
          final labelStyle = theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontFeatures: const [ui.FontFeature.tabularFigures()],
          );
          return Column(
            children: [
              Waveform(
                seed: seed,
                progress: value,
                playedColor: scheme.onSurface,
                restColor: scheme.onSurface.withValues(alpha: 0.18),
                onSeek: total == Duration.zero
                    ? null
                    : (fraction) => handler.seek(total * fraction),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatTime(current), style: labelStyle),
                  Text(_formatTime(total), style: labelStyle),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Bar waveform used as a seek bar. The shape is generated from [seed] so the
/// same track always looks the same.
class Waveform extends StatelessWidget {
  const Waveform({
    super.key,
    required this.seed,
    required this.progress,
    required this.playedColor,
    required this.restColor,
    this.onSeek,
    this.height = 56,
  });

  final String seed;
  final double progress;
  final Color playedColor;
  final Color restColor;
  final ValueChanged<double>? onSeek;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void seek(double dx) => onSeek?.call((dx / width).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seek(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seek(d.localPosition.dx),
          child: CustomPaint(
            size: Size(width, height),
            painter: _WavePainter(
              seed: seed.hashCode,
              progress: progress,
              played: playedColor,
              rest: restColor,
            ),
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.seed,
    required this.progress,
    required this.played,
    required this.rest,
  });

  final int seed;
  final double progress;
  final Color played;
  final Color rest;

  static const _bar = 2.6;
  static const _gap = 2.4;

  @override
  void paint(Canvas canvas, Size size) {
    final count = math.max(8, (size.width / (_bar + _gap)).floor());
    final random = math.Random(seed);
    final phase = (seed % 11) / 11 * math.pi;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = _bar;
    final mid = size.height / 2;
    for (var i = 0; i < count; i++) {
      final envelope =
          0.35 + 0.65 * math.sin(i / count * math.pi * 3 + phase).abs();
      final amp = (0.18 + 0.82 * random.nextDouble()) * envelope;
      final half = math.max(2.0, amp * mid);
      final x = i * (_bar + _gap) + _bar / 2;
      paint.color = i / count <= progress ? played : rest;
      canvas.drawLine(Offset(x, mid - half), Offset(x, mid + half), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress ||
      old.seed != seed ||
      old.played != played ||
      old.rest != rest;
}

// ---------------------------------------------------------------- transport

/// Shuffle · previous · play/pause · next · repeat.
class TransportControls extends StatelessWidget {
  const TransportControls({
    super.key,
    required this.handler,
    required this.iconColor,
    required this.playBackground,
    required this.playForeground,
    this.playSize = 68,
    this.iconSize = 34,
  });

  final PlaylistAudioHandler? handler;
  final Color iconColor;
  final Color playBackground;
  final Color playForeground;
  final double playSize;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final h = handler;
    final dim = iconColor.withValues(alpha: 0.45);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        StreamBuilder<bool>(
          stream: h?.shuffleModeStream,
          initialData: h?.player.shuffleModeEnabled ?? false,
          builder: (_, shuffle) => IconButton(
            tooltip: 'Aleatório',
            color: shuffle.data == true ? iconColor : dim,
            icon: const Icon(Icons.shuffle_rounded),
            onPressed: h == null
                ? null
                : () => h.setShuffle(shuffle.data != true),
          ),
        ),
        IconButton(
          tooltip: 'Anterior',
          iconSize: iconSize,
          color: iconColor,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: h?.skipToPrevious,
        ),
        StreamBuilder<bool>(
          stream: h?.playingStream,
          initialData: h?.player.playing ?? false,
          builder: (_, playing) {
            final isPlaying = playing.data == true;
            return IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: playBackground,
                foregroundColor: playForeground,
                fixedSize: Size(playSize, playSize),
                shape: const CircleBorder(),
              ),
              tooltip: isPlaying ? 'Pausar' : 'Reproduzir',
              iconSize: playSize * 0.5,
              onPressed: h == null ? null : (isPlaying ? h.pause : h.play),
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
            );
          },
        ),
        IconButton(
          tooltip: 'Seguinte',
          iconSize: iconSize,
          color: iconColor,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: h?.skipToNext,
        ),
        StreamBuilder<LoopMode>(
          stream: h?.loopModeStream,
          initialData: h?.player.loopMode ?? LoopMode.off,
          builder: (_, loop) {
            final mode = loop.data ?? LoopMode.off;
            return IconButton(
              tooltip: 'Repetição',
              color: mode == LoopMode.off ? dim : iconColor,
              icon: Icon(
                mode == LoopMode.one
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
              ),
              onPressed: h == null
                  ? null
                  : () => h.setLoopMode(switch (mode) {
                      LoopMode.off => LoopMode.all,
                      LoopMode.all => LoopMode.one,
                      LoopMode.one => LoopMode.off,
                    }),
            );
          },
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ desktop

class _ImmersivePlayer extends StatelessWidget {
  const _ImmersivePlayer({required this.handler});
  final PlaylistAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    final fallback = context.tokens.accent;
    return StreamBuilder<void>(
      stream: handler.activePlayerStream,
      builder: (context, _) => StreamBuilder<MediaItem?>(
        stream: handler.mediaItem,
        initialData: handler.mediaItem.value,
        builder: (context, snapshot) {
          final item = snapshot.data;
          if (item == null) return const SizedBox.shrink();
          final path = item.artUri?.toFilePath();
          return FutureBuilder<Color>(
            future: artworkTint(path, fallback),
            initialData: _tintCache[path] == null ? fallback : null,
            builder: (context, tint) => TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: tint.data ?? fallback),
              duration: const Duration(milliseconds: 600),
              builder: (context, color, _) =>
                  _immersive(context, item, path, color ?? fallback),
            ),
          );
        },
      ),
    );
  }

  Widget _immersive(
    BuildContext context,
    MediaItem item,
    String? path,
    Color tint,
  ) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final queue = handler.queue.value;
    final index = queue.indexWhere((e) => e.id == item.id);
    final titleSize = (width * 0.045).clamp(34.0, 64.0).toDouble();
    final deep = Color.lerp(tint, Colors.black, 0.35)!;

    final image = path == null
        ? null
        : Image.file(
            File(path),
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight;
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [tint, deep],
                ),
              ),
            ),
            if (image != null) ...[
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: Opacity(opacity: 0.55, child: image),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: h * 0.8,
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black, Colors.black, Colors.transparent],
                    stops: [0, 0.45, 1],
                  ).createShader(rect),
                  child: SizedBox.expand(child: image),
                ),
              ),
            ],
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    tint.withValues(alpha: 0.0),
                    tint.withValues(alpha: 0.78),
                    deep.withValues(alpha: 0.96),
                  ],
                  stops: const [0, 0.38, 0.74, 1],
                ),
              ),
            ),
            SafeArea(
              child: Theme(
                data: theme.copyWith(
                  iconTheme: const IconThemeData(color: Colors.white),
                  sliderTheme: theme.sliderTheme.copyWith(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white24,
                    trackHeight: 3,
                  ),
                ),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: Colors.white),
                  child: Column(
                    children: [
                      _immersiveTopBar(context, index, queue.length),
                      const Spacer(),
                      _artistPill(item),
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 420),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.12),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: Text(
                            item.title,
                            key: ValueKey(item.id),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: titleSize,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.4,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _ImmersiveProgress(handler: handler),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: 'Fila',
                                onPressed: () => showQueue(context, handler),
                                icon: const Icon(Icons.queue_music_rounded),
                              ),
                              Expanded(
                                child: TransportControls(
                                  handler: handler,
                                  iconColor: Colors.white,
                                  playBackground: Colors.white,
                                  playForeground: Colors.black,
                                  playSize: 64,
                                ),
                              ),
                              const Icon(Icons.volume_down_rounded, size: 20),
                              SizedBox(
                                width: 110,
                                child: StreamBuilder<double>(
                                  stream: handler.player.volumeStream,
                                  initialData: handler.player.volume,
                                  builder: (_, volume) => Slider(
                                    value: (volume.data ?? 1).clamp(0, 1),
                                    onChanged: handler.setVolume,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Toque em "Fila" para escolher outra música.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _immersiveTopBar(BuildContext context, int index, int total) {
    const style = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(Platform.isMacOS ? 84 : 28, 16, 28, 0),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Row(
                children: [
                  Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                  SizedBox(width: 2),
                  Text('FECHAR', style: style),
                ],
              ),
            ),
          ),
          const Spacer(),
          const Text(
            'Playlist MP3',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const Spacer(),
          Text(index < 0 ? '' : '${index + 1} / $total', style: style),
        ],
      ),
    );
  }

  Widget _artistPill(MediaItem item) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          color: Colors.white.withValues(alpha: 0.2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sensors_rounded, size: 18),
              const SizedBox(width: 8),
              Text(
                item.artist ?? 'YouTube',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImmersiveProgress extends StatelessWidget {
  const _ImmersiveProgress({required this.handler});
  final PlaylistAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white70, fontSize: 12);
    return StreamBuilder<Duration?>(
      stream: handler.durationStream,
      initialData: handler.player.duration,
      builder: (_, duration) => StreamBuilder<Duration>(
        stream: handler.positionStream,
        initialData: handler.player.position,
        builder: (_, position) {
          final total = duration.data ?? Duration.zero;
          final current = position.data ?? Duration.zero;
          final value = total.inMilliseconds == 0
              ? 0.0
              : current.inMilliseconds / total.inMilliseconds;
          return Row(
            children: [
              Text(_formatTime(current), style: style),
              Expanded(
                child: Slider(
                  value: value.clamp(0, 1),
                  onChanged: total == Duration.zero
                      ? null
                      : (v) => handler.seek(total * v),
                ),
              ),
              Text(_formatTime(total), style: style),
            ],
          );
        },
      ),
    );
  }
}

class _Queue extends StatelessWidget {
  const _Queue({required this.handler});
  final PlaylistAudioHandler handler;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MediaItem>>(
      stream: handler.queue,
      initialData: handler.queue.value,
      builder: (context, queue) {
        final items = queue.data ?? const <MediaItem>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return StreamBuilder<MediaItem?>(
          stream: handler.mediaItem,
          initialData: handler.mediaItem.value,
          builder: (context, current) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fila',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                ...items.asMap().entries.map((entry) {
                  final playing = entry.value.id == current.data?.id;
                  return ListTile(
                    dense: true,
                    selected: playing,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: playing
                        ? const Icon(Icons.equalizer_rounded)
                        : Text((entry.key + 1).toString().padLeft(2, '0')),
                    title: Text(
                      entry.value.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(entry.value.artist ?? 'YouTube'),
                    onTap: () => handler.playTrack(entry.key),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }
}
