import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'header_scene.dart';
import 'surfaces.dart';

/// The kit is one import for the whole design system. The pieces live in several files because
/// one file of three thousand lines is not a system, it is a drawer — but a screen should never
/// have to know which drawer a widget came out of, so everything comes back out here.
export 'connection.dart';
export 'figures.dart';
export 'hand.dart';
export 'header_scene.dart';
export 'inputs.dart';
export 'marks.dart';
export 'profile.dart';
export 'rows.dart';
export 'scaffold.dart';
export 'sheet_scene.dart';
export 'skeleton.dart';
export 'steps.dart';
export 'surfaces.dart';
export 'timeline.dart';

// ---------------------------------------------------------------------------
// Page scaffolding
// ---------------------------------------------------------------------------

/// A sub-screen: the page ground, the page gutter, and the standard header — a back arrow, a
/// caption eyebrow and a title. The tabs do not use this; they have their own scaffold with the
/// illustrated band behind the header.
class VScreen extends StatelessWidget {
  const VScreen({
    super.key,
    required this.child,
    this.title,
    this.eyebrow,
    this.trailing,
    this.showBack = true,
    this.scroll = true,
    this.bottom,
    this.art,
    this.onClose,
    this.padding = const EdgeInsets.fromLTRB(VSpace.l, VSpace.m, VSpace.l, VSpace.l),
  });

  /// How far the back arrow's 44 pt box hangs left of its glyph.
  ///
  /// The button is [VControl.touch] wide so a thumb can find it, but the arrow drawn inside is
  /// 22 pt and centred, so the box starts eleven points left of the ink. Pulling the box back by
  /// exactly that puts the *glyph* on the page gutter, which is where the title and every line of
  /// the body start. Without it a sub-screen has three left edges: the arrow at 19, the title at
  /// 52 and the text at 16.
  static const _glyphInset = (VControl.touch - 22) / 2;

  final Widget child;
  final String? title;
  final String? eyebrow;
  final Widget? trailing;
  final bool showBack;
  final bool scroll;
  final Widget? bottom;

  /// A drawing laid behind the header, running off the top and right of the screen. The Antrag
  /// gives each of its steps one; most sub-screens have none.
  final VHeaderSceneArt? art;

  /// Turns the back arrow into a close. For a screen that is a flow of its own rather than a page
  /// in a stack: an arrow promises "one step back", and on the Antrag it silently threw away every
  /// step at once. The caller decides what closing costs and whether to ask first.
  final VoidCallback? onClose;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final leading = onClose != null || (showBack && canPop);
    final header = (title != null || eyebrow != null || leading)
        ? Padding(
            padding: const EdgeInsets.fromLTRB(VSpace.l, VSpace.s, VSpace.l, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The arrow sits on its own line above the title rather than beside it. Beside it,
                // the title had to start clear of a 44 pt button and the screen gained a second
                // left edge for no reason anybody could see.
                if (leading)
                  Transform.translate(
                    offset: const Offset(-_glyphInset, 0),
                    child: VIconButton(
                      icon: onClose != null ? Icons.close : Icons.arrow_back,
                      onTap: onClose ?? () => Navigator.of(context).maybePop(),
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (eyebrow != null) VEyebrow(eyebrow!),
                          if (eyebrow != null) const SizedBox(height: 2),
                          if (title != null)
                            Text(title!, style: VText.h2, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
              ],
            ),
          )
        : null;

    final body = Padding(padding: padding, child: child);

    final content = SafeArea(
      bottom: bottom == null,
      child: Column(
        children: [
          if (header != null) header,
          Expanded(child: scroll ? SingleChildScrollView(child: body) : body),
          if (bottom != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(VSpace.l, VSpace.s, VSpace.l, VSpace.m),
                child: bottom!,
              ),
            ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: VColors.paper,
      // The drawing hangs from the top of the SCREEN, not from the header: it runs up behind the
      // status bar and down past the title into the first block, where its own gradients dissolve
      // it. Sizing it by the header instead made it as tall as whatever the title happened to be
      // and the art grew or shrank with the length of a word.
      body: art == null
          ? content
          : Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: VHeaderScene(art: art!),
                ),
                content,
              ],
            ),
    );
  }
}

class VIconButton extends StatelessWidget {
  const VIconButton({super.key, required this.icon, required this.onTap, this.color = VColors.ink});
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rules and spacing
// ---------------------------------------------------------------------------

/// A hairline.
///
/// The redesign retired the rule as a structural device: sections are separated by the page now,
/// not by a line across it. What survives lives *inside* a card, between the rows of one list —
/// that is [VDivider], and new code should use it. This stays while the screens migrate, drawn at
/// the new weight so an old call site does not look like a mistake.
class VRule extends StatelessWidget {
  const VRule({super.key})
      : color = VColors.hairlineStrong,
        thickness = VControl.hairline;
  @Deprecated(
    'The one thick red rule went with the hairline. A block that has to close now does it with a '
    'card edge or with VDivider(strong: true).',
  )
  const VRule.red({super.key})
      : color = VColors.red,
        thickness = 2;
  const VRule.soft({super.key})
      : color = VColors.hairline,
        thickness = VControl.hairline;

  final Color color;
  final double thickness;

  @override
  Widget build(BuildContext context) => Container(height: thickness, color: color);
}

class VGap extends StatelessWidget {
  const VGap(this.size, {super.key});
  const VGap.xs({super.key}) : size = VSpace.xs;
  const VGap.s({super.key}) : size = VSpace.s;

