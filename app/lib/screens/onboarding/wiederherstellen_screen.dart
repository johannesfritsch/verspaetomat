import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:go_router/go_router.dart';

import '../../repo/repo_scope.dart';
import '../../router.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';

/// Where the twelve words are typed back in.
///
/// This screen was the missing half of a feature the app already advertised. The code was minted,
/// shown once and written on paper, and `HttpRepository.recover` existed — with no call site
/// anywhere. A passenger on a new phone had nowhere to type it, which made the words a souvenir.
///
/// It is reachable from Willkommen, before an account is chosen, because that is when a person who
/// has changed phones actually needs it. Recovering points this install at the old account: the old
/// phone's token stops working, which is the intended effect of moving.
class WiederherstellenScreen extends StatefulWidget {
  const WiederherstellenScreen({super.key});

  @override
  State<WiederherstellenScreen> createState() => _WiederherstellenScreenState();
}

class _WiederherstellenScreenState extends State<WiederherstellenScreen> {
  final _ctl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// Twelve words, however they were typed: extra spaces, line breaks from a paste, capitals.
  List<String> get _words => _ctl.text.toLowerCase().split(RegExp(r'[^a-zäöüß]+')).where((w) => w.isNotEmpty).toList();

  bool get _looksComplete => _words.length == 12;

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    setState(() {
      _ctl.text = text.trim();
      _error = null;
    });
  }

  Future<void> _recover() async {
    final session = RepoScope.read(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.recoverAccount(_words.join(' '));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Konto zurückgeholt.')));
      context.go(Routes.bahnsteig);
    } catch (e) {
      if (!mounted) return;
      final unknown = e.toString().contains('unknown recovery code') || e.toString().contains('404');
      setState(() => _error = unknown
          ? 'Diese zwölf Wörter kennen wir nicht. Prüf die Reihenfolge und die Schreibweise.'
          : 'Das hat nicht geklappt: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return VScreen(
      eyebrow: 'Kein Konto, zwölf Wörter',
      title: 'Konto zurückholen',
      scroll: true,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VPrimaryButton(
            label: 'Konto zurückholen',
            busy: _busy,
            onTap: _looksComplete && !_busy ? _recover : null,
          ),
          const VGap.xs(),
          VGhostButton(label: 'Abbrechen', onTap: () => context.canPop() ? context.pop() : context.go(Routes.welcome)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VGap.s(),
          Text('Tipp die zwölf Wörter ein, die dir dein altes Telefon gezeigt hat.', style: VText.body),
          const VGap.s(),
          Text(
            'Reihenfolge zählt, Groß- und Kleinschreibung nicht. Danach gehört dieses Telefon zu '
            'deinem alten Konto — mit deinen Fahrten, deinen Anträgen und deiner Verspätomat-Adresse. '
            'Das alte Telefon meldet sich damit ab.',
            style: VText.caption,
          ),
          const VGap.l(),
          VCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _ctl,
                  onChanged: (_) => setState(() => _error = null),
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  maxLines: 3,
                  style: VText.mono,
                  decoration: const InputDecoration(
                    hintText: 'wort wort wort wort wort wort\nwort wort wort wort wort wort',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const VGap.s(),
                const VDivider(),
                const VGap.s(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_words.length} von 12 Wörtern',
                        style: VText.caption.copyWith(color: _looksComplete ? VColors.green : VColors.ink3),
                      ),
                    ),
                    VGhostButton(label: 'Einfügen', icon: Icons.content_paste, color: VColors.ink2, onTap: _paste),
                  ],
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const VGap.s(),
            VNoteBanner(icon: Icons.error_outline, text: _error!),
          ],
          const VGap.l(),
          const VNoteBanner(
            tone: VNoteTone.neutral,
            icon: Icons.help_outline,
            text: 'Keine zwölf Wörter? Dann fang neu an. Ein Konto ohne Code lässt sich nicht '
                'zurückholen — es gibt keine E-Mail und kein Passwort, an die wir uns wenden könnten.',
          ),
          const VGap.xl(),
        ],
      ),
    );
  }
}
