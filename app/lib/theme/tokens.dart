import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colours of the app.
///
/// The palette is cool. Every neutral in it has more blue than red, which is the single biggest
/// break with the paper white that came before — `#F3F3F0` was warm on purpose and `#F7F7F8` is
/// not a nudge of it, it is the other temperature. Nothing here is black: the darkest ink and the
/// hero board are both blue-blacks, and every neutral shadow is made of a slate navy.
///
/// There are two reds. [red] is the deep one and it means *do this* or *this is money*: the
/// primary button, the check-in circle, an amount, a link. [redBright] is the lit one and it means
/// *this one*: today's bar in the week chart, the unread badge, the app mark. They are forty
/// levels of green apart and one token cannot carry both.
///
/// The other hues — [teal], [blue], [blueDeep], [greenBright] — belong to third parties. They
/// identify an operator or a partner NGO and they never carry an app state. Colour is for
/// identity; red and green are for meaning.
class VColors {
  VColors._();

  // --- Ground and surfaces ---------------------------------------------------------------

  /// The page. Cards are lifted off it, never drawn on it.
  static const paper = Color(0xFFF7F7F8);

  /// A card, a sheet, the tab bar. The default surface now, not the rare second one.
  static const paperElevated = Color(0xFFFFFFFF);

  /// A card that sits *below* the page rather than above it. Two levels off [paper], so it only
  /// reads at all with a hairline; use it sparingly and never for anything that must be noticed.
  static const surfaceMuted = Color(0xFFF9F9FA);

  /// The dark hero board. A blue-black in the same family as [ink], never neutral.
  static const surfaceDark = Color(0xFF191B26);

  /// One step off the board: the dark tag on a timeline.
  static const surfaceDarkAlt = Color(0xFF1C2230);

  // --- Ink -------------------------------------------------------------------------------

  static const ink = Color(0xFF0F1522);
  static const ink2 = Color(0xFF6E727C);
  static const ink3 = Color(0xFF8A8E98);

  static const inkOnDark = Color(0xFFFFFFFF);
  static const inkOnDark2 = Color(0xD9FFFFFF);
  static const inkOnDark3 = Color(0xA3FFFFFF);

  /// Text on a red tint. Red itself on [redTintSoft] fails contrast, so a tinted note darkens its
  /// ink instead of shouting.
  static const redInk = Color(0xFF6E1214);

  // --- The two reds ----------------------------------------------------------------------

  static const red = Color(0xFFD61316);
  static const redPressed = Color(0xFFB30F12);
  static const redBright = Color(0xFFFE171A);

  /// Pills and icon circles.
  static const redTint = Color(0xFFFEE3E3);

  /// The fill of a tinted button.
  static const redTintStrong = Color(0xFFFCE1E2);

  /// A tinted block or note banner inside a card.
  static const redTintSoft = Color(0xFFFBF0F1);

  /// The lightest tinted panel.
  static const redTintFaint = Color(0xFFFDF3F3);

  /// Was the unfilled bars of the week chart, until issue #33 made those [track]: a quiet week
  /// in a red tint read as a faint achievement. Kept because it is the right pink for anything
  /// that has to sit on [redTintFaint] without glowing the way a straight opacity step would.
  static const redTintMuted = Color(0xFFF6E4E4);

  /// Kept so the old name still resolves while the screens migrate. Prefer [redTint].
  static const redSoft = redTint;

  // --- Green, and the identity hues -------------------------------------------------------

  /// On time, and ready to file.
  static const green = Color(0xFF057D2E);
  static const greenTint = Color(0xFFE1F6E8);
  static const greenSoft = greenTint;

  static const teal = Color(0xFF039189);
  static const tealTint = Color(0xFFCCF1ED);
  static const blueDeep = Color(0xFF054085);
  static const blueDeepTint = Color(0xFFD1E2FD);
  static const blue = Color(0xFF006EF0);
  static const blueTint = Color(0xFFE8F1FD);
  static const greenBright = Color(0xFF07A126);
  static const greenBrightTint = Color(0xFFDEF8E2);

  // --- The podium -------------------------------------------------------------------------

  /// Gold, silver and bronze: the fourth identity family (#24). A place on a board is who you are
  /// on that list, the way [teal] is who an operator is — identity, not decoration, which is the
  /// line `STYLE.md` draws. They were kept out of the palette until Johannes asked for them.
  ///
  /// Fills only, and deliberately no matching ink: the metal goes on the disc under the numeral
  /// and never on type. The numeral on all three is [ink] — 13.5:1 at worst. They sit in the same
  /// lightness band as [tealTint] and [blueDeepTint], so a podium here is three quiet discs and
  /// not three medals.
  static const podiumGold = Color(0xFFF3E4B5);
  static const podiumSilver = Color(0xFFE2E6EE);
  static const podiumBronze = Color(0xFFEFDAC3);

