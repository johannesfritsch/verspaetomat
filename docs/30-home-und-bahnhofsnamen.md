# 30 — Wir zuerst, und ein Bahnhof mit zwei Namen

Decided 11 September 2026 (Johannes, from build 18 on a real phone). Three small things, one of
which reverses an earlier decision on purpose.

## 1. „Ab Kißlegg" stood on the card twice

The away box — the one that asks „Von wo fährst du los?" when you are not at a station — merges
two lists: the **frequent stations** from this person's ride history (`GET /v1/me/geofence`) and
the **nearby** ones from the feed. It deduplicated them by exact id, or failing that by exact name.

Neither holds. One platform has an id per feed, as docs/28 found out the hard way; and the two
sources spell it differently — „Kißlegg Bahnhof" here, „Kißlegg" there, and a ride checked in
months ago carries whatever it was called then. So the same station arrived twice and the card
offered it twice.

`sameStation(a, b)` in `ride_widgets.dart` is the test to use wherever two lists of stations
meet: normalise (which already folds `Hauptbahnhof` to `Hbf`, drops parentheses and commas), then
allow one name to be the other plus the word for the thing itself — `Bahnhof`, `Bf`, `Hbf`. So
Kißlegg is Kißlegg Bahnhof and Köln Hbf is Köln Hauptbahnhof, while Köln Hbf is still not Köln
Messe/Deutz and Düsseldorf Hbf is still not Düsseldorf Flughafen.

Note what the tour cannot tell us here: in Demo mode both lists come from the same mock ids, so
they never collided and the duplicate never appeared. The rule has unit tests; the confirmation
is on a platform.

## 2. Wir goes to the top of Home

Home now reads: **Wir · Einchecken · Deine Woche.**

This reverses docs/16 §1, which put the action first — „the action for this moment", everything
above the fold. The reason to reverse it: the collective number is what the app is *for*, and it
is true whether or not anybody is travelling this minute. The check-in card is only the most
useful thing on the screen when you happen to be standing on a platform.

It costs a scroll to reach Einchecken when you are on one. That is the trade, made knowingly.

## 3. „Deine Woche" wears the same box as „Wir"

Two blocks that say the same kind of thing should look the same. Deine Woche was bare text beside
a bordered box; it is now the box: elevated paper, a hairline, the number as the hero, one quiet
line under it, and a bar.

One honest limit of that bar: it is scaled against the better of this week and last, so the
better week always fills the track completely. It reads „this week against last week" only if you
also read the caption. Wir's bar means something exact — your share of the whole — and this one
does not yet. Worth revisiting if it bothers anyone; noted rather than left to be discovered.

## Tests

- `test/same_station_test.dart`: both directions of the `Bahnhof` tail, and the pairs that must
  stay apart.
- Tour: `bahnsteig-deine-woche`, a scrolled shot, because the section that changed sits below the
  fold and an unphotographed change is an unchecked one.
