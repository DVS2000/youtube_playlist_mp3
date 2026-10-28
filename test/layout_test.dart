import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_playlist_mp3/main.dart';

void main() {
  for (final size in const [
    Size(360, 740),
    Size(430, 932),
    Size(1120, 740),
    Size(900, 600),
  ]) {
    testWidgets(
      'home sem overflow em ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(const MyApp());
        await tester.pump();
        expect(tester.takeException(), isNull);

        expect(find.text('Cole o link da playlist'), findsOneWidget);
      },
    );
  }
}