  /// The gap between two stacked surfaces, which is the rhythm of every page now.
  const VGap.md({super.key}) : size = VSpace.md;
  const VGap.m({super.key}) : size = VSpace.m;
  const VGap.l({super.key}) : size = VSpace.l;
  const VGap.xl({super.key}) : size = VSpace.xl;
  const VGap.xxl({super.key}) : size = VSpace.xxl;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(height: size, width: size);
}

// ---------------------------------------------------------------------------
// Die Fahrkarte
// ---------------------------------------------------------------------------

/// The one card shape this app has: a piece of paper whose top and bottom edge the perforator
/// bit into, a hairline down each side, nothing rounded and nothing floating. Same object as
/// the hero on verspaetomat.de (`site/static/verspaetomat.css`, `.fahrkarte`) and as the
/// shareable Fahrkarte in `widgets/ticket.dart`, down to the radius and the pitch.
///
/// It means something: a ticket is **one journey or one claim**, a thing that could be handed
/// to somebody. Numbers about a week, a settings group, a choice — those are still rules and
/// rows, never this shape (app/STYLE.md).
///
@Deprecated(
  'The perforated card left the app with the redesign. Use VCard, which is what this now draws. '
  'The silhouette itself survives in widgets/ticket.dart and on verspaetomat.de, where a shared '
  'object still means something. This alias exists only so the screens can migrate one at a time.',
)
class VFahrkarte extends StatelessWidget {
  const VFahrkarte({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(VSpace.card),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => VCard(padding: padding, child: child);
}

/// The silhouette itself: the rectangle minus a row of half circles along the top and the
/// bottom edge, plus the two side hairlines. Subtractive, not a row of painted dots — the
/// bites show whatever is behind the card, so the same border works on paper, on white and
/// over a sheet.
class VTicketBorder extends ShapeBorder {
  const VTicketBorder({this.side = const BorderSide(color: VColors.ruleSoft)});

  final BorderSide side;

  /// The website's numbers: a 5 px tooth every 14 px.
  static const radius = 5.0;
  static const pitch = 14.0;

  /// How deep the teeth reach into the card. Content keeps clear of it.
  static const bite = radius;

  @override
  EdgeInsetsGeometry get dimensions =>
      EdgeInsets.symmetric(horizontal: side.width, vertical: bite);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final teeth = Path();
    // Centred, so no tooth is cut in half by a corner: a chipped corner reads as a rendering
    // fault, a full tooth reads as perforation.
    final count = (rect.width / pitch).floor();
    if (count > 0) {
      final start = rect.left + (rect.width - count * pitch) / 2 + pitch / 2;
      for (var i = 0; i < count; i++) {
        final x = start + i * pitch;
        teeth.addOval(Rect.fromCircle(center: Offset(x, rect.top), radius: radius));
        teeth.addOval(Rect.fromCircle(center: Offset(x, rect.bottom), radius: radius));
      }
    }
    return Path.combine(PathOperation.difference, Path()..addRect(rect), teeth);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  /// Only the two cut sides are drawn. Top and bottom are torn edges; a line along a tear is
  /// what a border-everywhere box would do, and that is the look this replaces.
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    final paint = side.toPaint();
    final inset = side.width / 2;
    canvas.drawLine(Offset(rect.left + inset, rect.top), Offset(rect.left + inset, rect.bottom), paint);
    canvas.drawLine(Offset(rect.right - inset, rect.top), Offset(rect.right - inset, rect.bottom), paint);
  }

  @override
  ShapeBorder scale(double t) => VTicketBorder(side: side.scale(t));

  @override
  bool operator ==(Object other) => other is VTicketBorder && other.side == side;

  @override
  int get hashCode => side.hashCode;
}


// ---------------------------------------------------------------------------
// Die Tafel
// ---------------------------------------------------------------------------

/// The second of the app's two surfaces (app/STYLE.md): the board a figure stands on.
///
/// Elevated paper, a hairline all round, a 4 px radius — deliberately not the Fahrkarte, which
/// is one journey or one claim. A Tafel holds the numbers that belong together at one glance:
/// what we all waited, what your week came to, what you have collected. Same object on Home, on
/// Wir and on Ich, so the same kind of statement looks the same wherever it stands.
///
/// A surface never contains another surface. Nothing inside a Tafel gets its own border.
enum VTafelLook {
  /// Ink on paper, a hairline round it. The quiet one, for the figures under the fold.
  papier,

  /// The departure board: white flaps on black, a red rule under the row. One per screen, for
  /// the figure the screen is about (docs/34).
  anzeige,
}

class VTafel extends StatelessWidget {
  const VTafel({
    super.key,
    required this.child,
    this.look = VTafelLook.papier,
    this.onTap,
    this.padding = const EdgeInsets.all(VSpace.m),
  });

  final Widget child;
  final VTafelLook look;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// The board's own dark, from the tokens. A blue-black, never neutral.
  static const board = VColors.surfaceDark;

  /// Everything on the board that is not the figure: labels, units, captions.
  static const boardInk = VColors.inkOnDark2;

