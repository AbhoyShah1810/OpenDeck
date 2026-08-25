import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/protocol/schema.dart';
import 'package:mobile/models/deck_tile.dart';
import 'package:mobile/ui/widgets/deck_grid.dart';

void main() {
  group('DeckTile & DeckGrid Widget Tests', () {
    test('DeckTile conversion to ActionPayload', () {
      final tile = DeckTile(
        id: 'tile_1',
        label: 'Copy Shortcut',
        colorHex: '#6366F1',
        actionType: ActionType.hotkey,
        modifiers: ['PRIMARY_MOD'],
        key: 'C',
      );

      final payload = tile.toActionPayload();
      expect(payload.id, 'tile_1');
      expect(payload.actionType, ActionType.hotkey);
      expect(payload.modifiers, ['PRIMARY_MOD']);
      expect(payload.key, 'C');
    });

    testWidgets('DeckGrid renders all tiles in 3x3 layout', (WidgetTester tester) async {
      final tiles = List.generate(
        9,
        (i) => DeckTile(
          id: 'tile_$i',
          label: 'Button $i',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeckGrid(
              tiles: tiles,
              columns: 3,
              onTileTap: (_) {},
              onTileEdit: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Button 0'), findsOneWidget);
      expect(find.text('Button 8'), findsOneWidget);
    });
  });
}
