import 'dart:io';

/// Downloads a googlevideo URL to [target] using ranged requests.
///
/// YouTube throttles or stalls non-ranged downloads, so the file is fetched in
/// fixed-size chunks. Redirects are followed automatically.
Future<void> downloadRanged({
  required HttpClient client,
  required Uri url,
  required int totalBytes,
  required File target,
  required bool Function() isCancelled,
  required void Function(double progress) onProgress,
  int chunkSize = 1024 * 1024,
}) async {
  final sink = target.openWrite();
  var offset = 0;
  try {
    while (offset < totalBytes) {
      if (isCancelled()) return;
      final end = (offset + chunkSize - 1).clamp(0, totalBytes - 1);
      var attempt = 0;
      while (true) {
        try {
          final ranged = url.replace(
            queryParameters: {...url.queryParameters, 'range': '$offset-$end'},
          );
          final req = await client.getUrl(ranged);
          req.headers
            ..set(
              'User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            )
            ..set('Accept', '*/*');
          final res = await req.close().timeout(const Duration(seconds: 30));
          if (res.statusCode != 200 && res.statusCode != 206) {
            await res.drain<void>();
            throw HttpException('HTTP ${res.statusCode}');
          }
          var got = 0;
          await for (final data in res.timeout(const Duration(seconds: 30))) {
            sink.add(data);
            got += data.length;
          }
          if (got == 0) throw const HttpException('Resposta vazia');
          offset += got;
          break;
        } on Exception {
          if (++attempt >= 3) rethrow;
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      onProgress(offset / totalBytes);
    }
  } finally {
    await sink.close();
  }
}
