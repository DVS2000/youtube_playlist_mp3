import 'dart:convert';
import 'dart:io';

class AudioSource {
  const AudioSource({
    required this.url,
    required this.sizeBytes,
    required this.bitrate,
    required this.userAgent,
  });

  final Uri url;
  final int sizeBytes;
  final int bitrate;
  final String userAgent;
}

class VideoUnavailableException implements Exception {
  VideoUnavailableException(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// Finds a direct, downloadable audio-only stream for a YouTube video.
///
/// Uses the same InnerTube "VISIONOS" client that yt-dlp relies on, which
/// returns plain URLs without needing a PO token or a JavaScript player.
class AudioResolver {
  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';
  static const _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  String? _visitorData;

  void close() => _http.close(force: true);

  Future<AudioSource> resolve(String videoId) async {
    try {
      return await _resolveOnce(videoId);
    } on VideoUnavailableException catch (e) {
      // A stale visitor id is the usual cause of "confirm you're not a bot".
      if (!e.reason.toLowerCase().contains('bot')) rethrow;
      _visitorData = null;
      return _resolveOnce(videoId);
    }
  }

  Future<AudioSource> _resolveOnce(String videoId) async {
    final visitorData = _visitorData ??= await _fetchVisitorData(videoId);

    final response = await _postJson(
      'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
      {
        'context': {
          'client': {
            'clientName': 'VISIONOS',
            'clientVersion': '1.02',
            'deviceMake': 'Apple',
            'deviceModel': 'RealityDevice17,1',
            'userAgent': _userAgent,
            'osName': 'visionOS',
            'osVersion': '26.5.23O471',
            'hl': 'en',
            'visitorData': visitorData,
          },
        },
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
      },
      visitorData,
    );

    final status = response['playabilityStatus']?['status'];
    if (status != 'OK') {
      final reason = response['playabilityStatus']?['reason'] ?? status;
      throw VideoUnavailableException('Vídeo indisponível: $reason');
    }

    final formats =
        (response['streamingData']?['adaptiveFormats'] as List?)
            ?.whereType<Map>()
            .where(
              (f) =>
                  (f['mimeType'] as String?)?.startsWith('audio/') == true &&
                  f['url'] is String &&
                  f['contentLength'] != null,
            )
            .toList() ??
        [];
    if (formats.isEmpty) {
      throw VideoUnavailableException('Sem stream de áudio disponível');
    }

    formats.sort(
      (a, b) =>
          ((b['bitrate'] as num?) ?? 0).compareTo((a['bitrate'] as num?) ?? 0),
    );
    final best = formats.first;
    return AudioSource(
      url: Uri.parse(best['url'] as String),
      sizeBytes: int.parse(best['contentLength'].toString()),
      bitrate: ((best['bitrate'] as num?) ?? 0).toInt(),
      userAgent: _userAgent,
    );
  }

  Future<String> _fetchVisitorData(String videoId) async {
    final req = await _http.getUrl(
      Uri.parse('https://www.youtube.com/watch?v=$videoId&hl=en'),
    );
    req.headers
      ..set('User-Agent', _browserUserAgent)
      ..set('Accept-Language', 'en-US,en;q=0.9')
      ..set('Cookie', 'CONSENT=YES+1; SOCS=CAI');
    final res = await req.close();
    final html = await utf8.decoder.bind(res).join();
    final match = RegExp(r'"visitorData":"([^"]+)"').firstMatch(html);
    if (match == null) {
      throw VideoUnavailableException('Não foi possível contactar o YouTube');
    }
    return match.group(1)!;
  }

  Future<Map<String, dynamic>> _postJson(
    String url,
    Map<String, dynamic> body,
    String visitorData,
  ) async {
    final req = await _http.postUrl(Uri.parse(url));
    req.headers
      ..set('Content-Type', 'application/json')
      ..set('User-Agent', _userAgent)
      ..set('X-YouTube-Client-Name', '101')
      ..set('X-YouTube-Client-Version', '1.02')
      ..set('X-Goog-Visitor-Id', visitorData)
      ..set('Origin', 'https://www.youtube.com');
    req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close();
    final text = await utf8.decoder.bind(res).join();
    if (res.statusCode != 200) {
      throw VideoUnavailableException('YouTube respondeu ${res.statusCode}');
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }
}
