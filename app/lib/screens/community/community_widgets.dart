import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';

/// The name a customer goes by: the nickname they chose, else the first name from
/// their claim data, else null. "Fahrgast" is the server's blank, not a name.
String? displayName(ApiCustomer? me) {
  if (me == null) return null;
  final nick = me.nickname.trim();
  if (nick.isNotEmpty && nick != 'Fahrgast') return nick;
  final first = me.personalData?.name.trim().split(RegExp(r'\s+')).first;
  if (first != null && first.isNotEmpty) return first;
  return null;
}

/// Header for a tab screen: title on the left, an optional trailing widget and
/// the settings gear on the right (the gear sits top right on every tab, decided
/// 10 September 2026).
class TabHeader extends StatelessWidget {
  const TabHeader({super.key, required this.title, this.caption, this.trailing, this.onSettings});
  final String title;
  final String? caption;
  final Widget? trailing;

  /// Opens Einstellungen; defaults to pushing the route. Pass a callback to refresh afterwards.
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: VText.h1),
              if (caption != null) ...[const SizedBox(height: 2), Text(caption!, style: VText.caption)],
            ],
          ),
        ),
        if (trailing != null) ...[trailing!, const SizedBox(width: 4)],
        VIconButton(icon: Icons.settings_outlined, onTap: onSettings ?? () => context.push(Routes.einstellungen)),
      ],
    );
  }
}

/// A row of segment chips: one selected, ink on paper.
class SegmentTabs extends StatelessWidget {
  const SegmentTabs({super.key, required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 8),
              child: InkWell(
                onTap: () => onChanged(i),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: i == index ? VColors.ink : Colors.transparent,
                    border: Border.all(color: i == index ? VColors.ink : VColors.rule),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(labels[i], style: VText.bodySStrong.copyWith(color: i == index ? VColors.paper : VColors.ink)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A filter chip row (e.g. by line). `null` value = all.
class FilterChips extends StatelessWidget {
  const FilterChips({super.key, required this.options, required this.selected, required this.onSelect});
  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final all = <String?>[null, ...options];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final o in all)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () => onSelect(o),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: o == selected ? VColors.ink : Colors.transparent,
                    border: Border.all(color: o == selected ? VColors.ink : VColors.rule),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: Text(o ?? 'Alle', style: VText.tab.copyWith(color: o == selected ? VColors.paper : VColors.ink)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One line of a board: rank, name, points (#24).
///
/// The list used to be ten rows of the same weight: a mono rank hanging at the left of a 44 pt
/// column, a red dot that pushed the passenger's own name out of line with every other name, and
/// nothing at all to say who is at the top. It read as a table of numbers rather than as a
/// standing.
///
/// Three things carry it now. **The rank is a column, not an indent**: 28 pt wide and centred, so
/// 1 and 10 sit under each other and every name starts at the same x. **The first three get a
/// disc** in gold, silver and bronze — a fourth identity family in the palette, muted into the
/// same tint band as the operator hues, on the disc only and never on type (`STYLE.md`). They were
/// kept out until #24 asked for them, and they earn their place the way teal does: a place on a
/// board is who you are on that list.
/// **Your own row is the tinted one**, edge to edge. That is the app's own mark for *this one is
/// yours*, and it does the job the red dot was doing without moving the text a single point. The
/// words stay in ink: the tint already says whose row it is, and `VColors.red` is spoken for —
/// *do this* or *this is money* — so the one red left on the row is its rank.
class BoardRow extends StatelessWidget {
  const BoardRow({super.key, required this.entry});
  final ApiBoardEntry entry;

  @override
  Widget build(BuildContext context) {
    final me = entry.isMe;
    // No horizontal inset: the rows share the card's gutter with the tabs above them, the
    // hairlines between them and the footnote below them, and 8 pt of their own put the names on
    // a different left edge from everything else in the card.
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          _Rank(rank: entry.rank, me: me),
          const SizedBox(width: VSpace.md),
          Expanded(
            child: Text(
              me ? 'Du' : entry.name,
              style: (me ? VText.bodyStrong : VText.body).copyWith(color: VColors.ink),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(fmtInt(entry.points), style: VText.mono.copyWith(fontWeight: FontWeight.w700, color: VColors.ink)),
        ],
      ),
    );
    if (!me) return content;
    // The band runs the full width of the card's content, so the row keeps the same left edge as
    // every other row and the tint reads as something behind the line rather than a box round it.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(color: VColors.redTintFaint, borderRadius: BorderRadius.circular(VRadius.md)),
        child: content,
      ),
    );
  }
}

/// The place: a disc for the first three, bare figures below that.
class _Rank extends StatelessWidget {
  const _Rank({required this.rank, required this.me});
  final int rank;
  final bool me;

  static const _size = 28.0;

  @override
  Widget build(BuildContext context) {
    final podium = rank <= 3;
    final Color ink;
    final Color? disc;
    if (podium) {
      // Gold, silver and bronze, muted into the palette's tint band (#24). The metal is the disc
      // and nothing else: the numeral on all three is the full ink, which is what keeps them
      // readable and keeps colour off the type.
      disc = switch (rank) {
        1 => VColors.podiumGold,
        2 => VColors.podiumSilver,
        _ => VColors.podiumBronze,
      };
      ink = VColors.ink;
    } else {
      disc = null;
      // The place is what the row is ranked by, so it is content and takes the body grey, not the
      // caption grey. Your own place is the one red on the list.
      ink = me ? VColors.red : VColors.ink2;
    }
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: disc == null ? null : BoxDecoration(color: disc, shape: BoxShape.circle),
      // Below the top ten the list pins the passenger's own place, and that can be four figures
      // wide. Scaled down rather than wrapped: a rank that breaks across two lines is clipped by
      // the disc and reads as a different number.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$rank',
          maxLines: 1,
          style: VText.mono.copyWith(fontWeight: podium ? FontWeight.w700 : FontWeight.w500, color: ink),
        ),
      ),
    );
  }
}