  // --- Neutral fills ----------------------------------------------------------------------

  /// A neutral filled control: a quiet button, a round icon button, a speech bubble.
  static const greyFill = Color(0xFFF3F4F6);

  /// A neutral tag pill.
  static const greyPill = Color(0xFFEBEDF0);

  /// A neutral icon circle.
  static const greyCircle = Color(0xFFEFF0F2);

  // --- Lines ------------------------------------------------------------------------------

  /// The only divider left, and it lives *inside* a card, between the rows of one list. Never on
  /// the page, and never after the last row.
  static const hairline = Color(0xFFEDEFF3);

  /// The one heavier rule, for closing a block.
  static const hairlineStrong = Color(0xFFE2E3E8);

  /// The tab bar's top edge, over its upward shadow.
  static const tabBarBorder = Color(0xFFF3F3F5);

  /// Old names, kept resolving while the screens migrate.
  static const rule = hairlineStrong;
  static const ruleSoft = hairline;

  // --- Progress ---------------------------------------------------------------------------

  static const track = Color(0xFFE5E5E7);
  static const trackOnDark = Color(0xFF3D3E48);
  static const trackOnRed = Color(0x26FFFFFF);
  static const progressOnDark = Color(0xFFE12D2A);
  static const progressOnRed = Color(0xFFFC1418);

  // --- States and chrome ------------------------------------------------------------------

  /// Every neutral shadow is made of this, never of black. A black shadow on a cool page reads
  /// as dirt; a slate navy reads as depth.
  static const shadowTint = Color(0xFF15305A);

  static const scrim = Color(0x38000000);
  static const handle = Color(0xFFB6B9BD);

  static const disabledFill = Color(0xFFEDEEF1);
  static const disabledInk = Color(0xFFA7ABB5);
  static const pressedOverlay = Color(0x0F0F1522);

  static const tabInactive = Color(0xFF6E7076);

  /// The label under the check-in circle is neither the active tab nor an inactive one, because
  /// the circle is not a tab. It stays ink wherever you are.
  static const tabCenterLabel = Color(0xFF12141E);
}

/// The gradients, which there are exactly four of.
class VGradients {
  VGradients._();

  /// The dark hero board.
  static const board = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF20222F), Color(0xFF141620)],
  );

  /// Wir's board: the same object in red, so the pair reads as two looks of one thing.
  static const boardRed = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0xFFC0292D), Color(0xFF7C1719), Color(0xFF620E11)],
    stops: [0, 0.55, 1],
  );

  /// The bar the tabs stand on. Barely a gradient at all: a hair of light along the top edge, so
  /// the bar reads as a surface catching the room rather than as a flat sheet of paper. The design
  /// mockups draw it flat — this is a deliberate half-step past them.
  static const tabBar = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFF9FAFC)],
  );

  /// The raised check-in circle, lit from the top.
  static const fab = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF11B1E), Color(0xFFCE1114)],
  );
}

/// Spacing.
///
/// The names and their values are load-bearing: `VGap` alone has several hundred call sites, so
/// renumbering the scale would move every one of them silently. Exactly one value changed
/// ([page], 24 → 16) and exactly one was added ([md]).
class VSpace {
  VSpace._();
  static const xs = 4.0;
  static const s = 8.0;

  /// The gap between two stacked surfaces. New.
  static const md = 12.0;

  static const m = 16.0;
  static const l = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  /// The page gutter. Was 24; the cards want the width.
  static const page = 16.0;

  /// A card's inner padding, all four sides.
  static const card = 16.0;

  /// The inner padding of a card that is a list of rows.
  static const cardTight = 12.0;

  /// The ride sheet keeps a wider gutter than a page does.
  static const sheet = 24.0;
}

/// Corner radii. There was no radius token before this and eighteen files carried literals.
class VRadius {
  VRadius._();

  /// A dark line badge, a flat-sided tag, the app mark.
  static const sm = 6.0;

  /// A tinted panel, a note box, a sheet's top corners, a list-row card.
  static const md = 10.0;

  /// A content card and a hero board.
  static const lg = 14.0;

  /// Buttons.
  static const button = 12.0;

  /// The top of a week-chart bar. Deliberately not a capsule.
  static const bar = 2.0;

  /// Stadium: pills, progress bars, the grabber, every circle.
  static const full = 999.0;

  static const smR = Radius.circular(sm);
  static const mdR = Radius.circular(md);
  static const lgR = Radius.circular(lg);
}

/// Elevation.
///
/// Two families. Neutral shadows are slate navy and say *this is a surface above the page*. Red
/// glows say *press this* — they spill light downward out of the thing itself, and they are the
/// signature move of the whole design. Nothing else in the app may invent one.
class VShadow {
  VShadow._();