  @override
  Widget build(BuildContext context) {
    // The board became VBoard and the quiet paper one became an ordinary card. Both are drawn by
    // the new surfaces now; this stays so the screens can migrate one at a time.
    if (look == VTafelLook.anzeige) {
      return VBoard(padding: padding, onTap: onTap, child: child);
    }
    return VCard(padding: padding, onTap: onTap, child: child);
  }
}

/// The label over a figure: small caps, quiet, and legible on either look.
class VTafelLabel extends StatelessWidget {
  const VTafelLabel(this.text, {super.key, this.look = VTafelLook.papier});
  final String text;
  final VTafelLook look;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: VText.eyebrow.copyWith(color: look == VTafelLook.anzeige ? VColors.inkOnDark2 : VColors.ink2),
      );
}

/// A line under a figure: where the number comes from, what it is worth, what it was last week.
class VTafelCaption extends StatelessWidget {
  const VTafelCaption(this.text, {super.key, this.look = VTafelLook.papier, this.maxLines = 2});
  final String text;
  final VTafelLook look;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: VText.bodyS.copyWith(color: look == VTafelLook.anzeige ? VColors.inkOnDark3 : VColors.ink2),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
}

/// A figure on a Tafel, set the way a Fallblattanzeige sets one: every digit that changed flips
/// over to its new value, left to right, running through the digits in between the way the flaps
/// on a departure board do. Digits that did not change stand still — so a total ticking up by
/// one only moves its last flap, and a screen opening sets its whole row.
///
/// Tabular figures and a fixed cell height, so nothing shifts sideways or jumps while it runs.
/// This is the only animation in the app besides the station clock's second hand and the
/// arrival count-up (app/STYLE.md).
class VTafelZahl extends StatefulWidget {
  const VTafelZahl(this.text, {super.key, this.style, this.look = VTafelLook.papier, this.flaps = false});

  /// The number as it should read, German formatting and all: `1.208.316`, `+96`, `4,50 €`.
  /// Digits flip; a sign in front of them sits on a flap of its own and stands still, the way a
  /// board shows a character it never has to turn (issue #10). Group separators stay bare — they
  /// are punctuation between figures, and a board has no flap for them.
  final String text;
  final TextStyle? style;

  /// [flaps] draws each digit on a card with the hinge seam across it, the way a Solari board
  /// does. It is **off by default since the redesign**: the new boards set their figures as bare
  /// digits. The machinery is all still here and still correct, so switching a board back on is
  /// one word — see the note in app/STYLE.md about what that loss cost.
  final VTafelLook look;
  final bool flaps;

  @override
  State<VTafelZahl> createState() => _VTafelZahlState();
}

class _VTafelZahlState extends State<VTafelZahl> with SingleTickerProviderStateMixin {
  static const _flap = Duration(milliseconds: 110);
  static const _stagger = 45;

  /// `--dart-define=NO_ANIM=1`: the board stands still. The screenshot tour runs with it, because
  /// a still caught halfway through a flap looks like a rendering fault rather than a board, and
  /// a number that flaps every second made the capture drift a screen behind (docs/33).
  static const _still = String.fromEnvironment('NO_ANIM') == '1';

  /// At most this many flaps per digit: a board is quick, and 0 → 9 should not take a second.
  static const _maxFlaps = 6;

  /// A flap card is this much taller than the figure printed on it.
  static const _cardHeight = 1.18;

  /// What sits on a flap: the digits and the sign in front of them. The dots and commas that
  /// group a German number do not (issue #10).
  static final _bare = RegExp(r'[.,\s]');
  static bool _flapped(String c) => !_bare.hasMatch(c);

  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late String _from = _blank(widget.text);
  late String _to = widget.text;

  /// The row a board starts from: all flaps blank, so the first paint sets itself.
  static String _blank(String s) => s.replaceAll(RegExp(r'\d'), '0');

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void didUpdateWidget(VTafelZahl old) {
    super.didUpdateWidget(old);
    if (widget.text == _to) return;
    // Mid-flight the row shows whatever the animation has reached; starting the new run from the
    // old target is close enough and keeps the digits from jumping backwards.
    _from = _to;
    _to = widget.text;
    _c
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anzeige = widget.look == VTafelLook.anzeige;
    // White on a dark flap, in both boxes (issue #10) — but the group separators hang *between*
    // the flaps, on whatever the flaps hang in, so they take that colour instead.
    final onBoard = widget.look == VTafelLook.anzeige;
    final style = (widget.style ?? VText.number).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      // A figure on the board takes the board's ink whether or not it sits on a flap. Left to the
      // style it came out ink on ink the moment the flaps were switched off.
      color: widget.flaps
          ? VColors.paper
          : onBoard
              ? VColors.inkOnDark
              : null,
    );
    final bareStyle = style.copyWith(color: anzeige ? VColors.inkOnDark : VColors.ink);
    // Measured, not guessed: a flap has to be exactly as wide and as tall as the digit it turns
    // over, or the row shifts sideways while it runs. Tabular figures make one measurement do
    // for all ten.
    if (_still) {
      // No flapping, but the board keeps its flaps: the cells are the look, not the animation.
      if (!widget.flaps) return Text(_to, style: style);
      final probe = TextPainter(text: TextSpan(text: '0', style: style), textDirection: TextDirection.ltr)..layout();
      final cell = probe.height * _cardHeight;
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final c in _to.split(''))
            if (_flapped(c))
              _Card(
                height: cell,
                // Digits share one flap width; a sign keeps its own.
                width: RegExp(r'\d').hasMatch(c) ? probe.width : null,
                look: widget.look,
                child: SizedBox(height: cell, child: Center(child: Text(c, style: style))),
              )
            else
              Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: Text(c, style: bareStyle)),
        ],
      );
    }
    final probe = TextPainter(text: TextSpan(text: '0', style: style), textDirection: TextDirection.ltr)..layout();
    final cell = widget.flaps ? probe.height * _cardHeight : probe.height;
    final width = probe.width;
    // A shorter number than last time (never mind a longer one) must not read digits against the
    // wrong places: both rows are compared from the right, which is where a number grows.
    final to = _to;
    final from = _from.length == to.length ? _from : _blank(to);
    final digits = RegExp(r'\d');
    var index = 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < to.length; i++)
          if (!digits.hasMatch(to[i]))
            if (widget.flaps && _flapped(to[i]))
              _Card(
                height: cell,
                width: null,
                look: widget.look,
                child: SizedBox(height: cell, child: Center(child: Text(to[i], style: style))),
              )
            else
              Padding(padding: EdgeInsets.symmetric(horizontal: widget.flaps ? 1 : 0), child: Text(to[i], style: bareStyle))
          else
            _Flap(
              controller: _c,
              from: int.parse(from[i]),
              to: int.parse(to[i]),
              begin: (index++ * _stagger) / 900,
              span: _flap.inMilliseconds / 900,
              height: cell,
              width: width,
              style: style,
              anzeige: anzeige,
              flaps: widget.flaps,
            ),
      ],
    );
  }
}

