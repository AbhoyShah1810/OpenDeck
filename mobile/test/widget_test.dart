import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/storage/bonded_repository.dart';
import 'package:mobile/core/storage/profile_repository.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('OpenDeckApp smoke test', (WidgetTester tester) async {
    final profileRepo = ProfileRepository();
    final bondedRepo = BondedRepository();

    await tester.pumpWidget(OpenDeckApp(
      profileRepo: profileRepo,
      bondedRepo: bondedRepo,
    ));

    expect(find.text('General'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });
}