  /// An ordinary card on a page.
  static const card = [
    BoxShadow(color: Color(0x0F15305A), blurRadius: 6, offset: Offset(0, 2)),
  ];

  /// A card that floats above another surface.
  static const cardRaised = [
    BoxShadow(color: Color(0x1A15305A), blurRadius: 12, offset: Offset(0, 3)),
  ];

  /// The card that holds the screen's primary action takes a red-tinted shadow rather than the
  /// neutral one, so the call to action is lit before you read it.
  static const cardCta = [
    BoxShadow(color: Color(0x14D61316), blurRadius: 10, offset: Offset(0, 3)),
  ];

  /// Under a hero board. The negative spread is not a flourish: the glow is inset well inside the
  /// card's own width, and a plain Gaussian cannot do that.
  static const glowHero = [
    BoxShadow(color: Color(0x47D61316), blurRadius: 26, offset: Offset(0, 10), spreadRadius: -14),
  ];

  /// Under a primary or tinted button.
  static const glowButton = [
    BoxShadow(color: Color(0x40D61316), blurRadius: 22, offset: Offset(0, 8), spreadRadius: -6),
  ];

  /// The halo around the raised check-in circle.
  static const glowFab = [
    BoxShadow(color: Color(0x2ED61316), blurRadius: 16, offset: Offset(0, 4), spreadRadius: -2),
  ];

  /// The tab bar's lift off the content scrolling under it.
  static const tabBar = [
    BoxShadow(color: Color(0x0F15305A), blurRadius: 10, offset: Offset(0, -2)),
  ];

  /// The bottom sheet has none: its scrim is what separates it.
  static const sheet = <BoxShadow>[];
}

/// Control sizes, so a hit target is never a literal in a screen.
class VControl {
  VControl._();

  static const button = 44.0;
  static const buttonSmall = 38.0;

  /// The minimum touch area, whatever the control looks like. Two controls in the design mockups
  /// are drawn smaller than this; they are built at 44 anyway.
  static const touch = 44.0;

  static const badge = 50.0;
  static const badgeSmall = 40.0;
  static const badgeIcon = 22.0;

  static const chevron = 20.0;
  static const chevronSmall = 16.0;
  static const circleButton = 34.0;

  static const pill = 20.0;
  static const pillTall = 22.0;

  static const progress = 8.0;
  static const hairline = 0.5;

  static const tabBar = 64.0;
  static const fab = 44.0;

  /// How far the check-in circle rises above the bar's top edge.
  static const fabRise = 5.0;

  static const weekBar = 8.0;
  static const weekBarGap = 9.0;
  static const weekBarMax = 42.0;

  /// The illustrated band behind a tab header.
  static const sceneHeight = 200.0;
}

const _tabular = [FontFeature.tabularFigures()];

/// Type.
///
/// Archivo throughout the interface, and Caveat for the four handwritten margin notes that are
/// the one place the app speaks in its own hand.
///
/// A note on the sizes: the design mockups are not set in Archivo — their `i` carries a round
/// tittle where Archivo's is a hard square. Archivo was kept anyway, because it already has the
/// footed `1` that makes a big tabular figure read like a departure board, its x-height is the
/// closest of any candidate to what the mockups measure, and it reaches w800 where the nearest
/// alternative stops at w700. What that costs is the tittle. The sizes below are the measured
/// mockup sizes corrected for Archivo's own cap-height ratio of 0.686, which is why several of
/// them are a point larger than a ruler held against the mockup would say.
class VText {
  VText._();

  static TextStyle _a({
    required double size,
    FontWeight weight = FontWeight.w400,
    double height = 1.3,
    double letterSpacing = 0,
    Color color = VColors.ink,
    bool tabular = false,
  }) =>
      GoogleFonts.archivo(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
        fontFeatures: tabular ? _tabular : null,
      );

  // --- Figures ---------------------------------------------------------------------------

  /// The one figure a screen is built around.
  static TextStyle get display =>
      _a(size: 96, weight: FontWeight.w800, height: 1.0, letterSpacing: -3, tabular: true);

  /// A hero board's figure.
  static TextStyle get number =>
      _a(size: 52, weight: FontWeight.w800, height: 1.0, letterSpacing: -1.2, tabular: true);

  /// A figure inside a panel.
  static TextStyle get numberM =>
      _a(size: 33, weight: FontWeight.w800, height: 1.0, letterSpacing: -0.5, tabular: true);

  /// A euro total at the end of a list row.
  static TextStyle get numberS =>
      _a(size: 20, weight: FontWeight.w800, height: 1.0, tabular: true);

