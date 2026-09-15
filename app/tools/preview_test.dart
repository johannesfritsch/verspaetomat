// A bench, not a test. It renders single widgets to PNGs so a visual pass can look at one
// piece at a time instead of driving the whole app to reach it.
//
//   cd app && flutter test tools/preview_test.dart
//   open /tmp/verspaetomat-preview
//
// It lives under tools/ rather than test/ so `flutter test` does not run it in the ordinary
// suite: it asserts nothing, it only draws.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:verspaetomat/theme/tokens.dart';
import 'package:verspaetomat/widgets/header_scene.dart';
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
    await _loadFonts();
  });

  _preview('header-scene-home', height: 210, (context) => const VHeaderScene(height: 190));

  _preview('header-scene-wir', height: 210, (context) => const VHeaderScene(height: 190, heart: true));

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
}

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
