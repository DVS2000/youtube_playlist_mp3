import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:youtube_playlist_mp3/main.dart';

/// End-to-end: real network, real ffmpeg, real file written to disk.
/// Run with: flutter test integration_test -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('baixa o primeiro vídeo de uma playlist como MP3', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'https://www.youtube.com/playlist?list=PL6eeKdoK3f-rDbZ5ETkDH-WJApwyeRFkc',
    );
    await tester.tap(find.text('Carregar playlist'));

    Future<bool> waitFor(Finder f, Duration timeout) async {
      final end = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 300));
        if (f.evaluate().isNotEmpty) return true;
      }
      return false;
    }

    expect(
      await waitFor(
        find.text('Baixar tudo em MP3'),
        const Duration(seconds: 60),
      ),
      isTrue,
      reason: 'a playlist devia carregar',
    );

    final downloadButton = find.text('Baixar tudo em MP3');
    // macOS desktop uses a scrollable sidebar; this keeps the test valid on
    // the 800x600 test surface as well as on the normal 1120x740 window.
    await tester.dragFrom(const Offset(180, 540), const Offset(180, 180));
    await tester.pumpAndSettle();
    await tester.ensureVisible(downloadButton);
    await tester.tap(downloadButton);
    final done = await waitFor(
      find.text('Concluído'),
      const Duration(minutes: 3),
    );
    final failedText = find.textContaining('indisponível');
    debugPrint(
      'primeiro vídeo concluído: $done, falhas visíveis: ${failedText.evaluate().length}',
    );

    await tester.tap(find.text('Parar'));
    await tester.pump(const Duration(seconds: 2));
    expect(
      done,
      isTrue,
      reason: 'um vídeo devia terminar a conversão e ser guardado',
    );

    final downloads = '${Platform.environment['HOME']}/Downloads';
    final mp3s = Directory(downloads)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.mp3') && f.path.contains('Billboard'))
        .toList();
    debugPrint(
      'MP3 encontrados: ${mp3s.map((f) => '${f.path} (${f.lengthSync()} bytes)').toList()}',
    );
    expect(mp3s, isNotEmpty);
  });
}
