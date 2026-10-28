import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'playlist_downloader.dart';

/// Audio handler with a short DJ-style overlap between adjacent tracks.
/// Two players are used so the outgoing track can fade down while the next
/// track fades up, without interrupting lock-screen or Control Center metadata.
class PlaylistAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  PlaylistAudioHandler() {
    _attach(_player);
    _attach(_secondary);
  }

  AudioPlayer _player = AudioPlayer();
  AudioPlayer _secondary = AudioPlayer();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _activeChanged = StreamController<void>.broadcast();
  final _items = <MediaItem>[];

  int _index = -1;
  bool _crossfading = false;
  Timer? _fadeTimer;
  static const _fadeDuration = Duration(seconds: 6);

  AudioPlayer get player => _player;
  Stream<Duration> get positionStream => _position.stream;
  Stream<Duration?> get durationStream => _duration.stream;
  Stream<bool> get playingStream => _playing.stream;
  Stream<void> get activePlayerStream => _activeChanged.stream;
  Stream<LoopMode> get loopModeStream => _player.loopModeStream;
  Stream<bool> get shuffleModeStream => _player.shuffleModeEnabledStream;

  Future<void> configure() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  void _attach(AudioPlayer source) {
    source.positionStream.listen((position) {
      if (identical(source, _player)) {
        _position.add(position);
        _checkCrossfade(source, position);
      }
    });
    source.durationStream.listen((duration) {
      if (!identical(source, _player)) return;
      _duration.add(duration);
      _applyDuration();
    });
    source.playingStream.listen((playing) {
      if (identical(source, _player)) _playing.add(playing);
    });
    source.playbackEventStream.listen((event) {
      if (identical(source, _player)) _broadcastState(event);
    });
    source.processingStateStream.listen((state) {
      if (identical(source, _player) &&
          state == ProcessingState.completed &&
          !_crossfading) {
        unawaited(_advanceAfterCompletion());
      }
    });
  }

  /// Durations already discovered, keyed by file path. The system player
  /// (notification, lock screen, Control Center) only shows the elapsed and
  /// total time when the [MediaItem] carries its duration.
  final _durations = <String, Duration>{};

  MediaItem _withDuration(MediaItem item) {
    final known = _durations[item.id];
    return known == null ? item : item.copyWith(duration: known);
  }

  /// Publishes the active player's duration on the current [MediaItem].
  void _applyDuration() {
    if (_index < 0 || _index >= _items.length) return;
    final duration = _player.duration;
    if (duration == null || duration == Duration.zero) return;
    final item = _items[_index];
    // While switching tracks the player may still report the previous
    // source, so only accept a duration that belongs to the current item.
    final loaded = _player.sequenceState.currentSource?.tag;
    if (loaded is MediaItem && loaded.id != item.id) return;
    if (item.duration == duration) return;
    _durations[item.id] = duration;
    _items[_index] = item.copyWith(duration: duration);
    mediaItem.add(_items[_index]);
    queue.add(List.unmodifiable(_items));
  }

  AudioSource _source(MediaItem item) =>
      AudioSource.uri(_uri(item.id), tag: item);

  Uri _uri(String path) =>
      path.startsWith('content://') || path.startsWith('file://')
      ? Uri.parse(path)
      : Uri.file(path);

  Future<void> loadTracks(List<TrackState> tracks) async {
    final previousId = mediaItem.value?.id;
    final previousPosition = _player.position;
    final wasPlaying = _player.playing;
    _items
      ..clear()
      ..addAll(
        tracks
            .where((track) => track.filePath != null)
            .map(
              (track) => _withDuration(
                MediaItem(
                  id: track.filePath!,
                  album: 'Playlist MP3',
                  title: track.video.title,
                  artist: track.video.author.isEmpty
                      ? 'YouTube'
                      : track.video.author,
                  artUri: track.artworkPath == null
                      ? null
                      : Uri.file(track.artworkPath!),
                ),
              ),
            ),
      );
    queue.add(List.unmodifiable(_items));

    if (_items.isEmpty) {
      await _player.stop();
      await _secondary.stop();
      _index = -1;
      mediaItem.add(null);
      return;
    }

    // Downloading another item should extend the queue, not restart the
    // song that is already playing (or interrupt an active crossfade).
    if (previousId != null && _items.any((item) => item.id == previousId)) {
      _index = _items.indexWhere((item) => item.id == previousId);
      mediaItem.add(_items[_index]);
      return;
    }

    var nextIndex = previousId == null
        ? 0
        : _items.indexWhere((item) => item.id == previousId);
    if (nextIndex < 0) nextIndex = 0;
    await _stopBoth();
    await _player.setAudioSource(_source(_items[nextIndex]), preload: true);
    await _player.setVolume(1);
    await _secondary.setVolume(0);
    _index = nextIndex;
    mediaItem.add(_items[_index]);
    _applyDuration();
    _activeChanged.add(null);
    if (previousId != null) {
      await _player.seek(previousPosition);
      if (wasPlaying) await _player.play();
    }
  }

  Future<void> _stopBoth() async {
    _fadeTimer?.cancel();
    _crossfading = false;
    await _player.stop();
    await _secondary.stop();
  }

  Future<void> playTrack(int index) async {
    if (_items.isEmpty) return;
    await _switchTo(index.clamp(0, _items.length - 1), play: true);
  }

  Future<void> _switchTo(int index, {required bool play}) async {
    _fadeTimer?.cancel();
    _crossfading = false;
    await _stopBoth();
    await _player.setAudioSource(_source(_items[index]), preload: true);
    await _player.setVolume(1);
    await _secondary.setVolume(0);
    _index = index;
    mediaItem.add(_items[index]);
    _applyDuration();
    _activeChanged.add(null);
    if (play) await _player.play();
  }

  void _checkCrossfade(AudioPlayer source, Duration position) {
    if (_crossfading || !identical(source, _player) || _index < 0) return;
    final duration = source.duration;
    if (duration == null || _index >= _items.length - 1) return;
    final remaining = duration - position;
    if (remaining <= _fadeDuration && remaining > Duration.zero) {
      unawaited(_beginCrossfade());
    }
  }

  Future<void> _beginCrossfade() async {
    if (_crossfading || _index < 0 || _index >= _items.length - 1) return;
    _crossfading = true;
    final outgoing = _player;
    final incoming = _secondary;
    final nextIndex = _index + 1;
    try {
      await incoming.setAudioSource(_source(_items[nextIndex]), preload: true);
      await incoming.setVolume(0);
      await incoming.play();
      final started = DateTime.now();
      _fadeTimer = Timer.periodic(const Duration(milliseconds: 50), (
        timer,
      ) async {
        final progress =
            (DateTime.now().difference(started).inMilliseconds /
                    _fadeDuration.inMilliseconds)
                .clamp(0.0, 1.0);
        await outgoing.setVolume(1 - progress);
        await incoming.setVolume(progress);
        if (progress >= 1) {
          timer.cancel();
          await outgoing.stop();
          await outgoing.setVolume(1);
          _player = incoming;
          _secondary = outgoing;
          _index = nextIndex;
          _crossfading = false;
          mediaItem.add(_items[_index]);
          _applyDuration();
          _activeChanged.add(null);
          _broadcastState(_player.playbackEvent);
        }
      });
    } catch (_) {
      _crossfading = false;
    }
  }

  Future<void> _advanceAfterCompletion() async {
    if (_index < 0 || _index >= _items.length - 1) return;
    await _switchTo(_index + 1, play: true);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _stopBoth();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _index < _items.length - 1
      ? _switchTo(_index + 1, play: true)
      : Future.value();

  @override
  Future<void> skipToPrevious() => _index > 0
      ? _switchTo(_index - 1, play: true)
      : _player.seek(Duration.zero);

  @override
  Future<void> fastForward() =>
      _player.seek(_player.position + const Duration(seconds: 15));

  @override
  Future<void> rewind() =>
      _player.seek(_player.position - const Duration(seconds: 15));

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
    await _secondary.setVolume(0);
  }

  Future<void> setLoopMode(LoopMode mode) async {
    await _player.setLoopMode(mode);
    await _secondary.setLoopMode(mode);
  }

  Future<void> setShuffle(bool enabled) async {
    await _player.setShuffleModeEnabled(enabled);
    await _secondary.setShuffleModeEnabled(enabled);
  }

  void _broadcastState(PlaybackEvent event) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToPrevious,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek, MediaAction.setSpeed},
        androidCompactActionIndices: const [0, 2, 3],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: _player.playing,
        updatePosition: event.updatePosition,
        bufferedPosition: event.bufferedPosition,
        speed: _player.speed,
        queueIndex: _index,
      ),
    );
  }

  Future<void> dispose() async {
    _fadeTimer?.cancel();
    await _player.dispose();
    await _secondary.dispose();
    await _position.close();
    await _duration.close();
    await _playing.close();
    await _activeChanged.close();
  }
}

class PlayerService {
  PlayerService._();
  static final instance = PlayerService._();

  PlaylistAudioHandler? _handler;
  Future<void>? _initializing;

  PlaylistAudioHandler? get handler => _handler;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      JustAudioMediaKit.ensureInitialized();
      _handler = PlaylistAudioHandler();
      await _handler!.configure();
      return;
    }
    _handler = await AudioService.init(
      builder: () => PlaylistAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'playlist_mp3.audio',
        androidNotificationChannelName: 'Reprodução',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidNotificationIcon: 'drawable/ic_stat_music',
        fastForwardInterval: Duration(seconds: 15),
        rewindInterval: Duration(seconds: 15),
      ),
    );
    await _handler!.configure();
  }

  Future<void> loadTracks(List<TrackState> tracks) async {
    await initialize();
    await _handler!.loadTracks(tracks);
  }

  Future<void> dispose() async => _handler?.dispose();
}
