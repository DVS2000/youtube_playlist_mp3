import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_playlist_mp3/services/mp3_saver.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('guarda e restaura o acesso a uma pasta (sandbox macOS)', (
    tester,
  ) async {
    final saver = Mp3Saver();
    final base = (await getDownloadsDirectory())!;
    final dir = await Directory('${base.path}/teste_pasta').create();

    // Same call the app makes after the user picks a folder.
    const channel = MethodChannelProbe();
    expect(await channel.save(dir.path), isTrue);

    final restored = await saver.savedDirectory();
    expect(restored, isNotNull);
    expect(await Directory(restored!).exists(), isTrue);

    await saver.verifyWritable(restored);
    final out = await saver.save(
      tempPath: (await File('${dir.path}/a.tmp').writeAsString('x')).path,
      fileName: 'a.mp3',
      folder: 'lista',
      baseDir: restored,
    );
    expect(File('$out/a.mp3').existsSync(), isTrue);
    await dir.delete(recursive: true);
  });
}

class MethodChannelProbe {
  const MethodChannelProbe();
  Future<bool> save(String path) async =>
      (await const _Ch().invoke('saveBookmark', path)) == true;
}

class _Ch {
  const _Ch();
  Future<Object?> invoke(String m, Object? a) => _channel.invokeMethod(m, a);
}

const _channel = MethodChannel('folder_access');
