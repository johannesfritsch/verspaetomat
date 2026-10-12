// A bench, not a test. It renders single widgets to PNGs so a visual pass can look at one
// piece at a time instead of driving the whole app to reach it.
//
//   cd app && flutter test tools/preview_test.dart
//   open /tmp/verspaetomat-preview
//
// It lives under tools/ rather than test/ so `flutter test` does not run it in the ordinary
// suite: it asserts nothing, it only draws.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:verspaetomat/api/models.dart';
import 'package:verspaetomat/repo/repo_scope.dart';
import 'package:verspaetomat/screens/puzzles/piece_in_hand.dart' show PictureTile;
import 'package:verspaetomat/screens/puzzles/puzzle_widgets.dart';
import 'package:verspaetomat/screens/puzzles/puzzles_screen.dart';
import 'package:verspaetomat/state/demo_state.dart';
import 'package:verspaetomat/state/puzzle_video_store.dart';
import 'package:verspaetomat/theme/tokens.dart';
import 'package:verspaetomat/widgets/kit.dart';

/// The phone the design mockups were drawn for, so a preview can be held against them.
const _logical = Size(393, 852);

/// Captured at 3x, the way the device would.
const _pixelRatio = 3.0;

const _outDir = '/tmp/verspaetomat-preview';

/// Where fetch-preview-fonts.sh puts the app's two faces. Gitignored; the bench copes without.
const _fontDir = '.preview-fonts';

