import 'dart:convert';
import 'dart:io';

class PlaylistVideo {
  const PlaylistVideo({
    required this.id,
    required this.title,
    required this.author,
  });

  final String id;
  final String title;
  final String author;
}

class PlaylistInfo {
  const PlaylistInfo({
    required this.id,
    required this.title,
    required this.videos,
  });

  final String id;
  final String title;
  final List<PlaylistVideo> videos;
}

class InvalidPlaylistException implements Exception {
  @override
  String toString() => 'Link de playlist inválido.';
}

class PlaylistUnavailableException implements Exception {
  PlaylistUnavailableException([this.detail]);

  /// Technical reason, shown in small print to help diagnose failures.
  final String? detail;

  @override
  String toString() =>
      'Não foi possível ler a playlist. Verifique se ela é pública ou não listada.'
      '${detail == null ? '' : '\n($detail)'}';
}

/// Reads the full video list of a YouTube playlist straight from YouTube's
/// web endpoints. Understands both the legacy (`playlistVideoRenderer`) and the
/// current (`lockupViewModel`) page layouts, and follows pagination.
class PlaylistFetcher {
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
  static const _fallbackKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const _fallbackVersion = '2.20260101.00.00';

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);

  void close() => _http.close(force: true);

  /// Extracts the playlist id from a URL (or a bare id).
  static String parseId(String input) {
    final text = input.trim();
    final uri = Uri.tryParse(text);
    final fromQuery = uri?.queryParameters['list'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    if (RegExp(r'^(PL|UU|LL|FL|OL|RD)[A-Za-z0-9_-]{10,}$').hasMatch(text)) {
      return text;
    }
    throw InvalidPlaylistException();
  }

  Future<PlaylistInfo> fetch(String input) async {
    final id = parseId(input);
    var apiKey = _fallbackKey;
    var version = _fallbackVersion;
    Map<String, dynamic>? data;
    final problems = <String>[];

    // 1) The regular web page, which embeds the first batch of videos.
    try {
      final html = await _get(
        'https://www.youtube.com/playlist?list=$id&hl=en&persist_hl=1',
      );
      apiKey =
          RegExp(r'"INNERTUBE_API_KEY":"([^"]+)"').firstMatch(html)?.group(1) ??
          apiKey;
      version =
          RegExp(
            r'"INNERTUBE_CLIENT_VERSION":"([^"]+)"',
          ).firstMatch(html)?.group(1) ??
          version;
      data = _extractInitialData(html);
      if (data == null || _findVideos(data).isEmpty) {
        problems.add('página sem vídeos');
        data = null;
      }
    } on PlaylistUnavailableException catch (e) {
      problems.add(e.detail ?? 'página indisponível');
    } on SocketException catch (e) {
      throw PlaylistUnavailableException('sem ligação: ${e.message}');
    }

    // 2) Fallback that does not depend on the page layout: the browse API.
    if (data == null) {
      try {
        data = await _post(
          'https://www.youtube.com/youtubei/v1/browse?key=$apiKey&prettyPrint=false',
          {
            'context': {
              'client': {
                'clientName': 'WEB',
                'clientVersion': version,
                'hl': 'en',
              },
            },
            'browseId': 'VL$id',
          },
        );
        if (_findVideos(data).isEmpty) {
          problems.add('API sem vídeos');
          data = null;
        }
      } on PlaylistUnavailableException catch (e) {
        problems.add(e.detail ?? 'API indisponível');
      }
    }
    // 3) Auto-generated Mixes ("RD...") cannot be opened as a playlist page;
    // YouTube only exposes them through the watch-page "next" endpoint.
    if (data == null && id.startsWith('RD')) {
      final mix = await _fetchMix(
        id: id,
        input: input,
        apiKey: apiKey,
        version: version,
      );
      if (mix != null) return mix;
      problems.add('Mix indisponível');
    }
    if (data == null) {
      throw PlaylistUnavailableException(problems.join('; '));
    }

    final title = _findTitle(data) ?? 'Playlist';
    final videos = <PlaylistVideo>[];
    final seen = <String>{};

    void collect(Object? node) {
      for (final v in _findVideos(node)) {
        if (seen.add(v.id)) videos.add(v);
      }
    }

    collect(data);
    var token = _findContinuation(data);
    var guard = 0;
    while (token != null && guard++ < 200) {
      final next = await _post(
        'https://www.youtube.com/youtubei/v1/browse?key=$apiKey&prettyPrint=false',
        {
          'context': {
            'client': {
              'clientName': 'WEB',
              'clientVersion': version,
              'hl': 'en',
            },
          },
          'continuation': token,
        },
      );
      final before = videos.length;
      collect(next);
      final newToken = _findContinuation(next);
      if (videos.length == before || newToken == token) break;
      token = newToken;
    }

    if (videos.isEmpty) throw PlaylistUnavailableException('lista vazia');
    return PlaylistInfo(id: id, title: title, videos: videos);
  }

  /// Reads a YouTube Mix. Mixes are endless, so only the first few batches
  /// (about 25 videos each) are collected.
  Future<PlaylistInfo?> _fetchMix({
    required String id,
    required String input,
    required String apiKey,
    required String version,
  }) async {
    var videoId = Uri.tryParse(input.trim())?.queryParameters['v'];
    // "RD<videoId>" mixes carry the seed video in their own id.
    if (videoId == null && id.length == 13) videoId = id.substring(2);
    if (videoId == null) return null;

    final videos = <PlaylistVideo>[];
    final seen = <String>{};
    String? title;
    var currentVideo = videoId;

    for (var batch = 0; batch < 3; batch++) {
      final data = await _post(
        'https://www.youtube.com/youtubei/v1/next?key=$apiKey&prettyPrint=false',
        {
          'context': {
            'client': {
              'clientName': 'WEB',
              'clientVersion': version,
              'hl': 'en',
            },
          },
          'videoId': currentVideo,
          'playlistId': id,
          if (videos.isNotEmpty) 'playlistIndex': videos.length,
        },
      );
      title ??=
          data['contents']?['twoColumnWatchNextResults']?['playlist']?['playlist']?['title']
              as String?;
      final before = videos.length;
      for (final v in _findVideos(
        data['contents']?['twoColumnWatchNextResults']?['playlist'],
      )) {
        if (seen.add(v.id)) videos.add(v);
      }
      if (videos.length == before) break;
      currentVideo = videos.last.id;
    }

    if (videos.isEmpty) return null;
    return PlaylistInfo(id: id, title: title ?? 'Mix', videos: videos);
  }

  // ---------------------------------------------------------------- parsing

  static Map<String, dynamic>? _extractInitialData(String html) {
    const markers = ['var ytInitialData = ', 'window["ytInitialData"] = '];
    for (final marker in markers) {
      final start = html.indexOf(marker);
      if (start < 0) continue;
      final jsonStart = start + marker.length;
      final end = _matchingBrace(html, jsonStart);
      if (end < 0) continue;
      try {
        return jsonDecode(html.substring(jsonStart, end + 1))
            as Map<String, dynamic>;
      } catch (_) {}
    }
    return null;
  }

  /// Index of the `}` closing the object that opens at [start].
  static int _matchingBrace(String s, int start) {
    var depth = 0;
    var inString = false;
    for (var i = start; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (inString) {
        if (c == 0x5C) {
          i++; // skip escaped char
        } else if (c == 0x22) {
          inString = false;
        }
      } else if (c == 0x22) {
        inString = true;
      } else if (c == 0x7B) {
        depth++;
      } else if (c == 0x7D) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static String? _findTitle(Map<String, dynamic> data) {
    final meta = data['metadata']?['playlistMetadataRenderer']?['title'];
    if (meta is String && meta.isNotEmpty) return meta;
    final header = data['header']?['pageHeaderRenderer']?['pageTitle'];
    if (header is String && header.isNotEmpty) return header;
    return null;
  }

  /// Walks the whole JSON tree and yields every playlist video found.
  static Iterable<PlaylistVideo> _findVideos(Object? node) sync* {
    if (node is Map) {
      final panel = node['playlistPanelVideoRenderer'];
      if (panel is Map) {
        final id = panel['videoId'];
        final title = _text(panel['title']);
        if (id is String && title != null) {
          yield PlaylistVideo(
            id: id,
            title: title,
            author: _text(panel['shortBylineText']) ?? '',
          );
        }
        return;
      }
      final legacy = node['playlistVideoRenderer'];
      if (legacy is Map) {
        final id = legacy['videoId'];
        final title = _text(legacy['title']);
        if (id is String && title != null) {
          yield PlaylistVideo(
            id: id,
            title: title,
            author: _text(legacy['shortBylineText']) ?? '',
          );
        }
        return;
      }
      final lockup = node['lockupViewModel'];
      if (lockup is Map) {
        if (lockup['contentType'] == 'LOCKUP_CONTENT_TYPE_VIDEO' &&
            lockup['contentId'] is String) {
          final meta = lockup['metadata']?['lockupMetadataViewModel'];
          final title = meta?['title']?['content'];
          if (title is String) {
            yield PlaylistVideo(
              id: lockup['contentId'] as String,
              title: title,
              author: _lockupAuthor(meta),
            );
          }
        }
        return;
      }
      for (final value in node.values) {
        yield* _findVideos(value);
      }
    } else if (node is List) {
      for (final item in node) {
        yield* _findVideos(item);
      }
    }
  }

  static String _lockupAuthor(dynamic meta) {
    try {
      final rows = meta['metadata']['contentMetadataViewModel']['metadataRows'];
      return rows[0]['metadataParts'][0]['text']['content'] as String;
    } catch (_) {
      return '';
    }
  }

  static String? _text(Object? t) {
    if (t is Map) {
      if (t['simpleText'] is String) return t['simpleText'] as String;
      final runs = t['runs'];
      if (runs is List) {
        return runs.map((r) => r is Map ? r['text'] ?? '' : '').join();
      }
    }
    return null;
  }

  /// Finds the next-page token. Handles both `continuationItemRenderer`
  /// (legacy) and `continuationItemViewModel` (current) layouts.
  static String? _findContinuation(Object? node) {
    if (node is Map) {
      for (final key in [
        'continuationItemRenderer',
        'continuationItemViewModel',
      ]) {
        final item = node[key];
        if (item != null) {
          final token = _firstToken(item);
          if (token != null) return token;
        }
      }
      for (final value in node.values) {
        final found = _findContinuation(value);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final item in node) {
        final found = _findContinuation(item);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// First `continuationCommand.token` anywhere inside [node].
  static String? _firstToken(Object? node) {
    if (node is Map) {
      final command = node['continuationCommand'];
      if (command is Map && command['token'] is String) {
        return command['token'] as String;
      }
      for (final value in node.values) {
        final found = _firstToken(value);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final item in node) {
        final found = _firstToken(item);
        if (found != null) return found;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------- network

  Future<String> _get(String url) async {
    final req = await _http.getUrl(Uri.parse(url));
    req.headers
      ..set('User-Agent', _userAgent)
      ..set('Accept-Language', 'en-US,en;q=0.9')
      ..set('Cookie', 'CONSENT=YES+1; SOCS=CAI');
    final res = await req.close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw PlaylistUnavailableException('HTTP ${res.statusCode}');
    }
    return utf8.decoder.bind(res).join();
  }

  Future<Map<String, dynamic>> _post(
    String url,
    Map<String, dynamic> body,
  ) async {
    final req = await _http.postUrl(Uri.parse(url));
    req.headers
      ..set('User-Agent', _userAgent)
      ..set('Content-Type', 'application/json')
      ..set('Accept-Language', 'en-US,en;q=0.9')
      ..set('Origin', 'https://www.youtube.com')
      ..set('Cookie', 'CONSENT=YES+1; SOCS=CAI');
    req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close();
    final text = await utf8.decoder.bind(res).join();
    if (res.statusCode != 200) {
      throw PlaylistUnavailableException('API HTTP ${res.statusCode}');
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }
}
