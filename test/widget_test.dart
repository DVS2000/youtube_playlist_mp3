import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_playlist_mp3/main.dart';

void main() {
  testWidgets('mostra o título, o campo de link e o botão de carregar', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Playlist MP3'), findsOneWidget);
    expect(find.text('Cole o link da playlist'), findsOneWidget);
    expect(find.text('Carregar playlist'), findsOneWidget);
  });
}