/// One digit's column of flaps, clipped to a single cell and slid from the old digit to the new.
class _Flap extends StatelessWidget {
  const _Flap({
    required this.controller,
    required this.from,
    required this.to,
    required this.begin,
    required this.span,
    required this.height,
    required this.width,
    required this.style,
    required this.anzeige,
    required this.flaps,
  });

  final AnimationController controller;
  final int from;
  final int to;
  final double begin;
  final double span;
  final double height;
  final double width;
  final TextStyle style;
  final bool anzeige;
  final bool flaps;

  @override
  Widget build(BuildContext context) {
    // The flaps this digit turns over: from the old value up to the new one, the way the board
    // does it, capped so a long way round stays quick.
    final steps = <int>[];
    var d = from;
    while (d != to && steps.length < _VTafelZahlState._maxFlaps) {
      steps.add(d);
      d = (d + 1) % 10;
    }
    steps.add(to);
    if (steps.length == 1) return _card(_cell(to));

    final end = (begin + span * steps.length).clamp(0.0, 1.0);
    final t = CurvedAnimation(parent: controller, curve: Interval(begin.clamp(0.0, 1.0), end, curve: Curves.easeOut));
    return _card(
      ClipRect(
        child: SizedBox(
          height: height,
          width: width,
          child: AnimatedBuilder(
            animation: t,
            builder: (context, _) {
              final offset = -t.value * (steps.length - 1) * height;
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (var i = 0; i < steps.length; i++)
                    Positioned(top: i * height + offset, child: _cell(steps[i])),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _card(Widget child) => flaps
      ? _Card(height: height, width: width, look: anzeige ? VTafelLook.anzeige : VTafelLook.papier, child: child)
      : child;

  Widget _cell(int digit) => SizedBox(
        height: height,
        width: width,
        child: Center(child: Text('$digit', style: style)),
      );
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

/// The one thing on a card you are meant to press.
///
/// Red, and lit: it carries a red glow rather than a grey shadow, which is the device the whole
/// design uses to say *press this*. The old rule was one primary per screen; it is now one per
/// card, because a screen of collected claims has a real action on each desk.
class VPrimaryButton extends StatelessWidget {
  const VPrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.trailingIcon,
    this.expanded = true,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  /// A glyph pinned to the right edge while the label stays on the centre line: the arrow that
  /// says this button goes onward rather than does something here. [icon], by contrast, rides
  /// with the label and names the action — a paper plane on "Absenden".
  final IconData? trailingIcon;

  final bool expanded;

  /// While something is in flight. The label stays, so the button does not change width and the
  /// row around it does not move.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    final shape = BorderRadius.circular(VRadius.button);
    final fg = enabled ? VColors.paperElevated : VColors.disabledInk;

    final child = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: enabled ? VShadow.glowButton : const <BoxShadow>[],
      ),
      child: SizedBox(
        height: VControl.button,
        child: Material(
          color: enabled ? VColors.red : VColors.disabledFill,
          borderRadius: shape,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: shape,
            splashColor: VColors.redPressed,
            highlightColor: VColors.redPressed,
            child: Padding(
              // The trailing arrow needs room on the right that the label must not grow into,
              // so both ends are reserved when it is there and the label keeps the centre.
              padding: EdgeInsets.symmetric(horizontal: trailingIcon == null ? VSpace.l : VSpace.xxl),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (busy) ...[
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                        ),
                        const SizedBox(width: 10),
                      ] else if (icon != null) ...[
                        Icon(icon, size: 20, color: fg),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          label,
                          style: VText.button.copyWith(color: fg),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (trailingIcon != null)
                    Positioned(right: 0, child: Icon(trailingIcon, size: 20, color: fg)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: child) : child;
  }
}

/// The third tier of the button ladder: a label on the page, no fill, no border.
///
/// It is a block control and fills the width it is given — the quiet second action under a
/// [VPrimaryButton]. It does not *ask* for that width, though. It used to say
/// `width: double.infinity`, which means the same thing under a bounded parent and is a trap under
/// an unbounded one: in a Row's non-flex slot there is nothing finite to clamp against, so the
/// button reports an infinite width, every flex sibling is laid out at zero, and the label is
/// centred off the screen. The inner Row is [MainAxisSize.max] already, so a bounded parent still
/// gets a full-width button and an unbounded one now gets a button the width of its label.
///
/// Give it a bounded slot: a Column, or an Expanded inside a Row.
class VGhostButton extends StatelessWidget {
  const VGhostButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.trailingIcon,
    this.color = VColors.ink,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  /// A glyph after the label, inside the centred group rather than at the slot's edge — the
  /// chevron on "Was ist dieser Verein?", which is a link wearing a button's clothes.
  final IconData? trailingIcon;

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: 20, color: color), const SizedBox(width: 10)],
            // Not Flexible: this Row may be laid out unbounded (the button shrink-wraps when its
            // slot does), and a flex child under an unbounded main axis is an error.
            Text(label, style: VText.bodyStrong.copyWith(color: color)),
            if (trailingIcon != null) ...[const SizedBox(width: 6), Icon(trailingIcon, size: 18, color: color)],
          ],
        ),
      ),
    );
  }
}

/// An outlined secondary button for the rare two-button row.
class VOutlineButton extends StatelessWidget {
  const VOutlineButton({super.key, required this.label, this.onTap, this.icon});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: VColors.ink,
          side: const BorderSide(color: VColors.ink, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 10)],
            Flexible(child: Text(label, style: VText.button, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

/// A visibly "showcase only" control. Dashed outline, grey. Use it for
/// buttons that stand in for the real world (simulate arrival, etc.).
class VDemoControl extends StatelessWidget {
  const VDemoControl({super.key, required this.label, required this.onTap, this.icon = Icons.play_arrow_outlined});
  final String label;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const VDashedBorder(),
      child: SizedBox(
        height: 44,
        width: double.infinity,
        child: InkWell(
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: VColors.ink2),
              const SizedBox(width: 8),
              Text('Demo: $label', style: VText.caption),
            ],
          ),
        ),
      ),
    );
  }
}

