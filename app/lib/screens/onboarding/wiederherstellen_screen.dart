import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter, TextEditingValue;
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
///
/// Twelve numbered boxes rather than one free-text field: the numbers are the only thing that makes
/// „Reihenfolge zählt" checkable by the person typing, and a word in the wrong box is visible
/// before the server is asked. Nothing needs a paste button — a phrase pasted into any box spreads
/// itself across the boxes from there, and so does one typed with spaces between the words.
class WiederherstellenScreen extends StatefulWidget {
  const WiederherstellenScreen({super.key});

  @override
  State<WiederherstellenScreen> createState() => _WiederherstellenScreenState();
}

/// A recovery word is lower-case letters and nothing else, so the box refuses everything else as
/// it is typed. It keeps a trailing separator, which is what [_spread] reads as "next box".
class _WordInput extends TextInputFormatter {
  const _WordInput();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue _, TextEditingValue next) {
    final cleaned = next.text.toLowerCase().replaceAll(RegExp(r'[^a-zäöüß \n\t]'), '');
    if (cleaned == next.text) return next;
    return TextEditingValue(text: cleaned, selection: TextSelection.collapsed(offset: cleaned.length));
  }
}

class _WiederherstellenScreenState extends State<WiederherstellenScreen> {
  static const _count = 12;

  final _controllers = List.generate(_count, (_) => TextEditingController());
  final _nodes = List.generate(_count, (_) => FocusNode());
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  List<String> get _words => [for (final c in _controllers) c.text.trim()];

  bool get _complete => _words.every((w) => w.isNotEmpty);

  /// One box received something with a separator in it — a pasted phrase, or a word finished with
  /// a space. Lay the words out from this box onwards and put the cursor after the last one
  /// filled. Twelve words pasted into box 1 fill the screen; „bahn " typed into box 3 moves on to
  /// box 4. The same code does both, so neither is a path that only runs on someone else's phone.
  void _spread(int from, String raw) {
    final parts = raw.split(RegExp(r'[^a-zäöüß]+')).where((w) => w.isNotEmpty).toList();
    if (parts.isEmpty) {
      return;
    }
    var i = from;
    for (final word in parts) {
      if (i >= _count) break;
      _controllers[i].text = word;
      i++;
    }
    setState(() => _error = null);
    // After the frame, never inside the text-input callback that brought us here: moving focus
    // re-entrantly from an edit is the kind of thing that works until it does not.
    //
    // It is not a cure for one thing, and the limit is worth writing down. Keystrokes arriving
    // faster than the frame loop keep landing in the box focus is leaving, so a phrase injected
    // at machine speed comes out shredded across the boxes („zug gleis fahrplan" → „gleisa",
    // „f", „rplan"). Nothing a person does reaches that speed: a paste — the case this screen is
    // built around, and the one `wiederherstellen_test.dart` pins — arrives as a single edit and
    // is laid out in one pass, and a typed space has many frames behind it before the next
    // letter. Only `idb ui text` and friends can provoke it.
    final next = i;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Past the end of a full phrase there is nothing to focus, so the keyboard goes away.
      if (next >= _count) {
        FocusScope.of(context).unfocus();
      } else {
        _nodes[next].requestFocus();
      }
    });
  }

  void _onChanged(int i, String value) {
    if (RegExp(r'[ \n\t]').hasMatch(value)) {
      _spread(i, value);
      return;
    }
    if (_error != null) setState(() => _error = null);
    // The button turns on and off with the twelfth word.
    setState(() {});
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
      context.go(Routes.home);
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
      scroll: true,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          VPrimaryButton(
            label: 'Wiederherstellen',
            busy: _busy,
            onTap: _complete && !_busy ? _recover : null,
          ),
          const VGap.s(),
          VTintButton(
            label: 'Abbrechen',
            tone: VTintTone.neutral,
            onTap: () => context.canPop() ? context.pop() : context.go(Routes.welcome),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const VGap.m(),
          Text.rich(
            const TextSpan(
              children: [
                TextSpan(text: 'Konto ', style: TextStyle(color: VColors.ink)),
                TextSpan(text: 'wiederherstellen', style: TextStyle(color: VColors.red)),
              ],
            ),
            style: VText.h2,
            textAlign: TextAlign.center,
          ),
          const VGap.s(),
          Text(
            'Nutze diese Funktion nur, wenn du noch die zwölf Wiederherstellungswörter deines '
            'vorherigen Kontos kennst.',
            style: VText.bodyL.copyWith(color: VColors.ink2),
            textAlign: TextAlign.center,
          ),
          const VGap.l(),
          // Six rows of two rather than a GridView: the whole page already scrolls, and a grid
          // inside a scroll view is a second scrollable arguing with the first one.
          for (var row = 0; row < _count ~/ 2; row++) ...[
            Row(
              children: [
                Expanded(child: _buildWord(row * 2)),
                const SizedBox(width: VSpace.md),
                Expanded(child: _buildWord(row * 2 + 1)),
              ],
            ),
            const VGap.md(),
          ],
          if (_error != null) ...[
            const VGap.xs(),
            VNoteBanner(icon: Icons.error_outline, text: _error!),
          ],
          const VGap.s(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline, size: 22, color: VColors.ink3),
              const SizedBox(width: VSpace.md),
              Expanded(
                child: Text(
                  'Deine Wiederherstellungswörter bleiben bis zur Bestätigung ausschließlich auf '
                  'diesem Gerät.',
                  style: VText.bodyS,
                ),
              ),
            ],
          ),
          const VGap.m(),
        ],
      ),
    );
  }

  Widget _buildWord(int i) {
    final filled = _controllers[i].text.trim().isNotEmpty;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: VSpace.md),
      decoration: BoxDecoration(
        color: VColors.paperElevated,
        border: Border.all(color: filled ? VColors.hairlineStrong : VColors.hairline),
        borderRadius: BorderRadius.circular(VRadius.md),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text('${i + 1}', textAlign: TextAlign.right, style: VText.bodySStrong.copyWith(color: VColors.ink3)),
          ),
          const SizedBox(width: VSpace.md),
          Container(width: 1, height: 22, color: VColors.hairlineStrong),
          const SizedBox(width: VSpace.md),
          Expanded(
            child: TextField(
              controller: _controllers[i],
              focusNode: _nodes[i],
              onChanged: (v) => _onChanged(i, v),
              // The last box submits; the others walk on. A word typed with a space after it
              // walks on too, through `_spread`.
              textInputAction: i == _count - 1 ? TextInputAction.done : TextInputAction.next,
              onSubmitted: (_) {
                if (i < _count - 1) {
                  _nodes[i + 1].requestFocus();
                } else if (_complete && !_busy) {
                  _recover();
                }
              },
              inputFormatters: const [_WordInput()],
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              style: VText.bodyL.copyWith(color: VColors.ink),
              cursorColor: VColors.red,
              decoration: InputDecoration(
                hintText: 'Wort ${i + 1}',
                hintStyle: VText.bodyL.copyWith(color: VColors.ink3),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
