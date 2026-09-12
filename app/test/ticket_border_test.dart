import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verspaetomat/widgets/kit.dart';

/// The Fahrkarte's silhouette (docs/32). The teeth are the whole point: a card that loses them
/// is a rounded box again, and one that is bitten in the wrong place looks like a rendering
/// fault rather than perforation.
void main() {
  const border = VTicketBorder();
  const rect = Rect.fromLTWH(0, 0, 360, 200);
  final path = border.getOuterPath(rect);

  test('the middle of the card is card', () {
    expect(path.contains(const Offset(180, 100)), isTrue);
  });

  test('a tooth is bitten out of the top and the bottom edge', () {
    // The teeth are centred: 25 of them fit across 360 px, so the first centre sits at
    // (360 - 25 * 14) / 2 + 7 = 12.
    const firstTooth = 12.0;
    expect(path.contains(const Offset(firstTooth, 1)), isFalse, reason: 'top tooth');
    expect(path.contains(const Offset(firstTooth, 199)), isFalse, reason: 'bottom tooth');
    // Between two teeth the edge is still paper.
    expect(path.contains(const Offset(firstTooth + 7, 1)), isTrue);
  });

  test('no tooth is cut in half by a corner', () {
    expect(path.contains(const Offset(1, 1)), isTrue);
    expect(path.contains(const Offset(359, 199)), isTrue);
  });

  test('the bite never reaches the content', () {
    // Everything below the teeth belongs to the card, which is why VFahrkarte keeps
    // VTicketBorder.bite of padding above the first line.
    for (var x = 0.0; x < 360; x += 1) {
      expect(path.contains(Offset(x, VTicketBorder.bite + 0.5)), isTrue, reason: 'x = $x');
    }
  });

  test('a card too narrow for one tooth is a plain rectangle, not a crash', () {
    const narrow = Rect.fromLTWH(0, 0, 10, 20);
    final p = border.getOuterPath(narrow);
    expect(p.contains(const Offset(5, 0.5)), isTrue);
    expect(() => border.getOuterPath(Rect.zero), returnsNormally);
  });
}