/// The app's one dash walk.
///
/// Dashed ink means *not filled in yet*: the showcase control that stands in for the real world,
/// the dropzone waiting for a picture, the line between one step and the next. Three places, and
/// the walk is fiddly enough that a second copy would drift — so it is written once and takes
/// what differs. [VDashedBorder] draws the outline of a rounded rectangle; [VDashedLine] draws a
/// bare vertical.
class VDashedBorder extends CustomPainter {
  const VDashedBorder({
    this.color = VColors.ink3,
    this.radius = 4,
    this.dash = 5,
    this.gap = 4,
    this.width = 1,
  });

  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    _walk(canvas, Path()..addRRect(rrect), paint, dash, gap);
  }

  @override
  bool shouldRepaint(covariant VDashedBorder old) =>
      old.color != color || old.radius != radius || old.dash != dash || old.gap != gap || old.width != width;
}

/// A dashed vertical, top to bottom of its box. The connector between two steps.
class VDashedLine extends CustomPainter {
  const VDashedLine({this.color = VColors.hairlineStrong, this.dash = 4, this.gap = 4, this.width = 1.5});

  final Color color;
  final double dash;
  final double gap;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width / 2, size.height);
    _walk(canvas, path, paint, dash, gap);
  }

  @override
  bool shouldRepaint(covariant VDashedLine old) =>
      old.color != color || old.dash != dash || old.gap != gap || old.width != width;
}

void _walk(Canvas canvas, Path path, Paint paint, double dash, double gap) {
  for (final metric in path.computeMetrics()) {
    var d = 0.0;
    while (d < metric.length) {
      canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
      d += dash + gap;
    }
  }
}

// ---------------------------------------------------------------------------
// Numbers, chips, rows
// ---------------------------------------------------------------------------

/// The delay figure: a red "+" and the minutes. `size` picks the scale.
///
/// On time is a **green nought**, not the word „pünktlich". A word in a slot built for `+204`
/// is a different width class, and at figure sizes that breaks the layout around it rather than
/// itself: on Home the word took the whole row and left its neighbour one letter per line
/// („Aulendo / rf"). A nought is the same width as any other minute count, so a card keeps its
/// shape whether the train was late or not — and the number stays the design.
///
/// „Ausfall" has no figure to show, so it stays a word and drops to the label size for its slot.
/// The screens that show a delay inside a list do it the other way round and say „pünktlich" in
/// caption size next to a `VChip('Ausfall')`; that is prose, and prose may use words.
class VDelay extends StatelessWidget {
  const VDelay(this.minutes, {super.key, this.size = VDelaySize.medium, this.cancelled = false, this.punctualZero = true});
  final int minutes;
  final VDelaySize size;
  final bool cancelled;

  /// Off while a figure counts up to a real delay: zero is then a frame on the way, not a verdict,
  /// and a green flash at the start of the animation would say the opposite of what follows.
  final bool punctualZero;

  @override
  Widget build(BuildContext context) {
    if (cancelled) {
      return Text('Ausfall', style: _wordStyle().copyWith(color: VColors.red), maxLines: 1, softWrap: false);
    }
    if (minutes <= 0) {
      return Text('0', style: _style().copyWith(color: punctualZero ? VColors.green : VColors.ink));
    }
    final s = _style();
    return RichText(
      text: TextSpan(
        style: s,
        children: [
          TextSpan(text: '+', style: s.copyWith(color: VColors.red)),
          TextSpan(text: '$minutes'),
        ],
      ),
    );
  }

  TextStyle _style() => switch (size) {
        VDelaySize.display => VText.display,
        VDelaySize.large => VText.number,
        VDelaySize.medium => VText.numberM,
        VDelaySize.small => VText.mono.copyWith(fontWeight: FontWeight.w700),
      };

  /// A word in the figure's slot: big enough to lead, small enough to leave room beside it.
  TextStyle _wordStyle() => switch (size) {
        VDelaySize.display => VText.h1,
        VDelaySize.large => VText.h2,
        VDelaySize.medium => VText.bodyStrong,
        VDelaySize.small => VText.mono.copyWith(fontWeight: FontWeight.w700),
      };
}

enum VDelaySize { display, large, medium, small }

/// A small status chip. Ink outline by default; [tone] colours it.
class VChip extends StatelessWidget {
  const VChip(this.label, {super.key, this.tone = VTone.neutral});
  final String label;
  final VTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      VTone.neutral => (VColors.greyPill, VColors.ink2),
      VTone.ink => (VColors.ink, VColors.paperElevated),
      VTone.red => (VColors.redTint, VColors.red),
      VTone.green => (VColors.greenTint, VColors.green),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(VRadius.sm)),
      child: Text(label, style: VText.pill.copyWith(color: fg)),
    );
  }
}