void main() {
  setUpAll(() async {
    Directory(_outDir).createSync(recursive: true);
    // The bench has no network and google_fonts fetches at runtime, so every glyph would fall
    // back to the platform face — which has its own metrics and makes a layout check lie about
    // where things sit. app/tools/fetch-preview-fonts.sh drops static TTFs under the exact family
    // names google_fonts uses; loading them here gives the bench the app's real type.
    GoogleFonts.config.allowRuntimeFetching = false;
    // The bench is a test that lives outside test/, so the analyzer does not know it is one.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await _loadFonts();
  });

  _preview('header-scene-home', height: 210, (context) => const VHeaderScene(height: 190));

  _preview('header-scene-wir', height: 210, (context) => const VHeaderScene(height: 190, art: VHeaderSceneArt.landscapeWir));

  // The scene has to survive being narrow and being wide: it bleeds off the right edge, and the
  // title stands over its left half at every width.
  _preview('header-scene-narrow', width: 320, height: 210, (context) => const VHeaderScene(height: 190));

  _preview('header-scene-wide', width: 600, height: 230, (context) => const VHeaderScene(height: 210));

  // The three surfaces, side by side, which is the only way to see whether they read as three
  // things rather than as one thing with three tints.
  _preview('surfaces', height: 640, (context) {
    return Padding(
      padding: const EdgeInsets.all(VSpace.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VBoard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VBoardLabel('Minuten haben wir gewartet', icon: Icons.schedule),
                const VGap.s(),
                Text('1.208.313', style: VText.number.copyWith(color: VColors.inkOnDark)),
                const VGap.s(),
                const VProgressBar(value: 0.62, ground: VProgressGround.dark),
                const VGap.s(),
                const VBoardCaption('1.372 davon deine'),
              ],
            ),
          ),
          const VGap(VSpace.md),
          VCard(
            tone: VCardTone.cta,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VEyebrow('Einchecken', tone: VEyebrowTone.red),
                const VGap.xs(),
                Text('Fährst du gleich?', style: VText.h3),
                const VGap.xs(),
                Text('Von wo, wohin, welcher Zug. Ab dann zählen wir mit.', style: VText.body),
                const VGap.m(),
                VPrimaryButton(label: 'Einchecken', icon: Icons.train, onTap: () {}),
              ],
            ),
          ),
          const VGap(VSpace.md),
          VCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VEyebrow('Deine Woche', size: VEyebrowSize.m),
                const VGap.md(),
                VPanel(
                  tone: VPanelTone.redFaint,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const VEyebrow('Geduldspunkte diese Woche', size: VEyebrowSize.s),
                            const VGap.xs(),
                            Text('+96', style: VText.numberM),
                          ],
                        ),
                      ),
                      const SizedBox(width: VSpace.s),
                      const VWeekBars(
                        values: [12, 18, 26, 34, 22, 8, 41],
                        todayIndex: 6,
                        labels: ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  });

  // The red board, the delay tile and the quieter card tones.
  _preview('surfaces-2', height: 580, (context) {
    return Padding(
      padding: const EdgeInsets.all(VSpace.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VBoard(
            look: VBoardLook.red,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VBoardLabel('Zusammen gewartet', icon: Icons.groups_outlined),
                const VGap.s(),
                Text('1.208.316', style: VText.number.copyWith(color: VColors.inkOnDark)),
                const VGap.s(),
                const VProgressBar(value: 0.72, ground: VProgressGround.red),
                const VGap.s(),
                const VBoardCaption('Minuten, von uns allen zusammen'),
              ],
            ),
          ),
          const VGap(VSpace.md),
          const VDelayTile(3),
          const VGap(VSpace.md),
          VCard(
            tone: VCardTone.sunken,
            padding: const EdgeInsets.all(VSpace.cardTight),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('18.420 Menschen machen mit.', style: VText.bodyStrong),
                      Text('Danke, dass du Teil davon bist.', style: VText.bodyS),
                    ],
                  ),
                ),
                const VProgressBar(value: 0.38, label: '38 %'),
              ],
            ),
          ),
        ],
      ),
    );
  });

  // The three shapes the week chart has to take: the seven days the design asks for, the two
  // columns the API can actually fill today, and a week where nothing happened at all.
  _preview('week-chart', height: 600, (context) {
    Widget panel(String note, Widget chart, String figure) => VCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VPanel(
                tone: VPanelTone.redFaint,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const VEyebrow('Geduldspunkte diese Woche', size: VEyebrowSize.s),
                          const VGap.xs(),
                          Text(figure, style: VText.numberM),
                          const VGap.s(),
                          Text(note, style: VText.bodyS),
                        ],
                      ),
                    ),
                    const SizedBox(width: VSpace.s),
                    chart,
                  ],
                ),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.all(VSpace.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          panel(
            '55 mehr als letzte Woche',
            const VWeekBars(
              values: [41, 96],
              todayIndex: 1,
              labels: ['Letzte', 'Diese'],
            ),
            '+96',
          ),
          const VGap.md(),
          panel(
            'Jede Minute Verspätung wird ein Geduldspunkt.',
            const VWeekBars(values: [0, 0], todayIndex: 1, labels: ['Letzte', 'Diese']),
            '0',
          ),
          const VGap.md(),
          panel(
            'Dein bester Tag war Sonntag',
            const VWeekBars(
              values: [12, 18, 0, 34, 22, 8, 41],
              todayIndex: 6,
              labels: ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'],
            ),
            '+135',
          ),
        ],
      ),
    );
  });

  // The ride sheet's two halves. The tour cannot reach a journey with a change, so the onward
  // leg's card is checked here instead: the leg row, the note and the quiet timeline under it.
  _preview('ride-sheet', height: 840, (context) {
    return Container(
      color: VColors.paperElevated,
      padding: const EdgeInsets.all(VSpace.sheet),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(flex: 48, child: VDelayTile(3)),
              const SizedBox(width: VSpace.md),
              Expanded(
                flex: 52,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const VCallout(
                      icon: Icons.schedule,
                      line1: 'Umstieg Hagen Hbf',
                      line2: '10:41 statt 10:38',
                    ),
                    const VGap.s(),
                    Text(
                      'Wir behalten den weiteren Verlauf für dich im Blick.',
                      style: VText.bodyS,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const VGap.m(),
          const VDivider(),
          const VGap.m(),
          VStopTimeline(
            stops: [
              VStop(
                station: 'Köln Hbf',
                time: '09:50',
                delta: 0,
                tag: 'Zustieg',
                halo: true,
                mark: const VOperatorTag('NordWestBahn'),
              ),
              const VStop(station: 'Solingen Hbf', time: '10:06', delta: 2),
              const VStop(station: 'Wuppertal Hbf', time: '10:19', delta: 3),
              VStop(
                station: 'Hagen Hbf',
                time: '10:41',
                delta: 3,
                tag: 'Umstieg',
                bold: true,
                halo: true,
                mark: const VOperatorTag('NordWestBahn'),
              ),
            ],
          ),
          const VGap.m(),
          const VDivider(),
          const VGap.m(),
          const VEyebrow('Danach', size: VEyebrowSize.wide),
          const VGap.s(),
          VCard(
            tone: VCardTone.raised,
            padding: const EdgeInsets.all(VSpace.cardTight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VLegRow(
                  line: 'RB 52',
                  cls: VLineClass.regional,
                  title: 'nach Lüdenscheid',
                  subtitle: 'ab Hagen Hbf 10:55 · Gl. 6',
                ),
                const VGap.s(),
                const VNoteBanner(
                  icon: Icons.chat_bubble_outline,
                  text: 'Am Umstieg fragen wir einmal: bist du drin?',
                ),
                const VGap.md(),
                VStopTimeline(
                  tone: VTimelineTone.quiet,
                  stops: [
                    VStop(
                      station: 'Hagen Hbf',
                      time: '10:55',
                      tag: 'Umstieg',
                      mark: const VOperatorTag('NordWestBahn'),
                    ),
                    const VStop(station: 'Rummenohl', time: '11:12'),
                    VStop(
                      station: 'Lüdenscheid',
                      time: '11:28',
                      tag: 'Ziel',
                      mark: const VOperatorTag('NordWestBahn'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  });

  // The two handwritten notes that were reported cut off. Both sit at the end of a row with
  // something fixed beside them, which is where a rotated block of writing runs out of room.
  _preview('hand-notes', height: 400, (context) {
    return Padding(
      padding: const EdgeInsets.all(VSpace.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: VTintButton(label: 'Teilen', icon: Icons.ios_share, onTap: () {}),
              ),
              const SizedBox(width: VSpace.s),
              const Expanded(
                flex: 2,
                child: Row(
                  children: [
                    VHandArrow(),
                    SizedBox(width: VSpace.xs),
                    Flexible(
                      child: VHandNote('Zeig, was wir\ngemeinsam schaffen!', angle: -0.06),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const VGap.l(),
          VCard(
            tone: VCardTone.sunken,
            padding: const EdgeInsets.all(VSpace.cardTight),
            child: Row(
              children: [
                const VIconBadge(
                  icon: Icons.groups,
                  tone: VBadgeTone.neutral,
                  size: VControl.badgeSmall,
                ),
                const SizedBox(width: VSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('18.420 Menschen machen mit.', style: VText.bodyStrong),
                      Text('Danke, dass du Teil davon bist.', style: VText.bodyS),
                    ],
                  ),
                ),
                const SizedBox(width: VSpace.s),
                const VHeartMark(size: 20, color: VColors.redTint),
                const SizedBox(width: VSpace.xs),
                const VHandNote('Gemeinsam\nwirken.', angle: -0.12),
              ],
            ),
          ),
        ],
      ),
    );
  });

  // The two check-in backgrounds, straight from the asset bundle. Nothing composes them yet; this
  // is here to prove the files load and that WebP is decoded, before four screens depend on it.
  _preview('checkin-backgrounds', height: 420, (context) {
    Widget band(String path) => ClipRect(
          child: SizedBox(
            height: 190,
            width: double.infinity,
            child: Image.asset(path, fit: BoxFit.fitWidth, alignment: Alignment.topCenter),
          ),
        );
    return Column(
      children: [
        band('assets/header/checkin-platform.webp'),
        const VGap.m(),
        band('assets/header/checkin-clock.webp'),
      ],
    );
  });

  // Over the real thing: a title set across the faded half, which is the only test that matters
  // for a background.
  _preview('header-scene-with-title', height: 230, (context) {
    return Stack(
      children: [
        const Positioned(left: 0, right: 0, top: 0, child: VHeaderScene(height: 200)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 34, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Willkommen', style: VText.h1.copyWith(fontSize: 40)),
              const SizedBox(height: 6),
              Text('Jede verspätete Minute\nkann etwas bewegen.', style: VText.body.copyWith(color: VColors.ink2)),
            ],
          ),
        ),
      ],
    );
  });

  // docs/51 §7: the pieces have to read as a puzzle at every size — on the Puzzles page, in the
  // arrival card, and as the thumbnail on Ich's row — and a finished picture has no seams.
  // §2a: every slot shows its tier, owned or missing; the thumbnail drops the marks.
  _preview('puzzle-boards', height: 560, (context) {
    const cut = PuzzleCut(imageId: 'demo-bahnhofsmission', rows: 4, cols: 3);
    const image = AssetImage('assets/demo/puzzles/bahnhofsmission.webp');
    final tiers = _tiers('qmmmmqmHmmqm');
    return Padding(
      padding: const EdgeInsets.all(VSpace.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Owned: two quarters (0, 5) and minutes. Missing: the hour (7), a quarter (10), minutes.
              SizedBox(width: 168, child: PuzzleBoard(cut: cut, image: image, tiers: tiers, owned: const {0, 2, 4, 5, 6, 9, 11})),
              const SizedBox(width: VSpace.m),
              SizedBox(
                width: 168,
                child: PuzzleBoard(cut: const PuzzleCut(imageId: 'demo-wald', rows: 4, cols: 3), image: const AssetImage('assets/demo/puzzles/wald.webp'), tiers: _tiers('mmqmHmqmmmmq'), complete: true),
              ),
            ],
          ),
          const VGap.m(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // The hour owned, the quarters still to come.
              SizedBox(width: 112, child: PuzzleBoard(cut: cut, image: image, tiers: tiers, owned: const {1, 2, 3, 4, 6, 7, 8, 9, 11})),
              const SizedBox(width: VSpace.m),
              const SizedBox(width: 72, child: PuzzleBoard(cut: PuzzleCut(imageId: 'leer', rows: 4, cols: 3))),
              const SizedBox(width: VSpace.m),
              SizedBox(width: 33, child: PuzzleBoard(cut: cut, image: image, tiers: tiers, owned: const {0, 2, 4, 5, 6, 9, 11})),
              const SizedBox(width: VSpace.m),
              SizedBox(
                width: 96,
                child: PuzzleBoard(cut: const PuzzleCut(imageId: 'demo-kinderhospiz', rows: 4, cols: 3), image: const AssetImage('assets/demo/puzzles/kinderhospiz.webp'), tiers: _tiers('mqmqmmmHmqmm'), owned: const {1, 8}),
              ),
            ],
          ),
        ],
      ),
    );
  });

  // docs/51 §5: the reveal frame by frame — from below, turned and lifted; gliding in; the click
  // with the red light under it; settled. The bench cannot stop an animation half way, so these
  // are the reveal held at fixed moments. The second row is the hour piece, whose light lingers.
  _preview('puzzle-reveal-frames', height: 720, (context) {
    const cut = PuzzleCut(imageId: 'demo-bahnhofsmission', rows: 4, cols: 3);
    const image = AssetImage('assets/demo/puzzles/bahnhofsmission.webp');
    final tiers = _tiers('qmmmmqmHmmqm');
    Widget row(int piece) => Wrap(
          spacing: VSpace.m,
          runSpacing: VSpace.l,
          children: [
            for (final t in const [0.03, 0.3, 0.5, 0.7, 0.85, 1.0])
              SizedBox(
                width: 104,
                child: PieceReveal(cut: cut, image: image, tiers: tiers, owned: {0, 2, 4, 5, 6, 9, 11, piece}, piece: piece, reveal: AlwaysStoppedAnimation(t)),
              ),
          ],
        );
    return Padding(
      padding: const EdgeInsets.all(VSpace.page),
      child: Column(children: [row(8), const VGap.xl(), row(7)]),
    );
  });

  // The arrival's card for each tier: a minute from your own Verein, a quarter from somebody
  // else's, the hour that leaves only a quarter missing, and the last piece — a minute, as the
  // `complete` variant brings. One long title too. On white, as the sheet is.
  _preview('puzzle-arrival', height: 1460, background: VColors.paperElevated, (context) {
    ApiPuzzlePiece piece(String ngo, String name, String tiers, String title, String caption, List<int> owned, int last, {bool own = true}) => ApiPuzzlePiece(
          puzzle: ApiPuzzle(
            imageId: 'demo-$ngo',
            rows: 4,
            cols: 3,
            owned: owned,
            tiers: _tiers(tiers),
            complete: owned.length == 12,
            title: title,
            caption: caption,
            ngoId: ngo,
            ngoName: name,
            imageUrl: 'assets/demo/puzzles/$ngo.webp',
            width: 900,
            height: 1200,
          ),
          piece: last,
          ownCause: own,
        );
    const bm = 'qmmmmqmHmmqm';
    const nacht = 'Nachtschicht am Gleis 1';
    const tee = 'Um drei Uhr nachts ist hier noch Licht, und der Tee ist heiß.';
    return _withSession(
      Padding(
        // The arrival sheet's own gutter, so the text column is as narrow as on the phone.
        padding: const EdgeInsets.all(VSpace.sheet),
        child: Column(
          children: [
            ArrivalPieceCard(piece: piece('bahnhofsmission', 'Bahnhofsmission Köln', bm, nacht, tee, [0, 2, 4, 5, 6, 8, 9, 11], 8), delay: Duration.zero),
            const VGap.md(),
            ArrivalPieceCard(piece: piece('bahnhofsmission', 'Bahnhofsmission Köln', bm, nacht, tee, [0, 2, 4, 5, 6, 9, 10, 11], 10), delay: Duration.zero),
            const VGap.md(),
            ArrivalPieceCard(
              piece: piece('kinderhospiz', 'Kinderhospiz Rheinland', 'mqmqmmmHmqmm', 'Die Schaukel im Garten am Haus in Ehrenfeld', 'Die Schaukel hängt seit dem Sommer.', [1, 3, 8], 3, own: false),
              delay: Duration.zero,
            ),
            const VGap.md(),
            ArrivalPieceCard(piece: piece('bahnhofsmission', 'Bahnhofsmission Köln', bm, nacht, tee, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11], 7), delay: Duration.zero),
            const VGap.md(),
            ArrivalPieceCard(
              piece: piece('wald', 'Wald für morgen e.V.', 'mmqmHmqmmmmq', 'Die erste Reihe am Hang', 'Vierhundert Setzlinge bei Monschau, gepflanzt im Oktober.', [for (var i = 0; i < 12; i++) i], 0),
              delay: Duration.zero,
            ),
          ],
        ),
      ),
    );
  });

  // docs/51 §6: the page, scrolled out in full — a picture under way, one that waits only for
  // rare pieces, and two finished ones, titles whole.
  _preview('puzzles-page', height: 1220, (context) {
    ApiPuzzle p(String ngo, String name, String tiers, String title, List<int> owned) => ApiPuzzle(
          imageId: 'demo-$ngo',
          rows: 4,
          cols: 3,
          owned: owned,
          tiers: _tiers(tiers),
          complete: owned.length == 12,
          title: title,
          ngoId: ngo,
          ngoName: name,
          imageUrl: 'assets/demo/puzzles/$ngo.webp',
          width: 900,
          height: 1200,
          // §9b: every Demo picture moves once it is finished.
          hasVideo: true,
          video: owned.length == 12 ? ApiPuzzleVideo(url: 'assets/demo/puzzles/$ngo.mp4', bytes: 0) : null,
        );
    final all = [for (var i = 0; i < 12; i++) i];
    return _withSession(
      Padding(
        padding: const EdgeInsets.all(VSpace.l),
        child: PuzzlesBody(
          puzzles: ApiPuzzles(puzzles: [
            p('bahnhofsmission', 'Bahnhofsmission Köln', 'qmmmmqmHmmqm', 'Nachtschicht am Gleis 1', [0, 2, 4, 5, 6, 9, 11]),
            p('kinderhospiz', 'Kinderhospiz Rheinland', 'mqmqmmmHmqmm', 'Der Garten in Ehrenfeld', [0, 2, 4, 5, 6, 8, 10, 11, 9]),
            p('wald', 'Wald für morgen e.V.', 'mmqmHmqmmmmq', 'Die erste Reihe am Hang', all),
            p('kinderhospiz', 'Kinderhospiz Rheinland', 'mqmqmmmHmqmm', 'Der Garten in Ehrenfeld', all),
          ]),
        ),
      ),
    );
  });
  // docs/51 §9a: the piece in the hand at rest, turned 30°, edge-on and from behind — a minute, a
  // quarter and an hour — and a whole finished picture, lit by the shader where this engine can
  // run it (TileShading checks; otherwise the gradient light). The simulator shows the same at
  // /showcase/tile3d.
  _preview('puzzle-tile-frames', width: 1000, height: 1240, (context) {
    const cut = PuzzleCut(imageId: 'demo-bahnhofsmission', rows: 4, cols: 3);
    const image = AssetImage('assets/demo/puzzles/bahnhofsmission.webp');
    const board = Size(1000, 1000 / 0.75);
    const tilts = [TileTilt(0, 0), TileTilt.rest, TileTilt(0.14, 0.52), TileTilt(0.1, 1.4), TileTilt(0.14, 3.0)];
    Widget piece(int slot, PieceTier tier, TileTilt t) => PuzzlePicture(
          image: image,
          builder: (context, img) {
            final shape = pieceShape(cut, slot, board, img == null ? board : Size(img.width.toDouble(), img.height.toDouble()));
            return Tile3D(
              cacheKey: 'bench/$slot',
              outline: shape.outline,
              image: img,
              source: shape.source,
              tier: tier,
              width: 140,
              tilt: t,
              back: (context) => _BenchBack(tier: tier),
            );
          },
        );
    return Padding(
      padding: const EdgeInsets.all(VSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (slot, tier) in const [(1, PieceTier.minute), (5, PieceTier.quarter), (7, PieceTier.hour)]) ...[
            Row(
              children: [
                for (final t in tilts) Padding(padding: const EdgeInsets.only(right: 44), child: SizedBox(width: 140, height: 210, child: Center(child: piece(slot, tier, t)))),
              ],
            ),
            const VGap.l(),
          ],
          Row(
            children: [
              for (final t in const [TileTilt.rest, TileTilt(0.2, 0.6), TileTilt(0.12, 3.0)])
                Padding(
                  padding: const EdgeInsets.only(right: 60),
                  child: PuzzlePicture(
                    image: image,
                    builder: (context, img) => Tile3D(
                      cacheKey: 'bench/picture',
                      outline: Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & board, const Radius.circular(33))),
                      image: img,
                      source: pictureSource(img == null ? board : Size(img.width.toDouble(), img.height.toDouble()), board, Offset.zero & board),
                      width: 220,
                      depth: 0.025,
                      tilt: t,
                      back: (context) => ColoredBox(color: VColors.track, child: Center(child: Text('Nachtschicht am Gleis 1', style: VText.title))),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  });

  // docs/51 §9b: the button on a finished picture — ready to play, coming in (the ring at 40 %),
  // and failed (try again) — and the back of a finished picture, set like a card.
  _preview('puzzle-film-states', width: 900, height: 520, (context) {
    // The bench runs in fake time, where nothing downloads: the states are shown as they would be.
    final store = PuzzleVideoStore(directory: () async => Directory.systemTemp, fetch: (url, {from = 0}) => Completer<http.StreamedResponse>().future);
    ApiPuzzle picture(String id, String url) => ApiPuzzle(
          imageId: id,
          rows: 4,
          cols: 3,
          owned: [for (var i = 0; i < 12; i++) i],
          complete: true,
          title: 'Die erste Reihe am Hang',
          caption: 'Vierhundert Setzlinge bei Monschau, gepflanzt im Oktober.',
          ngoId: 'wald',
          ngoName: 'Wald für morgen e.V.',
          imageUrl: 'assets/demo/puzzles/wald.webp',
          width: 900,
          height: 1200,
          completedAt: DateTime(2026, 10, 3),
          hasVideo: true,
          video: ApiPuzzleVideo(url: url, bytes: 1000, seconds: 20, sha256: 'abcdef01', width: 900, height: 1200),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: invalid_use_of_visible_for_testing_member
      store.debugShow(picture('coming', '/v1/puzzle-videos/coming'), const PuzzleVideoState(VideoPhase.downloading, progress: 0.4));
      // ignore: invalid_use_of_visible_for_testing_member
      store.debugShow(picture('failed', '/v1/puzzle-videos/failed'), PuzzleVideoState.failed);
    });
    return _withSession(
      Padding(
        padding: const EdgeInsets.all(VSpace.xl),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PictureTile(puzzle: picture('ready', 'assets/demo/puzzles/wald.mp4'), width: 180, tilt: TileTilt.rest),
            const SizedBox(width: VSpace.xl),
            PictureTile(puzzle: picture('coming', '/v1/puzzle-videos/coming'), width: 180, tilt: TileTilt.rest),
            const SizedBox(width: VSpace.xl),
            PictureTile(puzzle: picture('failed', '/v1/puzzle-videos/failed'), width: 180, tilt: TileTilt.rest),
            const SizedBox(width: VSpace.xl),
            PictureTile(puzzle: picture('back', 'assets/demo/puzzles/wald.mp4'), width: 180, tilt: const TileTilt(0.12, 3.0)),
          ],
        ),
      ),
      videos: store,
    );
  });
}

class _BenchBack extends StatelessWidget {
  const _BenchBack({required this.tier});
  final PieceTier tier;

  @override
  Widget build(BuildContext context) => ColoredBox(color: VColors.track, child: Center(child: TierClock(tier, size: 34)));
}

/// A tier map in the demo's shorthand: `m` minute, `q` quarter, `H` hour.
List<PieceTier> _tiers(String s) => [for (final c in s.split('')) c == 'H' ? PieceTier.hour : (c == 'q' ? PieceTier.quarter : PieceTier.minute)];

/// A Demo session around [child], for the pieces that ask the repository for their pictures.
Widget _withSession(Widget child, {PuzzleVideoStore? videos}) => FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (context, prefs) => prefs.data == null
          ? const SizedBox.shrink()
          : RepoScope(session: Session(demo: DemoState(), prefs: prefs.data!, apiUrl: '', videoStore: videos), child: Material(type: MaterialType.transparency, child: child)),
    );

/// Registers the faces fetched by tools/fetch-preview-fonts.sh, if they are there.
///
/// Missing fonts are not an error: the bench still draws, it just draws in the platform face, and
/// the run says so once rather than failing. The family names have to match what google_fonts
/// asks for exactly — "Archivo_800", not "Archivo".
Future<void> _loadFonts() async {
  final dir = Directory(_fontDir);
  if (!dir.existsSync()) {
    // ignore: avoid_print
    print('NOTE no fonts in $_fontDir — run tools/fetch-preview-fonts.sh for real type');
    return;
  }
  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.ttf')) continue;
    final family = file.uri.pathSegments.last.replaceAll('.ttf', '');
    await (FontLoader(family)..addFont(Future.value(file.readAsBytesSync().buffer.asByteData())))
        .load();
  }
}

/// Renders one widget on the page background and writes it to a PNG.
void _preview(
  String name,
  Widget Function(BuildContext context) build, {
  double? width,
  double? height,
  Color background = const Color(0xFFF7F8FA),
}) {
  testWidgets(name, (tester) async {
    final size = Size(width ?? _logical.width, height ?? _logical.height);
    tester.view
      ..physicalSize = size * _pixelRatio
      ..devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.reset);

    final boundary = GlobalKey();
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, devicePixelRatio: _pixelRatio),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: boundary,
            child: Container(
              width: size.width,
              height: size.height,
              color: background,
              child: Builder(builder: build),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Images do not decode in a widget test unless you make them. Without this every preview
    // holding an asset comes out blank, which is worse than no preview: it looks like a bug in
    // the thing being reviewed rather than a bug in the bench.
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
      // The puzzle boards resolve their picture themselves rather than through an Image.
      for (final element in find.byType(PuzzlePicture).evaluate()) {
        final image = (element.widget as PuzzlePicture).image;
        if (image != null) await precacheImage(image, element);
      }
    });
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final object = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await object.toImage(pixelRatio: _pixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
    // ignore: avoid_print
    print('PREVIEW $_outDir/$name.png');
  });
}
