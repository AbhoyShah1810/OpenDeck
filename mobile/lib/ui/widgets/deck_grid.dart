import 'package:flutter/material.dart';
import '../../models/deck_tile.dart';
import 'deck_tile_button.dart';

/// Responsive Grid widget supporting 3x3, 4x4, and customizable MxN layouts
class DeckGrid extends StatelessWidget {
  final List<DeckTile> tiles;
  final int columns;
  final Function(DeckTile tile) onTileTap;
  final Function(DeckTile tile) onTileEdit;

  const DeckGrid({
    super.key,
    required this.tiles,
    this.columns = 3,
    required this.onTileTap,
    required this.onTileEdit,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          padding: const EdgeInsets.all(16.0),
          physics: const BouncingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.0,
          ),
          itemCount: tiles.length,
          itemBuilder: (context, index) {
            final tile = tiles[index];
            return DeckTileButton(
              tile: tile,
              onTap: () => onTileTap(tile),
              onLongPress: () => onTileEdit(tile),
            );
          },
        );
      },
    );
  }
}