  /// An amount inside a claim row.
  static TextStyle get amountS => _a(size: 14, weight: FontWeight.w700, tabular: true);

  // --- Headings --------------------------------------------------------------------------

  static TextStyle get h1 =>
      _a(size: 31, weight: FontWeight.w800, height: 1.05, letterSpacing: -0.3);
  static TextStyle get h2 =>
      _a(size: 26, weight: FontWeight.w700, height: 1.15, letterSpacing: -0.3);
  static TextStyle get h3 =>
      _a(size: 20, weight: FontWeight.w700, height: 1.2, letterSpacing: -0.2);

  /// A card or row header.
  static TextStyle get title => _a(size: 16, weight: FontWeight.w700, height: 1.3);

  // --- Body ------------------------------------------------------------------------------

  /// A station name, or the figure line under a tab title.
  static TextStyle get bodyL => _a(size: 16, height: 1.3);

  /// Body copy. It defaults to the secondary ink now — full ink is the exception.
  static TextStyle get body => _a(size: 14, height: 1.4, color: VColors.ink2);

  static TextStyle get bodyStrong => _a(size: 14, weight: FontWeight.w600, height: 1.25);
  static TextStyle get bodyS => _a(size: 12, height: 1.45, color: VColors.ink2);
  static TextStyle get bodySStrong => _a(size: 12, weight: FontWeight.w600, height: 1.35);

  static TextStyle get caption => _a(size: 11, height: 1.35, color: VColors.ink3);
  static TextStyle get captionInk => _a(size: 11, height: 1.35);

  // --- Labels ----------------------------------------------------------------------------

  /// A label welded to a figure, or a section inside a card.
  static TextStyle get eyebrow =>
      _a(size: 11, weight: FontWeight.w600, height: 1.2, letterSpacing: 0.33, color: VColors.ink2);

  /// A section label standing on the page rather than on a surface. Tracked wider, because it has
  /// nothing around it to hold it together.
  static TextStyle get eyebrowWide =>
      _a(size: 11, weight: FontWeight.w600, height: 1.2, letterSpacing: 0.9, color: VColors.ink2);

  /// The smallest label, inside a tinted block.
  static TextStyle get eyebrowS =>
      _a(size: 10, weight: FontWeight.w600, height: 1.2, color: VColors.ink2);

  /// A red kicker over a card title.
  static TextStyle get eyebrowRed => _a(
        size: 10,
        weight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0.15,
        color: VColors.red,
      );

  /// An inline red action, always paired with a chevron.
  static TextStyle get link => _a(size: 12, weight: FontWeight.w600, color: VColors.red);

  // --- Controls --------------------------------------------------------------------------

  static TextStyle get button => _a(size: 16, weight: FontWeight.w700, height: 1.2);
  static TextStyle get buttonS => _a(size: 14, weight: FontWeight.w600, height: 1.2);

  /// A line pill, a delay pill, a status pill.
  static TextStyle get pill => _a(size: 11, weight: FontWeight.w700, height: 1.2, tabular: true);

  /// A small flat-sided tag. Tighter than every other label, on purpose.
  static TextStyle get tag =>
      _a(size: 10, weight: FontWeight.w600, height: 1.2, letterSpacing: -0.25);

  /// The inverted dark line badge: bigger than the red pill, because it is the one you are on.
  static TextStyle get badge => _a(size: 14, weight: FontWeight.w700, height: 1.2, tabular: true);

  static TextStyle get tab => _a(size: 11, weight: FontWeight.w600, height: 1.2);

  // --- Numbers in rows --------------------------------------------------------------------

  /// A time in a timeline.
  static TextStyle get mono => _a(size: 14, height: 1.3, tabular: true);

  /// The signed delay under a time. Always signed.
  static TextStyle get delta => _a(size: 13, weight: FontWeight.w700, height: 1.2, tabular: true);

  /// A percentage. German spacing: a space before the sign.
  static TextStyle get pct =>
      _a(size: 11, weight: FontWeight.w500, height: 1.2, tabular: true, color: VColors.ink3);

  /// A weekday under a chart bar.
  static TextStyle get micro =>
      _a(size: 9, weight: FontWeight.w500, height: 1.2, color: VColors.ink3);

  // --- The app's own hand -------------------------------------------------------------------

  /// The four handwritten margin notes, and nothing else. A second face earns its place by doing
  /// a different job: these are asides, not interface.
  static TextStyle get hand => GoogleFonts.caveat(
        fontSize: 17,
        fontWeight: FontWeight.w500,
        height: 1.0,
        color: VColors.ink2,
      );

  static TextStyle get wordmark => _a(size: 18, weight: FontWeight.w700, height: 1.1);
  static TextStyle get tagline => _a(size: 12, height: 1.25);
}
