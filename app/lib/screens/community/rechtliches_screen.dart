import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../content/legal.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';

/// One legal text: Impressum, Datenschutz or "Wie wir Anträge weiterleiten".
/// Renders a [LegalDoc] from lib/content/legal.dart; the words live there.
class RechtlichesScreen extends StatelessWidget {
  const RechtlichesScreen({super.key, required this.doc});
  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    final others = legalDocs.where((d) => d.id != doc.id).toList();
    return VScreen(
      eyebrow: doc.eyebrow,
      title: doc.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(doc.lead, style: VText.body.copyWith(color: VColors.ink2)),
          if (doc.stand != null) ...[
            const VGap.s(),
            Text(doc.stand!, style: VText.caption),
          ],
          const VGap.l(),
          for (final s in doc.sections) ...[
            const VRule(),
            const VGap.m(),
            Text(s.heading, style: VText.title),
            const VGap.s(),
            for (final p in s.paragraphs)
              Padding(
                padding: const EdgeInsets.only(bottom: VSpace.m),
                child: SelectableText(p, style: VText.body),
              ),
            const VGap.xs(),
          ],
          const VGap.m(),
          const VSection('Auch lesen'),
          for (final d in others) VListRow(title: d.title, chevron: true, onTap: () => context.push(Routes.rechtliches(d.id))),
          const VGap.xl(),
        ],
      ),
    );
  }
}
