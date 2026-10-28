import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';

import '../services/player_service.dart';
import 'full_player.dart';
import 'theme.dart';

/// Now-playing strip.
///
/// [compact] is the mobile mini player: a dark, rounded card with the cover,
/// title and a white play button. Otherwise it is the desktop transport bar
/// with the controls centred, like a desktop music app.
class PlayerBar extends StatefulWidget {
  const PlayerBar({super.key, this.compact = false});

  final bool compact;

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> {
  PlaylistAudioHandler? _handler;

  @override
  void initState() {
    super.initState();
    _handler = PlayerService.instance.handler;
  }

  @override
  Widget build(BuildContext context) {
    final handler = _handler;
    if (handler == null) return const SizedBox.shrink();
    return StreamBuilder<void>(
      stream: handler.activePlayerStream,
      builder: (context, _) => StreamBuilder<MediaItem?>(
        stream: handler.mediaItem,
        initialData: handler.mediaItem.value,
        builder: (context, itemSnapshot) {
          final item = itemSnapshot.data;
          if (item == null) return const SizedBox.shrink();
          return widget.compact
              ? _mini(context, handler, item)
              : _desktop(context, handler, item);
        },
      ),
    );
  }

  // ------------------------------------------------------------------ mobile

  Widget _mini(
    BuildContext context,
    PlaylistAudioHandler handler,
    MediaItem item,
  ) {
    const ink = Color(0xFF111318);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: ink,
        borderRadius: BorderRadius.circular(26),
        elevation: 10,
        shadowColor: Colors.black54,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => FullPlayerSheet.show(context, handler),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                child: Row(
                  children: [
                    _art(context, item, 46, 14),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 320),
                        child: Column(
                          key: ValueKey(item.id),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              item.artist ?? 'YouTube',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Anterior',
                      visualDensity: VisualDensity.compact,
                      color: Colors.white,
                      onPressed: handler.skipToPrevious,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    StreamBuilder<bool>(
                      stream: handler.playingStream,
                      initialData: handler.player.playing,
                      builder: (_, playing) => IconButton.filled(
                        tooltip: playing.data == true ? 'Pausar' : 'Reproduzir',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: ink,
                          fixedSize: const Size(44, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: playing.data == true
                            ? handler.pause
                            : handler.play,
                        icon: Icon(
                          playing.data == true
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Seguinte',
                      visualDensity: VisualDensity.compact,
                      color: Colors.white,
                      onPressed: handler.skipToNext,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
              ),
              StreamBuilder<Duration?>(
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
                        : (current.inMilliseconds / total.inMilliseconds).clamp(
                            0.0,
                            1.0,
                          );
                    const timeStyle = TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      fontFeatures: [FontFeature.tabularFigures()],
                    );
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                      child: Row(
                        children: [
                          Text(_time(current), style: timeStyle),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                minHeight: 3,
                                value: value,
                                color: Colors.white,
                                backgroundColor: Colors.white12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(_time(total), style: timeStyle),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- desktop

  Widget _desktop(
    BuildContext context,
    PlaylistAudioHandler handler,
    MediaItem item,
  ) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: t.card,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.border)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => FullPlayerSheet.show(context, handler),
                    child: _art(context, item, 52, 8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          item.artist ?? 'YouTube',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 5,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 330),
                    child: TransportControls(
                      handler: handler,
                      iconColor: scheme.onSurface,
                      playBackground: t.accent,
                      playForeground: t.onAccent,
                      playSize: 40,
                      iconSize: 28,
                    ),
                  ),
                  _progress(context, handler),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.volume_down_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: StreamBuilder<double>(
                        stream: handler.player.volumeStream,
                        initialData: handler.player.volume,
                        builder: (_, v) => Slider(
                          value: (v.data ?? 1).clamp(0, 1),
                          onChanged: handler.setVolume,
                        ),
                      ),
                    ),
                  ),
                  PopupMenuButton<double>(
                    tooltip: 'Velocidade',
                    initialValue: handler.player.speed,
                    onSelected: handler.setSpeed,
                    itemBuilder: (_) =>
                        const <double>[0.75, 1.0, 1.25, 1.5, 2.0]
                            .map(
                              (v) => PopupMenuItem<double>(
                                value: v,
                                child: Text('${v}x'),
                              ),
                            )
                            .toList(),
                    icon: const Icon(Icons.speed_rounded, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Abrir reprodutor completo',
                    onPressed: () => FullPlayerSheet.show(context, handler),
                    icon: const Icon(Icons.open_in_full_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progress(BuildContext context, PlaylistAudioHandler handler) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
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
              SizedBox(width: 38, child: Text(_time(current), style: style)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                  ),
                  child: Slider(
                    value: value.clamp(0, 1),
                    onChanged: total == Duration.zero
                        ? null
                        : (v) => handler.seek(total * v),
                  ),
                ),
              ),
              SizedBox(
                width: 38,
                child: Text(
                  _time(total),
                  textAlign: TextAlign.right,
                  style: style,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _art(
    BuildContext context,
    MediaItem item,
    double size,
    double radius,
  ) {
    final image = item.artUri;
    final placeholder = Container(
      color: const Color(0xFF2A2D35),
      child: const Icon(Icons.music_note_rounded, color: Colors.white70),
    );
    return Hero(
      tag: 'playlist-mp3-artwork',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: size,
          height: size,
          child: image == null
              ? placeholder
              : Image.file(
                  File(image.toFilePath()),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => placeholder,
                ),
        ),
      ),
    );
  }

  String _time(Duration d) =>
      '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}
