import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_http_download.dart';
import 'audio_resolver.dart';
import 'mp3_saver.dart';
import 'playlist_fetcher.dart';

export 'playlist_fetcher.dart'
    show
        InvalidPlaylistException,
        PlaylistInfo,
        PlaylistUnavailableException,
        PlaylistVideo;

enum TrackStatus { pending, downloading, converting, done, failed, skipped }

class TrackState {
  TrackState(this.video);

  final PlaylistVideo video;
  TrackStatus status = TrackStatus.pending;
  bool selected = true;
  double progress = 0;
  String? error;
  String? filePath;
  String? artworkPath;
}

/// Downloads every video of a YouTube playlist as MP3.
class PlaylistDownloader {
  PlaylistDownloader({Mp3Saver? saver}) : _saver = saver ?? Mp3Saver();

  final Mp3Saver _saver;

  Mp3Saver get saver => _saver;
  final PlaylistFetcher _fetcher = PlaylistFetcher();
  final AudioResolver _resolver = AudioResolver();
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  void dispose() {
    _fetcher.close();
    _resolver.close();
    _http.close(force: true);
  }

  /// Resolves the playlist metadata and its videos.
  Future<PlaylistInfo> load(String url) => _fetcher.fetch(url);

  /// Downloads all [tracks]. [onChanged] fires whenever a track changes.
  /// Returns the public location where the files were stored.
  Future<String> downloadAll({
    required String playlistTitle,
    required List<TrackState> tracks,
    required void Function() onChanged,
    String? baseDir,
  }) async {
    _cancelled = false;
    final folder = _sanitize(playlistTitle);
    final tmp = await getTemporaryDirectory();
    final work = await Directory('${tmp.path}/ytmp3').create(recursive: true);
    var location = '';

    for (var i = 0; i < tracks.length; i++) {
      if (_cancelled) break;
      final track = tracks[i];
      if (!track.selected) continue;
      if (track.status == TrackStatus.done) continue;
      track.error = null;
      track.progress = 0;
      final baseName = _sanitize(track.video.title);
      final fileName = '${(i + 1).toString().padLeft(2, '0')} - $baseName.mp3';
      final input = File('${work.path}/${track.video.id}.src');
      final output = File('${work.path}/${track.video.id}.mp3');
      final cover = File('${work.path}/${track.video.id}.jpg');

      try {
        track.status = TrackStatus.downloading;
        onChanged();
        await _downloadAudio(track, input, onChanged);
        if (_cancelled) break;

        track.status = TrackStatus.converting;
        track.progress = 1;
        onChanged();
        await _downloadArtwork(track, cover);
        track.artworkPath = cover.path;
        await _convertToMp3(
          input,
          cover,
          output,
          track.video.title,
          track.video.author,
          playlistTitle,
        );

        location = await _saver.save(
          tempPath: output.path,
          fileName: fileName,
          folder: folder,
          baseDir: baseDir,
        );
        track.filePath = _saver.lastSavedPath;
        track.artworkPath = await _saver.saveArtwork(
          tempPath: cover.path,
          fileName: fileName.replaceFirst(RegExp(r'\.mp3$'), '.jpg'),
          folder: folder,
          baseDir: baseDir,
        );
        track.status = TrackStatus.done;
      } on FolderAccessException {
        // Every remaining track would fail the same way: stop and let the UI
        // ask for a new folder.
        track.status = TrackStatus.pending;
        track.progress = 0;
        rethrow;
      } catch (e) {
        track.status = TrackStatus.failed;
        track.error = _friendly(e);
      } finally {
        for (final f in [input, cover, output]) {
          if (await f.exists()) await f.delete();
        }
        onChanged();
      }
    }

    // Tracks that were not reached because of cancel go back to pending.
    for (final t in tracks) {
      if (t.status == TrackStatus.downloading ||
          t.status == TrackStatus.converting) {
        t.status = TrackStatus.pending;
        t.progress = 0;
      }
    }
    onChanged();
    return location;
  }

  Future<void> _downloadAudio(
    TrackState track,
    File target,
    void Function() onChanged,
  ) async {
    final source = await _resolver.resolve(track.video.id);
    var lastReport = 0.0;
    await downloadRanged(
      client: _http,
      url: source.url,
      totalBytes: source.sizeBytes,
      target: target,
      isCancelled: () => _cancelled,
      onProgress: (p) {
        if (p - lastReport >= 0.01 || p >= 1) {
          lastReport = p;
          track.progress = p;
          onChanged();
        }
      },
    );
  }

  Future<void> _downloadArtwork(TrackState track, File target) async {
    final request = await _http.getUrl(
      Uri.parse('https://i.ytimg.com/vi/${track.video.id}/maxresdefault.jpg'),
    );
    request.headers.set('User-Agent', 'Mozilla/5.0');
    final response = await request.close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw Exception('Não foi possível baixar a capa');
    }
    await response.pipe(target.openWrite());
  }

  Future<void> _convertToMp3(
    File input,
    File cover,
    File output,
    String title,
    String artist,
    String album,
  ) async {
    if (await output.exists()) await output.delete();
    final session = await FFmpegKit.executeWithArguments([
      '-y',
      '-i',
      input.path,
      '-i',
      cover.path,
      '-map',
      '0:a:0',
      '-map',
      '1:v:0',
      '-codec:a',
      'libmp3lame',
      '-b:a',
      '192k',
      '-metadata',
      'title=$title',
      '-metadata',
      'artist=${artist.isEmpty ? 'YouTube' : artist}',
      '-metadata',
      'album=$album',
      '-codec:v',
      'mjpeg',
      '-disposition:v:0',
      'attached_pic',
      '-id3v2_version',
      '3',
      '-metadata:s:v',
      'title=Album cover',
      '-metadata:s:v',
      'comment=Cover (Front)',
      output.path,
    ]);
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code)) {
      throw Exception('Falha na conversão para MP3');
    }
  }

  static String _sanitize(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final result = cleaned.isEmpty ? 'sem_nome' : cleaned;
    return result.length > 120 ? result.substring(0, 120).trim() : result;
  }

  static String _friendly(Object e) {
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }
}
