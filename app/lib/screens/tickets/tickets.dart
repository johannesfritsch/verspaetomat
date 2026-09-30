import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../repo/repo_scope.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit.dart';
import '../community/community_widgets.dart' show SwitchRow;
import '../ride/ride_widgets.dart' show shortError;

// Tickets (#66, docs/49 §5.3, docs/50 phase 3): the passenger's own tickets, adding one, changing
// one. Every sentence about what a ticket is owed comes from the catalogue (`GET /v1/fares`); the
// app only names the families and asks for the fields the catalogue says a product needs.

/// How the app names a family of tickets, and the mark it gives it.
class TicketFamily {
  const TicketFamily(this.id, this.label, this.icon, {this.question, this.note});
  final String id;
  final String label;
  final IconData icon;

  /// For a family with several products: the second question ("Welcher Verbund?").
  final String? question;

  /// A quiet line under the family where the catalogue has no single sentence for it.
  final String? note;

  static const all = <TicketFamily>[
    TicketFamily('deutschlandticket', 'Deutschlandticket', Icons.confirmation_number_outlined, note: 'Auch als Job-, Semester- oder Sozialticket'),
    TicketFamily('bahncard100', 'BahnCard 100', Icons.credit_card),
    TicketFamily('zeitkarte', 'Monats- oder Jahreskarte', Icons.badge_outlined, question: 'Welcher Verbund?', note: 'Von deinem Verkehrsverbund'),
    TicketFamily('streckenzeitkarte', 'Streckenzeitkarte ICE oder IC', Icons.linear_scale),
    TicketFamily('laender_ticket', 'Länder-Ticket', Icons.map_outlined, note: 'Oder Quer-durchs-Land'),
    TicketFamily('einzelfahrkarte', 'Einzelfahrkarte', Icons.receipt_long_outlined, question: 'Wo gekauft?', note: 'Flexpreis, Sparpreis oder Nahverkehr'),
  ];

  static TicketFamily of(String id) => all.firstWhere((f) => f.id == id, orElse: () => TicketFamily(id, id, Icons.confirmation_number_outlined));
}

/// What a ticket still lacks before a claim can use it, in one line. Null: nothing.
String? ticketMissing(ApiTicket t, ApiFare? fare) {
  if (t.productUnsure) return t.family == 'streckenzeitkarte' ? 'Strecke und Preis fehlen noch' : 'Welcher Verbund? Bitte angeben.';
  if ((fare?.fields.priceRequired ?? false) && t.priceCents == null) return 'Fahrpreis fehlt';
  return null;
}

/// „63" or „63,00" or „63.5" → cents. Null for anything else.
int? parseEuro(String s) {
  final t = s.trim().replaceAll('€', '').replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  return v == null || v < 0 ? null : (v * 100).round();
}

String euroText(int cents) => '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';

/// For reading, not for a field: „4.899,00".
String euroDisplay(int cents) {
  final whole = (cents ~/ 100).toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '$whole,${(cents % 100).toString().padLeft(2, '0')}';
}

String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

String numberLabel(String kind) => switch (kind) {
  'abo' => 'Abo-Nummer',
  'zeitkarte' => 'Kartennummer',
  'bahncard' => 'BahnCard-Nr.',
  _ => 'Auftragsnr.',
};

/// The catalogue and the passenger's tickets, loaded together.
class TicketBook {
  const TicketBook(this.fares, this.tickets);
  final ApiFares fares;
  final List<ApiTicket> tickets;

  static Future<TicketBook> load(BuildContext context, {bool all = false}) async {
    final repo = RepoScope.read(context).repo;
    final results = await Future.wait([repo.fares(), repo.tickets(all: all)]);
    return TicketBook(results[0] as ApiFares, results[1] as List<ApiTicket>);
  }
}

