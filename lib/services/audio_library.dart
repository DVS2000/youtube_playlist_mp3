import 'dart:io';

import 'package:flutter/services.dart';

import 'playlist_downloader.dart';

/// Rebuilds a playable queue from a folder that was downloaded previously.
/// Sidecar JPGs written by [Mp3Saver] are matched by the MP3 basename.
class AudioLibrary {
  Future<List<TrackState>> scan(String folderPath) async {
    if (Platform.isAndroid) return _scanAndroid(folderPath);
    final root = Directory(folderPath);
    if (!await root.exists()) return [];
    final files = await root
        .list(recursive: true, followLinks: false)
        .where(
          (entity) =>
              entity is File && entity.path.toLowerCase().endsWith('.mp3'),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));

    return files.map((file) {
      final title = _title(file.path);
      final track =
          TrackState(
              PlaylistVideo(
                id: file.path,
                title: title,
                author: 'Playlist MP3',
              ),
            )
            ..status = TrackStatus.done
            ..selected = true
            ..filePath = file.path;
      final artwork = File(
        '${file.path.substring(0, file.path.length - 4)}.jpg',
      );
      if (artwork.existsSync()) {
        track.artworkPath = artwork.path;
      } else {
        // Older downloads used the title without the numeric track prefix.
        final legacyName = file.path.replaceFirst(
          RegExp(r'^(.*/)?\d+\s*-\s*'),
          r'\1',
        );
        final legacyArtwork = File(
          '${legacyName.substring(0, legacyName.length - 4)}.jpg',
        );
        if (legacyArtwork.existsSync()) track.artworkPath = legacyArtwork.path;
      }
      return track;
    }).toList();
  }

  Future<List<TrackState>> _scanAndroid(String folderPath) async {
    try {
      final rows = await const MethodChannel(
        'mp3_saver',
      ).invokeMethod<List<dynamic>>('listSavedAudio', {'folder': folderPath});
      return (rows ?? []).whereType<Map>().map((row) {
        final uri = row['uri'] as String;
        final title = _title(row['name'] as String);
        return TrackState(
            PlaylistVideo(id: uri, title: title, author: 'Playlist MP3'),
          )
          ..status = TrackStatus.done
          ..selected = true
          ..filePath = uri;
      }).toList();
    } on PlatformException {
      return [];
    }
  }

  String _title(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final withoutExtension = name.replaceFirst(
      RegExp(r'\.mp3$', caseSensitive: false),
      '',
    );
    return withoutExtension.replaceFirst(RegExp(r'^\d+\s*-\s*'), '');
  }
}
