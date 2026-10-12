import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/widgets/puzzle.dart';

/// docs/51 §7: the cut of a picture comes from its id alone, so every phone draws the same
/// pieces, and two neighbours always fit — a knob on one side is a hole on the other.
void main() {
  const cell = Size(40, 40);

  test('the hash is FNV-1a and the same on every run', () {
    // The reference values of 32-bit FNV-1a, not whatever this process happens to compute.
    expect(puzzleHash(''), 0x811c9dc5);
    expect(puzzleHash('a'), 0xe40c292c);
    expect(puzzleHash('foobar'), 0xbf9cf968);
  });

  test('the same picture is cut the same way, another one differently', () {
    const a = PuzzleCut(imageId: '8c1d6a7e-0d4f-4b55-9a1e-3f2f0c0e9b11', rows: 4, cols: 3);
    const again = PuzzleCut(imageId: '8c1d6a7e-0d4f-4b55-9a1e-3f2f0c0e9b11', rows: 4, cols: 3);
    const other = PuzzleCut(imageId: 'b7f0e2a4-5c6d-4e8f-9a0b-1c2d3e4f5a6b', rows: 4, cols: 3);
    List<int> tabs(PuzzleCut c) => [for (var i = 0; i < c.pieces; i++) for (final s in PieceSide.values) c.tab(i, s)];
    expect(tabs(again), tabs(a));
    expect(a.edge(4, PieceSide.right, cell), again.edge(4, PieceSide.right, cell));
    expect(tabs(other), isNot(tabs(a)));
  });

  for (final (rows, cols) in const [(4, 3), (5, 4), (6, 5)]) {
    final cut = PuzzleCut(imageId: 'demo-$rows-$cols', rows: rows, cols: cols);

    test('$rows × $cols: the border is flat and nothing else is', () {
      for (var i = 0; i < cut.pieces; i++) {
        final r = i ~/ cols, c = i % cols;
        expect(cut.tab(i, PieceSide.top) == 0, r == 0);
        expect(cut.tab(i, PieceSide.bottom) == 0, r == rows - 1);
        expect(cut.tab(i, PieceSide.left) == 0, c == 0);
        expect(cut.tab(i, PieceSide.right) == 0, c == cols - 1);
      }
    });

    test('$rows × $cols: neighbours are complementary and share one edge', () {
      for (var i = 0; i < cut.pieces; i++) {
        final r = i ~/ cols, c = i % cols;
        if (c < cols - 1) {
          expect(cut.tab(i, PieceSide.right), -cut.tab(i + 1, PieceSide.left));
          expect(cut.edge(i, PieceSide.right, cell), cut.edge(i + 1, PieceSide.left, cell).reversed.toList());
        }
        if (r < rows - 1) {
          expect(cut.tab(i, PieceSide.bottom), -cut.tab(i + cols, PieceSide.top));
          expect(cut.edge(i, PieceSide.bottom, cell), cut.edge(i + cols, PieceSide.top, cell).reversed.toList());
        }
      }
    });

    test('$rows × $cols: a knob leaves its cell, a hole stays inside it', () {
      for (var i = 0; i < cut.pieces; i++) {
        final box = cut.cellRect(i, cell);
        final bounds = cut.piece(i, cell).getBounds();
        expect(bounds.right > box.right + 5, cut.tab(i, PieceSide.right) == 1);
        expect(bounds.bottom > box.bottom + 5, cut.tab(i, PieceSide.bottom) == 1);
        expect(bounds.left < box.left - 5, cut.tab(i, PieceSide.left) == 1);
        expect(bounds.top < box.top - 5, cut.tab(i, PieceSide.top) == 1);
      }
    });
  }
}