/// „Fahrkarte hinzufügen": the family, then (where a family has several) the product, then its
/// form. Returns the new ticket, or null when the passenger backed out. With [single] false, the
/// single ticket is left out: that one belongs to a journey, not to the list of one's tickets.
Future<ApiTicket?> addTicket(BuildContext context, {bool single = false}) {
  return Navigator.of(context, rootNavigator: true).push<ApiTicket>(MaterialPageRoute(builder: (_) => _WelcheFahrkarte(single: single)));
}

/// Opens one ticket to change it. Returns the changed ticket, or null.
Future<ApiTicket?> editTicket(BuildContext context, ApiTicket ticket, ApiFares fares) {
  final fare = fares.byId(ticket.product);
  if (fare == null) return Future.value(null);
  return Navigator.of(context, rootNavigator: true).push<ApiTicket>(
    MaterialPageRoute(
      builder: (_) => FahrkarteScreen(fare: fare, fares: fares, ticket: ticket),
    ),
  );
}

/// „Deine Fahrkarten" (Einstellungen → Fahrkarten).
class FahrkartenScreen extends StatefulWidget {
  const FahrkartenScreen({super.key});

  @override
  State<FahrkartenScreen> createState() => _FahrkartenScreenState();
}

class _FahrkartenScreenState extends State<FahrkartenScreen> {
  TicketBook? _book;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final b = await TicketBook.load(context);
      if (mounted) setState(() => _book = b);
    } catch (e) {
      if (mounted) setState(() => _error = 'Fahrkarten nicht geladen: ${shortError(e)}');
    }
  }

  Future<void> _add() async {
    final t = await addTicket(context);
    if (t != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    return VScreen(
      eyebrow: 'Einstellungen',
      title: 'Deine Fahrkarten',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const VGap.xs(),
          Text('Was eine Verspätung wert ist, hängt an der Fahrkarte. Beim Einchecken wählst du eine davon.', style: VText.body.copyWith(color: VColors.ink2)),
          const VGap.m(),
          if (_error != null) Text(_error!, style: VText.bodyS.copyWith(color: VColors.red)),
          if (book == null && _error == null) const VSkeletonCard(),
          if (book != null && book.tickets.isEmpty)
            VCard(
              child: Text('Noch keine. Die erste legst du hier an oder beim nächsten Einchecken.', style: VText.body.copyWith(color: VColors.ink2)),
            ),
          if (book != null && book.tickets.isNotEmpty)
            VCard(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.cardTight),
              child: Column(
                children: [
                  for (final (i, t) in book.tickets.indexed)
                    VOptionRow(
                      key: Key('fahrkarte-${t.id}'),
                      leading: VIconBadge(icon: TicketFamily.of(t.family).icon, tone: VBadgeTone.neutral, size: VControl.badgeSmall, iconColor: VColors.ink2),
                      title: t.name,
                      subtitle: ticketMissing(t, book.fares.byId(t.product)) ?? t.ruleLine,
                      divider: i < book.tickets.length - 1,
                      onTap: () async {
                        await editTicket(context, t, book.fares);
                        if (mounted) await _load();
                      },
                    ),
                ],
              ),
            ),
          const VGap.m(),
          VTintButton(key: const Key('fahrkarte-neu'), label: 'Fahrkarte hinzufügen', icon: Icons.add, onTap: _add),
        ],
      ),
    );
  }
}

/// „Welche Fahrkarte?": the families, and for a family with several products the second question.
class _WelcheFahrkarte extends StatefulWidget {
  const _WelcheFahrkarte({required this.single});
  final bool single;

  @override
  State<_WelcheFahrkarte> createState() => _WelcheFahrkarteState();
}