/// Big figure with a label underneath. Tappable for a source sheet.
class BigFigure extends StatelessWidget {
  const BigFigure({super.key, required this.value, required this.label, this.style, this.onTap});
  final String value;
  final String label;
  final TextStyle? style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bare digits, no flaps: four boards in a grid would shout over the one that matters
            // (docs/35). The Fallblatt is for the figure a screen is about.
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: style ?? VText.numberM)),
            const SizedBox(height: 4),
            Text(label, style: VText.caption),
          ],
        ),
      ),
    );
  }
}

/// A source sheet: "Woher weißt du das?"
///
/// Two paragraphs at most, both written as answers. It used to end in a register row — the word
/// „Aktualität" over the word „Live" — which reads as a database column, not as an answer to the
/// question in the header (#23). A sheet that explains a number is prose or it is nothing.
void showSourceSheet(BuildContext context, {required String title, required String origin, String? update}) {
  showVSheet(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VSheetHeader(title: 'Woher weißt du das?', subtitle: title),
          Padding(
            // The sheet's gutter, not the page's: the answer has to start under its own question.
            padding: const EdgeInsets.fromLTRB(VSpace.sheet, VSpace.s, VSpace.sheet, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(origin, style: VText.body),
                if (update != null) ...[
                  const VGap.m(),
                  Text(update, style: VText.bodyS.copyWith(color: VColors.ink2)),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// „Woher weißt du das?" for the minutes the whole community has waited — the one figure that
/// stands on two screens, so both take the same answer: the board on Home and the board on Wir.
void showMinutesSource(BuildContext context) => showSourceSheet(
      context,
      title: 'Minuten zusammen gewartet',
      // Word for word what „Woher kommen die Daten?" says about this figure and about the number
      // it is made of, including the case where there were no live data: a ride whose arrival the
      // passenger typed in counts too, and a sheet that leaves that out promises more than the
      // number can keep.
      origin: 'Die Summe aller endgültigen Verspätungen aller Fahrgäste, Minute für Minute. '
          'Gezählt wird die Verspätung an dem Halt, an dem jemand ausgestiegen ist: geplante '
          'Ankunft aus dem Fahrplan, tatsächliche aus den Live-Daten. Wo es keine Live-Daten gab, '
          'zählt die Zeit, die der Fahrgast selbst eingetragen hat, und ein ausgefallener Zug '
          'zählt mit mindestens 60 Minuten.',
      update: 'Die Zahl wächst laufend: jede Fahrt kommt dazu, sobald sie vorbei und ihre '
          'Verspätung endgültig ist.',
    );

/// A badge: a circle in the station-clock spirit, name below.
/// The achievement artwork from `assets/achievements/<stem>-aktiv|inaktiv.png` (Johannes'
/// icons, prepared by `tools/badge_icons.sh`): a red ring with the motif when earned, grey
/// otherwise. Ids that have no artwork fall back to the old dot in a ring.
class BadgeIcon extends StatelessWidget {
  const BadgeIcon({super.key, required this.badge, required this.size});
  final ApiBadge badge;
  final double size;

  static const _stems = <String, String>{
    'erste': 'erste-verspaetung',
    'sev': 'schienenersatzverkehr',
    'stellwerk': 'stellwerksstoerung',
    'gleis': 'personen-im-gleis',
    'gegenzug': 'gegenzug-abgewartet',
    'letzter': 'letzter-zug',
    'nacht': 'nachtschicht',
    'stunde': 'volle-stunde',
    'bagatell': 'bagatellgrenze-geknackt',
    'abgeschickt': 'abgeschickt',
    'bestaetigt': 'bestaetigt',
    'deutschland': 'deutschlandreise',
    'stammgleis': 'stammgleis',
  };

  static String? assetFor(String id, {required bool earned}) {
    final stem = _stems[id] ?? (id.startsWith('minuten-') ? 'verspaetungsminuten-${id.substring(8)}' : null);
    if (stem == null) return null;
    return 'assets/achievements/$stem-${earned ? 'aktiv' : 'inaktiv'}.png';
  }

  @override
  Widget build(BuildContext context) {
    final earned = badge.earned;
    final asset = assetFor(badge.id, earned: earned);
    if (asset != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Image.asset(asset, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: earned ? VColors.paperElevated : Colors.transparent,
        border: Border.all(color: earned ? VColors.ink : VColors.rule, width: earned ? 2.5 : 1.5),
      ),
      child: Center(
        child: earned
            ? Container(width: size / 5, height: size / 5, decoration: const BoxDecoration(color: VColors.red, shape: BoxShape.circle))
            : Container(width: size / 5, height: size / 5, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: VColors.rule, width: 1.5))),
      ),
    );
  }
}

class BadgeTile extends StatelessWidget {
  const BadgeTile({super.key, required this.badge, required this.onTap});
  final ApiBadge badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final earned = badge.earned;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            BadgeIcon(badge: badge, size: 64),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: LayoutBuilder(
                builder: (context, c) {
                  final style = VText.captionInk.copyWith(color: earned ? VColors.ink : VColors.ink3, fontWeight: earned ? FontWeight.w600 : FontWeight.w500);
                  return Text(
                    hyphenateToFit(badge.name, style, c.maxWidth),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Flutter breaks at a soft hyphen (U+00AD) but draws no hyphen. When a name
/// does not fit on one line, the first soft hyphen becomes "-" + line break;
/// otherwise the soft hyphens are dropped.
String hyphenateToFit(String name, TextStyle style, double maxWidth) {
  if (!name.contains('\u00AD')) return name;
  final plain = name.replaceAll('\u00AD', '');
  final painter = TextPainter(text: TextSpan(text: plain, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout(maxWidth: double.infinity);
  if (painter.width <= maxWidth) return plain;
  final at = name.indexOf('\u00AD');
  return '${name.substring(0, at)}-\n${name.substring(at + 1).replaceAll('\u00AD', '')}';
}

/// Settings row with a switch on the right.
class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: VText.bodyStrong),
                    if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: VText.caption)],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
        const VRule(),
      ],
    );
  }
}

/// Radio-like row for a choice among a few.
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({super.key, required this.title, this.subtitle, required this.selected, required this.onTap});
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? VColors.red : VColors.rule, width: 1.5),
                  ),
                  child: selected
                      ? Center(child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: VColors.red, shape: BoxShape.circle)))
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: selected ? VText.bodyStrong : VText.body),
                      if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: VText.caption)],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const VRule.soft(),
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// The Zweck picker (docs/20 §4): shared by Einstellungen and the collecting card on
/// Anträge. Choosing updates the customer's setting; every future claim goes there.
void pickNgo(BuildContext context, Session session, String? current) {
  showVSheet(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VSheetHeader(title: 'Dein Zweck', subtitle: 'Wohin die Bahn überweist'),
          Padding(
            padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, 0),
            child: Column(
              children: [
                for (final n in session.ngos) ...[
                  VChoiceCard(
                    title: n.name,
                    subtitle: n.tagline,
                    selected: current == n.id,
                    onTap: () {
                      session.updateSettings(MePatch(ngoId: n.id));
                      Navigator.of(ctx).pop();
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
