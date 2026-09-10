import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
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

/// One line of a board: rank, name, points. The customer's row is bold with a red mark.
class BoardRow extends StatelessWidget {
  const BoardRow({super.key, required this.entry});
  final ApiBoardEntry entry;

  @override
  Widget build(BuildContext context) {
    final me = entry.isMe;
    final style = me ? VText.bodyStrong : VText.body;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text('${entry.rank}', style: VText.mono.copyWith(color: me ? VColors.ink : VColors.ink2)),
              ),
              if (me)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: const BoxDecoration(color: VColors.red, shape: BoxShape.circle),
                ),
              Expanded(child: Text(me ? 'Du' : entry.name, style: style, overflow: TextOverflow.ellipsis)),
              Text(fmtInt(entry.points), style: VText.mono.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const VRule.soft(),
      ],
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
void showSourceSheet(BuildContext context, {required String title, required String origin, String? freshness, String? fallback}) {
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
            padding: const EdgeInsets.fromLTRB(VSpace.page, VSpace.s, VSpace.page, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(origin, style: VText.body),
                if (freshness != null) ...[const VGap.m(), VKeyValue('Aktualität', freshness)],
                if (fallback != null) ...[const VRule(), VKeyValue('Wenn es fehlt', fallback)],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// A badge: a circle in the station-clock spirit, name below.
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
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: earned ? VColors.paperElevated : Colors.transparent,
                border: Border.all(color: earned ? VColors.ink : VColors.rule, width: earned ? 2.5 : 1.5),
              ),
              child: Center(
                child: earned
                    ? Container(width: 12, height: 12, decoration: const BoxDecoration(color: VColors.red, shape: BoxShape.circle))
                    : Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: VColors.rule, width: 1.5))),
              ),
            ),
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