class _WelcheFahrkarteState extends State<_WelcheFahrkarte> {
  ApiFares? _fares;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final f = await RepoScope.read(context).repo.fares();
        if (mounted) setState(() => _fares = f);
      } catch (e) {
        if (mounted) setState(() => _error = 'Fahrkarten nicht geladen: ${shortError(e)}');
      }
    });
  }

  Future<void> _pick(TicketFamily family, List<ApiFare> products) async {
    final fares = _fares!;
    final ApiFare? fare = products.length == 1 ? products.first : await pickProduct(context, family, products);
    if (fare == null || !mounted) return;
    final t = await Navigator.of(context).push<ApiTicket>(
      MaterialPageRoute(
        builder: (_) => FahrkarteScreen(fare: fare, fares: fares),
      ),
    );
    if (t != null && mounted) Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    final fares = _fares;
    final families = [
      for (final f in TicketFamily.all)
        if (fares != null && fares.inFamily(f.id).isNotEmpty && (widget.single || f.id != 'einzelfahrkarte')) f,
    ];
    return VScreen(
      eyebrow: 'Fahrkarte hinzufügen',
      title: 'Welche Fahrkarte?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const VGap.m(),
          if (_error != null) Text(_error!, style: VText.bodyS.copyWith(color: VColors.red)),
          if (fares == null && _error == null) const VSkeletonCard(),
          if (fares != null)
            VCard(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.cardTight),
              child: Column(
                children: [
                  for (final (i, f) in families.indexed)
                    () {
                      final products = fares.inFamily(f.id);
                      return VOptionRow(
                        key: Key('familie-${f.id}'),
                        leading: VIconBadge(icon: f.icon, tone: VBadgeTone.neutral, size: VControl.badgeSmall, iconColor: VColors.ink2),
                        title: f.label,
                        subtitle: products.length == 1 ? products.first.ruleLine : f.note,
                        divider: i < families.length - 1,
                        onTap: () => _pick(f, products),
                      );
                    }(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The second question of a family with several products: which Verbund, where bought.
Future<ApiFare?> pickProduct(BuildContext context, TicketFamily family, List<ApiFare> products) {
  // The standard text first is the wrong way round for a list someone scans for their own
  // Verbund; it goes last, as „Anderer Verbund".
  final sorted = [...products]..sort((a, b) => (a.id.endsWith('_spnv') ? 1 : 0).compareTo(b.id.endsWith('_spnv') ? 1 : 0));
  return showVSheet<ApiFare>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.only(bottom: VSpace.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VSheetHeader(title: family.question ?? family.label),
          const VGap.s(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VSpace.page),
            child: VCard(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.cardTight),
              child: Column(
                children: [
                  for (final (i, p) in sorted.indexed)
                    VOptionRow(key: Key('produkt-${p.id}'), title: p.name, subtitle: p.ruleLine, divider: i < sorted.length - 1, onTap: () => Navigator.of(ctx).pop(p)),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// One ticket: add it, or change it. Asks only for what the catalogue says this product needs.
class FahrkarteScreen extends StatefulWidget {
  const FahrkarteScreen({super.key, required this.fare, required this.fares, this.ticket});
  final ApiFare fare;
  final ApiFares fares;
  final ApiTicket? ticket;

  @override
  State<FahrkarteScreen> createState() => _FahrkarteScreenState();
}

class _FahrkarteScreenState extends State<FahrkarteScreen> {
  late ApiFare _fare = widget.fare;
  late final _label = TextEditingController(text: widget.ticket?.label ?? '');
  late final _number = TextEditingController(text: widget.ticket?.number ?? '');
  late final _price = TextEditingController(text: widget.ticket?.priceCents == null ? '' : euroText(widget.ticket!.priceCents!));
  late final _from = TextEditingController(text: widget.ticket?.originStationName ?? '');
  late final _to = TextEditingController(text: widget.ticket?.destinationStationName ?? '');
  late bool _first = widget.ticket?.firstClass ?? false;
  late DateTime? _validFrom = widget.ticket?.validFrom;
  late DateTime? _validUntil = widget.ticket?.validUntil;
  late DateTime? _birth = widget.ticket?.birthDate;
  late bool _unsure = widget.ticket?.productUnsure ?? false;
  bool _busy = false;
  String? _error;

  List<ApiFare> get _siblings => widget.fares.inFamily(_fare.family);

  @override
  void dispose() {
    for (final c in [_label, _number, _price, _from, _to]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _invalid() {
    if (_price.text.trim().isNotEmpty && parseEuro(_price.text) == null) return 'Der Preis ist keine Zahl.';
    if (_validFrom != null && _validUntil != null && _validUntil!.isBefore(_validFrom!)) return '„Gültig bis" liegt vor „Gültig ab".';
    return null;
  }

  Future<void> _save() async {
    final wrong = _invalid();
    if (wrong != null) {
      setState(() => _error = wrong);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    String? text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final validity = _fare.fields.validity;
    final input = TicketInput(
      product: _fare.id,
      firstClass: _first,
      label: text(_label),
      number: _fare.fields.number == 'none' ? null : text(_number),
      priceCents: parseEuro(_price.text),
      validFrom: validity == 'none' ? null : _validFrom,
      validUntil: validity == 'range' ? _validUntil : (validity == 'day' ? _validFrom : null),
      birthDate: _fare.fields.birthDate ? _birth : null,
      originStationName: _fare.fields.route ? text(_from) : null,
      destinationStationName: _fare.fields.route ? text(_to) : null,
    );
    try {
      final repo = RepoScope.read(context).repo;
      final saved = widget.ticket == null ? await repo.createTicket(input) : await repo.updateTicket(widget.ticket!.id, input);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Nicht gespeichert: ${shortError(e)}';
        });
      }
    }
  }

  Future<void> _archive() async {
    final t = widget.ticket;
    if (t == null) return;
    setState(() => _busy = true);
    try {
      await RepoScope.read(context).repo.archiveTicket(t.id);
      if (mounted) Navigator.of(context).pop(t);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Nicht möglich: ${shortError(e)}';
        });
      }
    }
  }

  Future<DateTime?> _date(DateTime? current, {DateTime? first, DateTime? last}) {
    final now = DateTime.now();
    return showDatePicker(context: context, initialDate: current ?? now, firstDate: first ?? DateTime(now.year - 3), lastDate: last ?? DateTime(now.year + 3));
  }

  @override
  Widget build(BuildContext context) {
    final f = _fare.fields;
    final family = TicketFamily.of(_fare.family);
    final priceHint = f.priceRequired ? 'Was du bezahlt hast, in Euro' : (_fare.listPriceCents != null ? 'Optional · sonst ${euroDisplay(_fare.listPriceCents!)} €' : 'Optional');
    return VScreen(
      eyebrow: widget.ticket == null ? 'Fahrkarte hinzufügen' : 'Deine Fahrkarte',
      title: _fare.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const VGap.xs(),
          Text(_fare.ruleLine, style: VText.body.copyWith(color: VColors.ink2)),
          if (_fare.caveat != null) ...[const VGap.s(), Text(_fare.caveat!, style: VText.bodyS.copyWith(color: VColors.ink2))],
          const VGap.m(),
          if (_siblings.length > 1)
            VCard(
              padding: const EdgeInsets.symmetric(horizontal: VSpace.cardTight),
              child: VOptionRow(
                key: const Key('fahrkarte-produkt'),
                title: _unsure ? (family.question ?? 'Welche?') : _fare.name,
                subtitle: _unsure ? 'Noch nicht angegeben' : _fare.tariff,
                divider: false,
                onTap: () async {
                  final p = await pickProduct(context, family, _siblings);
                  if (p != null && mounted) {
                    setState(() {
                      _fare = p;
                      _unsure = false;
                    });
                  }
                },
              ),
            ),
          if (_siblings.length > 1) const VGap.s(),
          VCard(
            child: Column(
              children: [
                if (f.number != 'none') ...[TicketField(key: const Key('fahrkarte-nummer'), label: numberLabel(f.number), hint: 'Optional', controller: _number, mono: true), const VDivider()],
                TicketField(
                  key: const Key('fahrkarte-preis'),
                  label: f.priceRequired ? 'Fahrpreis' : 'Preis',
                  hint: priceHint,
                  controller: _price,
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                  suffix: '€',
                ),
                if (f.validity != 'none') ...[
                  const VDivider(),
                  TicketDateRow(
                    label: f.validity == 'day' ? 'Gültig am' : 'Gültig ab',
                    value: _validFrom,
                    onTap: () async {
                      final d = await _date(_validFrom);
                      if (d != null) setState(() => _validFrom = d);
                    },
                  ),
                ],
                if (f.validity == 'range') ...[
                  const VDivider(),
                  TicketDateRow(
                    label: 'Gültig bis',
                    value: _validUntil,
                    onTap: () async {
                      final d = await _date(_validUntil ?? _validFrom);
                      if (d != null) setState(() => _validUntil = d);
                    },
                  ),
                ],
                if (f.birthDate) ...[
                  const VDivider(),
                  TicketDateRow(
                    label: 'Geburtsdatum',
                    hint: 'Steht auf der BahnCard',
                    value: _birth,
                    onTap: () async {
                      final d = await _date(_birth ?? DateTime(1990), first: DateTime(1900), last: DateTime.now());
                      if (d != null) setState(() => _birth = d);
                    },
                  ),
                ],
                if (f.route) ...[
                  const VDivider(),
                  TicketField(label: 'Von', hint: 'Bahnhof', controller: _from, capitalization: TextCapitalization.words),
                  const VDivider(),
                  TicketField(label: 'Nach', hint: 'Bahnhof', controller: _to, capitalization: TextCapitalization.words),
                ],
                const VDivider(),
                TicketField(label: 'Name', hint: 'Optional, z. B. „Arbeitsweg"', controller: _label, capitalization: TextCapitalization.sentences),
              ],
            ),
          ),
          if (f.firstClass) ...[
            const VGap.s(),
            VCard(
              child: SwitchRow(title: '1. Klasse', value: _first, divider: false, onChanged: (v) => setState(() => _first = v)),
            ),
          ],
          if (_error != null) ...[const VGap.s(), Text(_error!, style: VText.bodyS.copyWith(color: VColors.red))],
          const VGap.l(),
          VPrimaryButton(key: const Key('fahrkarte-speichern'), label: 'Speichern', busy: _busy, onTap: _busy || _unsure ? null : _save),
          if (widget.ticket != null) ...[const VGap.s(), VGhostButton(label: 'Nicht mehr in Gebrauch', onTap: _busy ? null : _archive)],
        ],
      ),
    );
  }
}

/// A labelled field in the style of the Antrag's „Deine Angaben".
class TicketField extends StatelessWidget {
  const TicketField({super.key, required this.label, required this.hint, required this.controller, this.keyboard, this.capitalization = TextCapitalization.none, this.mono = false, this.suffix});
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboard;
  final TextCapitalization capitalization;
  final bool mono;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VSpace.s),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(label, style: VText.bodyS.copyWith(color: VColors.ink2)),
              ),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboard,
                textCapitalization: capitalization,
                style: mono ? VText.mono : VText.bodySStrong,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: VText.bodyS.copyWith(color: VColors.ink3),
                  suffixText: suffix,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A date in the same row shape as [TicketField]; tapping opens the picker.
class TicketDateRow extends StatelessWidget {
  const TicketDateRow({super.key, required this.label, required this.value, required this.onTap, this.hint = 'Optional'});
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: VSpace.s),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: VControl.touch - 2 * VSpace.s),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(label, style: VText.bodyS.copyWith(color: VColors.ink2)),
              ),
              Expanded(
                child: Text(value == null ? hint : _dmy(value!), style: value == null ? VText.bodyS.copyWith(color: VColors.ink3) : VText.bodySStrong),
              ),
              const Icon(Icons.calendar_today_outlined, size: 18, color: VColors.ink3),
            ],
          ),
        ),
      ),
    );
  }
}
