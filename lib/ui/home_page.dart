import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:window_manager/window_manager.dart';

import '../services/mp3_saver.dart';
import '../services/audio_library.dart';
import '../services/notification_service.dart';
import '../services/player_service.dart';
import 'full_player.dart';
import 'player_bar.dart';
import '../services/playlist_downloader.dart';
import '../services/playlist_fetcher.dart' show PlaylistFetcher;
import 'theme.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  final _downloader = PlaylistDownloader();
  final _library = AudioLibrary();
  final _scroll = ScrollController();

  String? _playlistTitle;
  List<TrackState> _tracks = [];
  bool _loading = false;
  bool _downloading = false;
  String? _error;
  String? _savedTo;

  /// iOS / desktop only: where the MP3 files go.
  String? _saveDir;
  String? _defaultDir;

  @override
  void initState() {
    super.initState();
    _loadFolder();
    NotificationService.instance.init(onStop: _stop, onOpen: _openNotification);
  }

  bool _stopRequested = false;
  int _playerTrackCount = 0;

  void _stop() {
    _stopRequested = true;
    _downloader.cancel();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _downloader.cancel();
    _downloader.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ folder

  Future<void> _loadFolder() async {
    if (!Mp3Saver.canChooseFolder) return;
    final saver = _downloader.saver;
    final saved = await saver.savedDirectory();
    final fallback = await saver.defaultDirectory();
    if (!mounted) return;
    setState(() {
      _defaultDir = fallback;
      _saveDir = saved ?? fallback;
    });
  }

  Future<String?> _chooseFolder() async {
    final picked = await _downloader.saver.pickDirectory(initial: _saveDir);
    if (picked != null && mounted) setState(() => _saveDir = picked);
    return picked;
  }

  Future<void> _choosePlaybackFolder() async {
    final picked = await _downloader.saver.pickDirectory(initial: _saveDir);
    if (picked == null) return;
    final tracks = await _library.scan(picked);
    if (tracks.isEmpty) {
      if (mounted) _snack('Não encontrei ficheiros MP3 nessa pasta.');
      return;
    }
    await PlayerService.instance.loadTracks(tracks);
    if (mounted) {
      setState(() {
        _saveDir = picked;
        _savedTo = picked;
      });
      _snack('${tracks.length} músicas adicionadas ao reprodutor.');
    }
  }

  Future<void> _openNotification(String? payload) async {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload);
      final folder = data is Map ? data['folder'] as String? : null;
      if (folder == null || folder.isEmpty) return;
      // Reopen the security-scoped bookmark before scanning a macOS/iOS folder.
      if (Platform.isMacOS) await _downloader.saver.savedDirectory();
      final tracks = await _library.scan(folder);
      if (tracks.isEmpty) return;
      await PlayerService.instance.loadTracks(tracks);
      if (mounted) {
        setState(() => _savedTo = folder);
        _snack('A reproduzir ${tracks.length} músicas da pasta baixada.');
      }
    } catch (_) {
      // Notification payloads can outlive a folder permission.
    }
  }

  String _describeFolder(String? path) {
    if (path == null) return '…';
    if (path == _defaultDir && Platform.isIOS) {
      return 'Ficheiros › Neste iPhone › Playlist MP3';
    }
    final parts = path
        .split(Platform.pathSeparator)
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length <= 2) return path;
    return '…/${parts[parts.length - 2]}/${parts.last}';
  }

  // ---------------------------------------------------------------- playlist

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _controller.text = data!.text!.trim();
      _onLinkChanged(_controller.text);
    }
  }

  String? _lastAutoLoaded;

  /// Loads the playlist on its own as soon as the field holds a valid link.
  void _onLinkChanged(String value) {
    if (_loading || _downloading) return;
    final String id;
    try {
      id = PlaylistFetcher.parseId(value);
    } on InvalidPlaylistException {
      return;
    }
    if (id == _lastAutoLoaded) return;
    _lastAutoLoaded = id;
    _loadPlaylist();
  }

  Future<void> _loadPlaylist() async {
    FocusScope.of(context).unfocus();
    try {
      _lastAutoLoaded = PlaylistFetcher.parseId(_controller.text);
    } on InvalidPlaylistException {
      _lastAutoLoaded = null;
    }
    setState(() {
      _loading = true;
      _error = null;
      _savedTo = null;
      _tracks = [];
      _playlistTitle = null;
    });
    try {
      final result = await _downloader.load(_controller.text);
      if (!mounted) return;
      setState(() {
        _playlistTitle = result.title;
        _tracks = result.videos.map(TrackState.new).toList();
      });
    } on InvalidPlaylistException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } on PlaylistUnavailableException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Não foi possível carregar a playlist. Verifique a ligação.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startDownload() async {
    if (_selectedCount() == 0) {
      _snack('Seleciona pelo menos uma música.');
      return;
    }
    String? baseDir;
    if (Mp3Saver.canChooseFolder) {
      baseDir = _saveDir ?? await _downloader.saver.defaultDirectory();
      try {
        await _downloader.saver.verifyWritable(baseDir);
      } on FolderAccessException {
        // The remembered folder is no longer accessible: ask again.
        if (!mounted) return;
        _snack('Sem acesso à pasta. Escolha onde guardar as músicas.');
        baseDir = await _chooseFolder();
        if (baseDir == null) return;
        try {
          await _downloader.saver.verifyWritable(baseDir);
        } on FolderAccessException catch (e) {
          if (mounted) setState(() => _error = e.toString());
          return;
        }
      }
    }

    final notifications = NotificationService.instance;
    final playlist = _playlistTitle ?? 'Playlist';
    _stopRequested = false;
    setState(() {
      _downloading = true;
      _error = null;
    });
    await notifications.start(playlist: playlist, total: _selectedCount());
    try {
      final where = await _downloader.downloadAll(
        playlistTitle: playlist,
        tracks: _tracks,
        baseDir: baseDir,
        onChanged: () {
          if (mounted) setState(() {});
          final ready = _tracks.where((t) => t.filePath != null).length;
          if (ready != _playerTrackCount) {
            _playerTrackCount = ready;
            PlayerService.instance.loadTracks(_tracks);
          }
          final current = _tracks.cast<TrackState?>().firstWhere(
            (t) =>
                t!.status == TrackStatus.downloading ||
                t.status == TrackStatus.converting,
            orElse: () => null,
          );
          notifications.update(
            playlist: playlist,
            done: _selectedDoneCount(),
            total: _selectedCount(),
            current: current?.video.title,
            currentFraction: current == null
                ? 0
                : current.status == TrackStatus.converting
                ? 1
                : current.progress,
          );
        },
      );
      if (!mounted) return;
      if (where.isNotEmpty) setState(() => _savedTo = where);
      final failed = _count(TrackStatus.failed);
      if (_count(TrackStatus.done) == _tracks.length) {
        _snack('Playlist concluída!');
      } else if (failed > 0) {
        _snack(
          '$failed vídeo(s) falharam. Toque em Continuar para tentar de novo.',
        );
      }
    } on FolderAccessException catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      await notifications.finish(
        playlist: playlist,
        done: _selectedDoneCount(),
        failed: _count(TrackStatus.failed),
        total: _selectedCount(),
        stopped: _stopRequested,
        location: _savedTo,
        folderPath: _savedTo,
      );
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _playTrack(TrackState track) async {
    if (track.filePath == null) {
      _snack('Esta música ainda não foi baixada.');
      return;
    }
    await PlayerService.instance.loadTracks(_tracks);
    final playable = _tracks.where((t) => t.filePath != null).toList();
    final index = playable.indexOf(track);
    if (index >= 0) await PlayerService.instance.handler?.playTrack(index);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  int _count(TrackStatus s) => _tracks.where((t) => t.status == s).length;

  int _selectedDoneCount() =>
      _tracks.where((t) => t.selected && t.status == TrackStatus.done).length;

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    // Use the actual available width as well as the platform style. This is
    // important for the web target, where a Material-themed app can still be
    // opened on a desktop-sized window.
    if (context.isDesktopLayout) return _buildDesktop(context);
    return _buildMobile(context);
  }

  PlaylistAudioHandler? get _handler => PlayerService.instance.handler;

  /// Plays the downloaded tracks, from the start or from a random one.
  Future<void> _playAll({bool shuffle = false}) async {
    final playable = _tracks.where((t) => t.filePath != null).length;
    if (playable == 0) {
      _snack('Baixe pelo menos uma música para reproduzir.');
      return;
    }
    await PlayerService.instance.loadTracks(_tracks);
    final handler = _handler;
    if (handler == null) return;
    await handler.setShuffle(shuffle);
    await handler.playTrack(shuffle ? math.Random().nextInt(playable) : 0);
  }

  void _openPlayer() {
    final handler = _handler;
    if (handler == null || handler.mediaItem.value == null) {
      _snack('Nada a reproduzir. Toque numa música baixada.');
      return;
    }
    FullPlayerSheet.show(context, handler);
  }

  // ----------------------------------------------------------------- desktop

  /// macOS hides the native title bar, so the panes reserve room for the
  /// traffic-light buttons and act as a drag area.
  bool get _customTitleBar => Platform.isMacOS;

  Widget _dragArea({required Widget child}) =>
      _customTitleBar ? DragToMoveArea(child: child) : child;

  Widget _buildDesktop(BuildContext context) {
    final t = context.tokens;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final busy = _loading || _downloading;
    final topInset = _customTitleBar ? 38.0 : 0.0;
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = (width * 0.036).clamp(30.0, 52.0).toDouble();
    final warm = dark ? const Color(0xFF7A4A12) : const Color(0xFFFFD36A);
    final author = _tracks.isEmpty || _tracks.first.video.author.isEmpty
        ? 'Playlist MP3'
        : _tracks.first.video.author;

    return Scaffold(
      backgroundColor: t.background,
      body: Stack(
        children: [
          // Warm colour wash, like the immersive reference.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    warm,
                    Color.alphaBlend(
                      warm.withValues(alpha: 0.35),
                      t.background,
                    ),
                    t.background,
                  ],
                  stops: const [0, 0.4, 0.85],
                ),
              ),
            ),
          ),
          Row(
            children: [
              // ----------------------------------------------------- sidebar
              ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    width: 320,
                    decoration: BoxDecoration(
                      color: t.sidebar.withValues(alpha: dark ? 0.78 : 0.62),
                      border: Border(right: BorderSide(color: t.border)),
                    ),
                    child: Column(
                      children: [
                        _dragArea(
                          child: SizedBox(
                            height: topInset,
                            width: double.infinity,
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
                            children: [
                              _header(context, compact: true),
                              const SizedBox(height: 26),
                              const SectionLabel('NOVA PLAYLIST'),
                              const SizedBox(height: 8),
                              _inputCard(context, busy),
                              const SizedBox(height: 22),
                              const SectionLabel('DESTINO'),
                              const SizedBox(height: 8),
                              _destinationCard(context),
                              if (_error != null) ...[
                                const SizedBox(height: 16),
                                _errorBanner(context),
                              ],
                              if (_tracks.isNotEmpty) ...[
                                const SizedBox(height: 22),
                                const SectionLabel('PROGRESSO'),
                                const SizedBox(height: 8),
                                _summaryCard(context, busy),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // ----------------------------------------------------- content
              Expanded(
                child: Column(
                  children: [
                    _dragArea(
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.fromLTRB(
                          40,
                          28 + topInset * 0.5,
                          40,
                          8,
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.onSurface.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.sensors_rounded,
                                    size: 17,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      author,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _playlistTitle ?? 'A sua biblioteca',
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: titleSize,
                                height: 1.05,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.6,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _tracks.isEmpty
                                  ? 'Cole um link para começar'
                                  : '${_tracks.length} vídeos · ${_count(TrackStatus.done)} concluídos',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            if (_tracks.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 400,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: PrimaryButton(
                                        onPressed: _playAll,
                                        icon: Icons.play_arrow_rounded,
                                        label: 'Reproduzir',
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _GlassButton(
                                        onPressed: () =>
                                            _playAll(shuffle: true),
                                        icon: Icons.shuffle_rounded,
                                        label: 'Aleatório',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _tracks.isEmpty
                          ? Center(
                              child: SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 440,
                                  ),
                                  child: _loading
                                      ? const CircularProgressIndicator()
                                      : _emptyState(context),
                                ),
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(
                                40,
                                14,
                                40,
                                24,
                              ),
                              child: AppCard(
                                padding: EdgeInsets.zero,
                                clip: true,
                                child: ListView.separated(
                                  itemCount: _tracks.length,
                                  separatorBuilder: (_, _) =>
                                      Divider(height: 1, color: t.border),
                                  itemBuilder: (_, i) => TrackTile(
                                    index: i,
                                    track: _tracks[i],
                                    dense: true,
                                    onTap: () => _playTrack(_tracks[i]),
                                    onSelected: (value) =>
                                        _setSelected(i, value),
                                  ),
                                ),
                              ),
                            ),
                    ),
                    const PlayerBar(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ mobile

  Widget _buildMobile(BuildContext context) {
    final t = context.tokens;
    final busy = _loading || _downloading;

    return Scaffold(
      backgroundColor: t.card,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: CustomScrollView(
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      sliver: SliverList.list(
                        children: [
                          _header(context),
                          const SizedBox(height: 24),
                          if (_tracks.isNotEmpty) ...[
                            _albumHeader(context),
                            const SizedBox(height: 20),
                          ],
                          _inputCard(context, busy),
                          const SizedBox(height: 12),
                          _destinationCard(context),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            _errorBanner(context),
                          ],
                          const SizedBox(height: 16),
                          if (_tracks.isNotEmpty) _summaryCard(context, busy),
                        ],
                      ),
                    ),
                    if (_tracks.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                        sliver: SliverList.builder(
                          itemCount: _tracks.length,
                          itemBuilder: (_, i) => TrackTile(
                            index: i,
                            track: _tracks[i],
                            onTap: () => _playTrack(_tracks[i]),
                            onSelected: (value) => _setSelected(i, value),
                          ),
                        ),
                      )
                    else if (!_loading)
                      SliverToBoxAdapter(child: _emptyState(context)),
                    const SliverToBoxAdapter(child: SizedBox(height: 190)),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [const PlayerBar(compact: true), _bottomNav(context)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomNav(BuildContext context) {
    final t = context.tokens;
    final canChoose = Mp3Saver.canChooseFolder;
    Widget item(
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool selected = false,
    }) {
      final color = selected
          ? Theme.of(context).colorScheme.onSurface
          : Theme.of(context).colorScheme.onSurfaceVariant;
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 26, color: color),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: color,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: t.card,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          item(Icons.home_rounded, 'Início', () {
            if (_scroll.hasClients) {
              _scroll.animateTo(
                0,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
              );
            }
          }, selected: true),
          item(Icons.library_music_outlined, 'Biblioteca', () {
            if (_loading || _downloading) return;
            canChoose ? _choosePlaybackFolder() : _playAll();
          }),
          item(Icons.graphic_eq_rounded, 'A reproduzir', _openPlayer),
        ],
      ),
    );
  }

  Widget _albumHeader(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final first = _tracks.first;
    final author = first.video.author.isEmpty ? 'YouTube' : first.video.author;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                color: const Color(0xFF111318),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.network(
                'https://i.ytimg.com/vi/${first.video.id}/hqdefault.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.library_music_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Playlist • ${_tracks.length} faixas',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _playlistTitle ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      decoration: TextDecoration.underline,
                      decorationStyle: TextDecorationStyle.dotted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                onPressed: _playAll,
                icon: Icons.play_circle_outline_rounded,
                label: 'Reproduzir',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SoftButton(
                onPressed: () => _playAll(shuffle: true),
                icon: Icons.shuffle_rounded,
                label: 'Aleatório',
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _setSelected(int index, bool selected) {
    if (_downloading || index >= _tracks.length) return;
    setState(() => _tracks[index].selected = selected);
  }

  void _selectAll(bool selected) {
    if (_downloading) return;
    setState(() {
      for (final track in _tracks) {
        if (track.status != TrackStatus.done) track.selected = selected;
      }
    });
  }

  int _selectedCount() => _tracks.where((track) => track.selected).length;

  Widget _header(BuildContext context, {bool compact = false}) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: compact ? 48 : 64,
          height: compact ? 48 : 64,
          padding: EdgeInsets.all(compact ? 3 : 4),
          decoration: BoxDecoration(
            color: const Color(0xFF14141A),
            borderRadius: BorderRadius.circular(compact ? 12 : 18),
            boxShadow: compact
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: AppTheme.red.withValues(alpha: 0.30),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Image.asset('assets/icon/logo.png'),
        ),
        SizedBox(width: compact ? 12 : 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Playlist MP3',
                style:
                    (compact
                            ? theme.textTheme.titleLarge
                            : theme.textTheme.headlineSmall)
                        ?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
              ),
              const SizedBox(height: 2),
              Text(
                compact
                    ? 'Playlists do YouTube em MP3'
                    : 'Baixe playlists do YouTube em MP3',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _inputCard(BuildContext context, bool busy) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            enabled: !busy,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            onChanged: _onLinkChanged,
            onSubmitted: (_) => _loadPlaylist(),
            decoration: InputDecoration(
              hintText: 'Cole o link da playlist',
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: IconButton(
                tooltip: 'Colar',
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: busy ? null : _paste,
              ),
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            onPressed: busy ? null : _loadPlaylist,
            loading: _loading,
            icon: Icons.search_rounded,
            label: _loading ? 'A carregar...' : 'Carregar playlist',
          ),
        ],
      ),
    );
  }

  Widget _destinationCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canChoose = Mp3Saver.canChooseFolder;
    final busy = _loading || _downloading;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.folder_rounded, color: scheme.onSurface),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Guardar em',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      canChoose
                          ? _describeFolder(_saveDir)
                          : 'Música › ${_playlistTitle ?? 'nome da playlist'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (canChoose) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: busy ? null : _chooseFolder,
                    icon: const Icon(Icons.drive_file_move_rounded, size: 18),
                    label: const Text('Alterar'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: busy ? null : _choosePlaybackFolder,
                    icon: const Icon(Icons.headphones_rounded, size: 18),
                    label: const Text('Ouvir'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(color: scheme.onErrorContainer, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(BuildContext context, bool busy) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = _tracks.length;
    final selected = _selectedCount();
    final done = _selectedDoneCount();
    final failed = _count(TrackStatus.failed);
    final allDone = selected > 0 && done == selected;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Downloads',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: busy ? null : () => _selectAll(selected != total),
                child: Text(
                  selected == total ? 'Limpar seleção' : 'Selecionar tudo',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatChip(
                icon: Icons.queue_music_rounded,
                text: '$selected de $total selecionados',
                color: scheme.primary,
              ),
              StatChip(
                icon: Icons.check_circle_rounded,
                text: '$done concluídos',
                color: context.tokens.success,
              ),
              if (failed > 0)
                StatChip(
                  icon: Icons.error_rounded,
                  text: '$failed com erro',
                  color: scheme.error,
                ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: total == 0 ? 0 : done / total,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          if (_savedTo != null) ...[
            const SizedBox(height: 10),
            Text(
              'Guardado em: $_savedTo',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (_downloading)
            OutlinedButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Parar'),
            )
          else
            PrimaryButton(
              onPressed: busy || allDone || selected == 0
                  ? null
                  : _startDownload,
              icon: allDone ? Icons.check_rounded : Icons.download_rounded,
              label: allDone
                  ? 'Tudo baixado'
                  : done > 0 || failed > 0
                  ? 'Continuar'
                  : selected == total
                  ? 'Baixar tudo em MP3'
                  : 'Baixar selecionadas ($selected)',
            ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget step(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );

    final desktop = context.isDesktopLayout;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
      child: Column(
        children: [
          if (desktop) ...[
            Container(
              width: 96,
              height: 96,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF14141A),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Image.asset('assets/icon/logo.png'),
            ),
            const SizedBox(height: 20),
          ],
          Text(
            'Como funciona',
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          step(
            Icons.content_copy_rounded,
            'Copie o link de uma playlist pública do YouTube',
          ),
          step(
            Icons.content_paste_rounded,
            desktop
                ? 'Cole-o no campo à esquerda: a lista carrega sozinha'
                : 'Cole-o acima e carregue a lista de vídeos',
          ),
          step(
            Icons.library_music_rounded,
            'Cada vídeo é convertido em MP3 e guardado na pasta escolhida',
          ),
        ],
      ),
    );
  }
}

/// Translucent pill used over the warm desktop gradient.
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(context.tokens.radiusControl);
    return Material(
      color: scheme.onSurface.withValues(alpha: 0.09),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onPressed,
        child: SizedBox(
          height: context.tokens.controlHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: scheme.onSurface),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