enum VTone { neutral, ink, red, green }

/// Label on the left, value on the right, on one baseline.
class VKeyValue extends StatelessWidget {
  const VKeyValue(this.label, this.value, {super.key, this.strong = false, this.valueStyle, this.trailing});
  final String label;
  final String value;
  final bool strong;
  final TextStyle? valueStyle;

  /// A control after the value: the copy button on an IBAN. It breaks the baseline alignment the
  /// rest of the row keeps, so it is centred against the line instead.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final line = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Text(label, style: VText.bodyS.copyWith(color: VColors.ink2))),
        Text(value, style: valueStyle ?? (strong ? VText.bodySStrong : VText.bodyS).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    );
    if (trailing == null) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: line);
    }
    // The control carries its own 44 pt box, so the row no longer needs its own vertical air.
    return Row(
      children: [
        Expanded(child: line),
        const SizedBox(width: VSpace.xs),
        trailing!,
      ],
    );
  }
}

/// Section heading: an eyebrow with a hairline under it.
class VSection extends StatelessWidget {
  const VSection(this.label, {super.key, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label.toUpperCase(), style: VText.eyebrowWide)),
            if (trailing != null) trailing!,
          ],
        ),
      ],
    );
  }
}

/// A tappable list row with optional leading/trailing, hairline below.
class VListRow extends StatelessWidget {
  const VListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.divider = true,
  });
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;

  /// Off for the last row of a list: a line under the last row is a line under nothing, and it is
  /// what makes a list look like a form.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 14)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: VText.bodyStrong),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: VText.caption),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 12), trailing!],
                if (chevron) ...[const SizedBox(width: 8), const VChevron()],
              ],
            ),
          ),
          if (divider) const VDivider(),
        ],
      ),
    );
  }
}

/// Red dots for "3 von 3". Filled = counted, outline = missing.
class VDots extends StatelessWidget {
  const VDots({super.key, required this.filled, required this.total});
  final int filled;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? VColors.red : Colors.transparent,
                border: Border.all(color: i < filled ? VColors.red : VColors.track, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

/// A thin progress bar: confirmed solid red, submitted as a lighter segment.
class VProgress extends StatelessWidget {
  const VProgress({super.key, required this.confirmed, this.submitted = 0, this.track});
  final double confirmed; // 0..1
  final double submitted; // 0..1, drawn behind confirmed

  /// The empty part. Darker than the paper default when the bar stands on a board (docs/34).
  final Color? track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(VRadius.full),
      child: SizedBox(
        height: VControl.progress,
        child: Stack(
          children: [
            Container(color: track ?? VColors.track),
            FractionallySizedBox(widthFactor: (confirmed + submitted).clamp(0, 1), child: Container(color: VColors.redTint)),
            FractionallySizedBox(widthFactor: confirmed.clamp(0, 1), child: Container(color: VColors.red)),
          ],
        ),
      ),
    );
  }
}

/// The round tick of a choice: one of these is on. Its own widget, so a card that puts
/// something else beside it does not have to draw a second one from scratch.
class VSelectedMark extends StatelessWidget {
  const VSelectedMark({super.key, required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? VColors.red : Colors.transparent,
        border: Border.all(color: selected ? VColors.red : VColors.rule, width: 1.5),
      ),
      child: selected ? const Icon(Icons.check, size: 14, color: VColors.paperElevated) : null,
    );
  }
}

/// A square tick in ink. For a list where several things can be on at once — a round tick
/// would promise that only one may be.
class VCheckbox extends StatelessWidget {
  const VCheckbox({super.key, required this.checked, required this.onTap, this.label, this.color = VColors.ink});
  final bool checked;
  final VoidCallback? onTap;

  /// For screen readers: what this tick decides.
  final String? label;

  /// What a ticked box fills with. Ink by default, because a multi-select tick is a statement of
  /// fact and not an action. Red is for the rare list where the ticks decide money: the cases
  /// going into an Antrag are exactly that, and the sum above them moves as they are touched.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: checked,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: checked ? color : Colors.transparent,
              border: Border.all(color: checked ? color : VColors.rule, width: 1.5),
              borderRadius: BorderRadius.circular(3),
            ),
            child: checked ? const Icon(Icons.check, size: 15, color: VColors.paper) : null,
          ),
        ),
      ),
    );
  }
}

/// A big selectable card for the setup screens (ticket type, NGO).
class VChoiceCard extends StatelessWidget {
  const VChoiceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.all(VSpace.m),
        decoration: BoxDecoration(
          color: selected ? VColors.paperElevated : Colors.transparent,
          border: Border.all(color: selected ? VColors.ink : VColors.rule, width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: VText.title),
                  const SizedBox(height: 4),
                  Text(subtitle, style: VText.caption),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing ?? VSelectedMark(selected: selected),
          ],
        ),
      ),
    );
  }
}

/// Bottom navigation in the paper style: a hairline on top, four tabs and the
/// raised "Einchecken" square in the middle (decided 10 September 2026). The
/// square is not a tab: it opens the check-in directly.
class VBottomNav extends StatelessWidget {
  const VBottomNav({super.key, required this.index, required this.onTap, required this.onCheckin, this.badges = const {}, this.checkinEnabled = true});
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onCheckin;

  /// False while a journey is under way (docs/20 §1): the square is drawn disabled and
  /// [onCheckin] then opens the ride instead of a new check-in.
  final bool checkinEnabled;

  /// Small red count on a tab's icon, by tab index (Anträge shows unread railway mail).
  final Map<int, int> badges;

