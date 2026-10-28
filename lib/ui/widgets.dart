import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../services/player_service.dart';
import '../services/playlist_downloader.dart';
import 'theme.dart';

/// Rounded container used for every block. Mobile uses a soft grey fill with
/// no border (like the reference player); desktop styles use hairline borders.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final soft = t.style == DesignStyle.material;
    return Container(
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: soft ? t.background : t.card,
        borderRadius: BorderRadius.circular(soft ? 22 : t.radiusCard),
        border: soft ? null : Border.all(color: t.border),
        boxShadow: soft ? const [] : t.shadows,
      ),
      child: child,
    );
  }
}

/// Small section label ("Destino", "Progresso"...).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Main call-to-action: a solid pill in the accent colour.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.loading = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = onPressed != null;
    final material = t.style == DesignStyle.material;
    final radius = BorderRadius.circular(material ? 16 : t.radiusControl);

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: t.accent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: Container(
            height: material ? 54 : t.controlHeight,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: t.onAccent,
                    ),
                  )
                else if (icon != null)
                  Icon(icon, color: t.onAccent, size: 20),
                if (loading || icon != null) const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.onAccent,
                      fontSize: material ? 16 : 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft secondary pill (the "Shuffle" button of the reference).
class SoftButton extends StatelessWidget {
  const SoftButton({
    super.key,
    required this.onPressed,
    required this.label,
    required this.icon,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: Material(
        color: t.background,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: SizedBox(
            height: 54,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: scheme.onSurface),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Neutral-or-coloured pill, e.g. "12 concluídos".
class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = t.style == DesignStyle.material ? 20.0 : t.radiusControl + 2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rebuilds [builder] with whether [path] is the item currently loaded in the
/// player. Works before the audio handler exists.
class NowPlayingBuilder extends StatelessWidget {
  const NowPlayingBuilder({
    super.key,
    required this.path,
    required this.builder,
  });

  final String? path;
  final Widget Function(bool playing) builder;

  @override
  Widget build(BuildContext context) {
    final handler = PlayerService.instance.handler;
    if (handler == null || path == null) return builder(false);
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      initialData: handler.mediaItem.value,
      builder: (_, snapshot) => builder(snapshot.data?.id == path),
    );
  }
}

/// One video of the playlist: numbered like a track list on mobile
/// ("01  Title / Author · status") and as a flat row with thumbnail on
/// desktop. [dense] selects the desktop row.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.index,
    required this.track,
    this.dense = false,
    this.onTap,
    required this.onSelected,
  });

  final int index;
  final TrackState track;
  final bool dense;
  final VoidCallback? onTap;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final t = context.tokens;

    final (IconData icon, Color color, String label) = switch (track.status) {
      TrackStatus.pending => (
        Icons.schedule_rounded,
        scheme.outline,
        'Em espera',
      ),
      TrackStatus.downloading => (
        Icons.arrow_downward_rounded,
        t.accent,
        'A baixar ${(track.progress * 100).round()}%',
      ),
      TrackStatus.converting => (
        Icons.graphic_eq_rounded,
        t.accent,
        'A converter para MP3',
      ),
      TrackStatus.done => (Icons.check_circle_rounded, t.success, 'Concluído'),
      TrackStatus.failed => (
        Icons.error_rounded,
        scheme.error,
        track.error ?? 'Erro',
      ),
      TrackStatus.skipped => (
        Icons.skip_next_rounded,
        scheme.outline,
        'Ignorado',
      ),
    };
    final active =
        track.status == TrackStatus.downloading ||
        track.status == TrackStatus.converting;
    final number = (index + 1).toString().padLeft(2, '0');
    final author = track.video.author.isEmpty ? 'YouTube' : track.video.author;

    return NowPlayingBuilder(
      path: track.filePath,
      builder: (playing) {
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              track.video.title,
              maxLines: dense ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            SizedBox(height: dense ? 2 : 4),
            Row(
              children: [
                Flexible(
                  child: Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '  •  ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (active) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: dense ? 3 : 4,
                  value: track.status == TrackStatus.converting
                      ? null
                      : track.progress,
                ),
              ),
            ],
          ],
        );

        final numberWidget = SizedBox(
          width: 34,
          child: playing
              ? Icon(Icons.equalizer_rounded, size: 22, color: scheme.onSurface)
              : Text(
                  number,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
        );

        if (dense) {
          return Material(
            color: playing
                ? t.accent.withValues(alpha: 0.08)
                : Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Checkbox(
                        value: track.selected,
                        onChanged: (value) => onSelected(value ?? false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    numberWidget,
                    _thumb(scheme, 64, 36, 6),
                    const SizedBox(width: 14),
                    Expanded(child: details),
                  ],
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color: playing ? t.background : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 0, 10),
                child: Row(
                  children: [
                    numberWidget,
                    const SizedBox(width: 6),
                    Expanded(child: details),
                    Checkbox(
                      value: track.selected,
                      shape: const CircleBorder(),
                      onChanged: (value) => onSelected(value ?? false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _thumb(ColorScheme scheme, double w, double h, double radius) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: w,
        height: h,
        child: Image.network(
          'https://i.ytimg.com/vi/${track.video.id}/mqdefault.jpg',
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            color: scheme.surfaceContainerHighest,
            child: Icon(Icons.music_note_rounded, color: scheme.outline),
          ),
        ),
      ),
    );
  }
}
