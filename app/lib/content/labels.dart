// Names that leave the house: what a ticket is called on the claim form and in the mail to
// the railway. One rule, used where an attachment is made and where an open draft is picked
// up again, so the same file is recognised as the one that is already there.

/// "2026-08" → "August 2026"
String monthLabel(String ym) {
  const months = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
  final parts = ym.split('-');
  if (parts.length != 2) return ym;
  final m = int.tryParse(parts[1]);
  if (m == null || m < 1 || m > 12) return ym;
  return '${months[m - 1]} ${parts[0]}';
}

/// The label of the ticket image for one month: "Ticket August 2026". A single ticket that
/// covers no month of its own — an Einzelfahrkarte — is just "Ticket".
String ticketLabel(String month) => month == 'Ticket' ? 'Ticket' : 'Ticket ${monthLabel(month)}';