  /// The four tabs, in order. Index 1 (Anträge) keeps the receipt icon the E2E taps.
  static const items = [
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'Anträge'),
    (Icons.groups_outlined, Icons.groups, 'Wir'),
    (Icons.person_outline, Icons.person, 'Ich'),
  ];

  @override
  Widget build(BuildContext context) {
    Widget tab(int i) {
      final selected = i == index;
      final count = badges[i] ?? 0;
      return Expanded(
        child: InkWell(
          onTap: () => onTap(i),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    selected ? items[i].$2 : items[i].$1,
                    size: 24,
                    color: selected ? VColors.red : VColors.tabInactive,
                  ),
                  if (count > 0) Positioned(top: -6, right: -10, child: VNavBadge(count)),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                items[i].$3,
                style: VText.tab.copyWith(color: selected ? VColors.red : VColors.tabInactive),
              ),
            ],
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        // The bar is a card the tabs stand on, so it takes a card's corner. Only the top two are
        // seen; the other two are under the home indicator and past the screen edges.
        borderRadius: BorderRadius.vertical(top: VRadius.lgR),
        gradient: VGradients.tabBar,
        // Uniform, because a border on one side and a radius cannot both be set. At half a point
        // the three edges nobody sees cost nothing.
        border: Border.fromBorderSide(
          BorderSide(color: VColors.tabBarBorder, width: VControl.hairline),
        ),
        boxShadow: VShadow.tabBar,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: VControl.tabBar,
          child: Row(
            children: [
              tab(0),
              tab(1),
              Expanded(
                child: VCheckinFab(onTap: onCheckin, enabled: checkinEnabled),
              ),
              tab(2),
              tab(3),
            ],
          ),
        ),
      ),
    );
  }
}

/// The raised check-in circle. It is not a tab: it opens the check-in wherever you are, and it
/// keeps its ink label on every screen because it is never the place you currently stand.
class VCheckinFab extends StatelessWidget {
  const VCheckinFab({super.key, required this.onTap, this.enabled = true, this.label = 'Einchecken'});

  final VoidCallback onTap;
  final bool enabled;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.translate(
            offset: const Offset(0, -VControl.fabRise),
            child: Container(
              width: VControl.fab,
              height: VControl.fab,
              key: const Key('nav-checkin'),
              decoration: BoxDecoration(
                gradient: enabled ? VGradients.fab : null,
                color: enabled ? null : VColors.disabledFill,
                shape: BoxShape.circle,
                boxShadow: enabled ? VShadow.glowFab : const <BoxShadow>[],
              ),
              child: Icon(
                Icons.train,
                size: 24,
                color: enabled ? VColors.paperElevated : VColors.disabledInk,
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -VControl.fabRise + 1),
            child: Text(
              label,
              style: VText.tab.copyWith(
                color: enabled ? VColors.tabCenterLabel : VColors.disabledInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The unread count on a tab. Lit red, not the action red: it is a notice, not a button.
class VNavBadge extends StatelessWidget {
  const VNavBadge(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 17),
        height: 17,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: VColors.redBright,
          borderRadius: BorderRadius.circular(VRadius.full),
          border: Border.all(color: VColors.paperElevated, width: 1.5),
        ),
        child: Text(
          count > 9 ? '9+' : '$count',
          style: VText.tab.copyWith(color: VColors.paperElevated, fontSize: 10, height: 1),
        ),
      );
}

// ---------------------------------------------------------------------------
// The station clock
// ---------------------------------------------------------------------------

/// The German station clock. The red second hand sweeps to twelve, waits,
/// and only then does the minute hand jump. [animated] runs that cycle
/// (compressed to ~12 s so it reads in a demo); otherwise it is still.
class VStationClock extends StatefulWidget {
  const VStationClock({super.key, this.size = 44, this.animated = false, this.time});
  final double size;
  final bool animated;

  /// Optional fixed time to show (hour, minute). Defaults to 10:08 which
  /// reads well and is the classic "clock face" pose.
  final TimeOfDay? time;

  @override
  State<VStationClock> createState() => _VStationClockState();
}

class _VStationClockState extends State<VStationClock> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12));

  @override
  void initState() {
    super.initState();
    if (widget.animated) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant VStationClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated && !_c.isAnimating) _c.repeat();
    if (!widget.animated && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.time ?? const TimeOfDay(hour: 10, minute: 8);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Sweep for 88% of the cycle, then hold at twelve.
        final v = _c.value;
        final sweep = (v / 0.88).clamp(0.0, 1.0);
        final minuteJump = v >= 0.985 ? 1 : 0;
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _ClockPainter(
            hour: t.hour,
            minute: t.minute + minuteJump,
            secondFraction: widget.animated ? sweep : 0,
          ),
        );
      },
    );
  }
}

class _ClockPainter extends CustomPainter {
  _ClockPainter({required this.hour, required this.minute, required this.secondFraction});
  final int hour;
  final int minute;
  final double secondFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ring = Paint()
      ..color = VColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.09;
    canvas.drawCircle(c, r - ring.strokeWidth / 2, Paint()..color = VColors.paperElevated);
    canvas.drawCircle(c, r - ring.strokeWidth / 2, ring);

    final mark = Paint()..color = VColors.ink;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final big = i % 3 == 0;
      final len = big ? r * 0.22 : r * 0.14;
      final w = big ? r * 0.09 : r * 0.06;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(a);
      canvas.drawRect(Rect.fromLTWH(-w / 2, -r + ring.strokeWidth * 1.4, w, len), mark);
      canvas.restore();
    }

    void hand(double angle, double length, double width, Color color) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(angle);
      canvas.drawRect(Rect.fromLTWH(-width / 2, -length, width, length + width * 1.2), Paint()..color = color);
      canvas.restore();
    }

    final hourAngle = ((hour % 12) + minute / 60) * math.pi / 6;
    final minuteAngle = minute * math.pi / 30;
    hand(hourAngle, r * 0.52, r * 0.12, VColors.ink);
    hand(minuteAngle, r * 0.76, r * 0.09, VColors.ink);

    // Red second hand with the disc at its tip.
    final sa = secondFraction * 2 * math.pi;
    hand(sa, r * 0.68, r * 0.045, VColors.red);
    final tip = c + Offset(math.sin(sa), -math.cos(sa)) * (r * 0.68);
    canvas.drawCircle(tip, r * 0.1, Paint()..color = VColors.red);
    canvas.drawCircle(c, r * 0.07, Paint()..color = VColors.red);
  }

  @override
  bool shouldRepaint(covariant _ClockPainter old) =>
      old.hour != hour || old.minute != minute || old.secondFraction != secondFraction;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// German number formatting without intl: 1208311 -> "1.208.311".
String fmtInt(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final fromEnd = s.length - i;
    b.write(s[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) b.write('.');
  }
  return (n < 0 ? '-' : '') + b.toString();
}

/// 4.5 -> "4,50 €"
String fmtEuro(double v) {
  final cents = (v * 100).round();
  final whole = cents ~/ 100;
  final frac = (cents % 100).toString().padLeft(2, '0');
  return '${fmtInt(whole)},$frac €';
}

/// 48320.0 -> "48.320 €" (community figures)
String fmtEuroWhole(double v) => '${fmtInt(v.round())} €';

/// TimeOfDay -> "08:52"
String fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay addMinutes(TimeOfDay t, int minutes) {
  final total = (t.hour * 60 + t.minute + minutes) % (24 * 60);
  return TimeOfDay(hour: total ~/ 60, minute: total % 60);
}

/// Show a standard bottom sheet in the paper style.
Future<T?> showVSheet<T>(BuildContext context, {required WidgetBuilder builder, bool expand = false, bool dismissible = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Off only for a sheet that must be answered: one that shows something once and never again.
    isDismissible: dismissible,
    enableDrag: dismissible,
    builder: (ctx) => expand
        ? FractionallySizedBox(heightFactor: 0.92, child: builder(ctx))
        // Not expanded: as tall as its content, but never taller than the screen. A sheet that
        // grew an action (docs/23 §2) used to overflow instead of scrolling.
        : ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.92),
            child: SingleChildScrollView(
              // Clamping, not the iOS default: a bouncing list swallows the pull at the top as
              // an overscroll of its own, so a sheet taller than the screen could only ever be
              // closed from the few pixels of header above the list. Refusing the overscroll
              // hands the drag back to the sheet, and the whole thing pulls down again.
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: builder(ctx),
            ),
          ),
  );
}

/// The little grabber + optional title at the top of a sheet.
class VSheetHeader extends StatelessWidget {
  const VSheetHeader({
    super.key,
    this.eyebrow,
    this.title,
    this.subtitle,
    this.trailing,
    this.narrow = false,
    this.dismissible = true,
  });

  /// False for a sheet that must be answered. The header is otherwise a handle — a drag or a tap on
  /// the grabber closes the sheet — which would quietly undo `showVSheet(dismissible: false)`.
  final bool dismissible;

  /// The small-caps line over the title: "Check-in · Schritt 1 von 3".
  final String? eyebrow;

  final String? title;
  final String? subtitle;
  final Widget? trailing;

  /// Keeps the text column to the left of the sheet. With a drawing behind it the right third
  /// belongs to the picture, and a subtitle running the full width sets straight across a train.
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    if (!dismissible) return _body(context);
    // The header is the handle: a drag anywhere on it closes the sheet, and so does a tap on
    // the grabber. Before this the only way out of a long sheet was a few pixels of dead space.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 120) Navigator.of(context).maybePop();
      },
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(VSpace.sheet, 10, VSpace.sheet, VSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // No grabber on a sheet that cannot be pulled away: a handle that does nothing is a lie.
          if (!dismissible) const SizedBox(height: 24),
          if (dismissible)
            Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              // A 36×4 bar is the smallest thing on screen; the target around it is not.
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 40),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: VColors.handle,
                    borderRadius: BorderRadius.circular(VRadius.full),
                  ),
                ),
              ),
            ),
          ),
          if (title != null) ...[
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: narrow ? 66 : 100,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eyebrow != null) ...[
                        VEyebrow(eyebrow!),
                        const SizedBox(height: 3),
                      ],
                      Text(title!, style: VText.h2, maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (subtitle != null) ...[const SizedBox(height: 3), Text(subtitle!, style: VText.body)],
                    ],
                  ),
                ),
                if (narrow) const Spacer(flex: 34),
                if (trailing != null) trailing!,
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One flap on the board: a card a shade darker than the board it hangs in, with the hinge seam
/// across the middle — the line you see on every Solari board, drawn over the figure because
/// that is where it sits in the real thing.
class _Card extends StatelessWidget {
  const _Card({required this.height, required this.width, required this.look, required this.child});
  final double height;

  /// Null for a flap that takes the width of what is printed on it: every digit is the same
  /// width, a `+` is not.
  final double? width;
  final VTafelLook look;
  final Widget child;

  /// A flap is dark with white figures on it, in both boxes (issue #10). That is the flap of a
  /// real board; what changes is what it hangs in — the black board, or a white card with a
  /// little board on it.
  static const _flap = Color(0xFF1D1D1D);
  static const _seam = Color(0xFF000000);

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        height: height,
        width: width,
        color: _flap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            child,
            Positioned(top: height / 2 - 0.5, left: 0, right: 0, child: Container(height: 1, color: _seam)),
          ],
        ),
      );
}
