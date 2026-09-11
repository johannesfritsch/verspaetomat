# 28 — Der Bus, der ein Zug ist

Found 11 September 2026 (Johannes, looking for a connection he knew existed): *„Ich kann für heute
keine Verbindung von Kißlegg nach Aulendorf finden in der App, aber es gibt diese ganz sicher."*

He was right, and the app was wrong in the worst way available to it — not by saying „nichts
gefunden", but by confidently offering three changes through Memmingen for a journey that is one
direct ride of half an hour.

## What was happening

Kißlegg → Aulendorf runs on the Württembergische Allgäubahn, and that branch is on
**Schienenersatzverkehr**. A replacement does not get a bus number; it runs under the **line's own
number**. In the feed it looks like this:

```
mode:            BUS
routeShortName:  RB53
agencyName:      DB ZugBus Regionalverkehr Alb-Bodensee GmbH
headsign:        Bahnhof, Aulendorf
from.modes:      [REGIONAL_RAIL, BUS]
```

The planner asked Transitous for rail modes only. So the four direct RB 53 runs were filtered out
before the app ever saw them, and the router did what routers do when you delete the obvious
answer: it found a worse one. Neither end of the branch showed the line at all — Kißlegg listed
only the Bavarian services to Memmingen and Lindau, Aulendorf only the Ulm–Friedrichshafen axis.

## Why this was worse than a missing route

A replacement bus is part of the rail contract. The delay on it is claimable exactly like a
train's, and the app has carried a **Schienenersatzverkehr** badge since docs/12 for precisely
this case — „checked in to a replacement bus on a rail line". The product always intended to
cover these journeys.

So the one kind of journey most likely to go wrong, and most worth claiming, was the one kind the
app could not plan. A passenger standing at Kißlegg would conclude the app does not know the
German railway. They would be right to.

## The rule

Ask the planner for buses as well, then keep only the ones standing in for a train.

A city bus is `7`, `X41`, `N3`. A train is `RB 53`, `RE 96`, `S 12`. **A rail prefix plus a
number** is the signal, and it is the only honest one the feed offers — `is_rail_replacement` in
`train/mod.rs`. Anything else on wheels means the itinerary is not a rail journey and is dropped
whole, so an ordinary bus never becomes a leg.

Nothing downstream needed changing: `category_for` already reads the line prefix before the mode,
so `RB53` was always going to be a `Rb`. Points, the claim, and the desk follow from that.

## What is still missing, and is not ours

- **The intermediate stations on that branch have no timetable.** Bad Waldsee and Wolfegg exist in
  the OSM-derived feed as place markers with zero departures; the DELFI feed does not carry them.
  A check-in from Bad Waldsee itself will still fail. Upstream.
- **`stations/nearby` is tight.** At Kißlegg's exact coordinates it returns the station; 500 m
  away it returns nothing at all. Worth a look on its own — the far end of a long platform should
  not lose the station.

## Tests

- Unit: a bus called `RB 53` is a replacement, a bus called `7`, `X41` or `N3` is not, a bus with
  no number tells us nothing, and a train is not a replacement but the thing being replaced.
- By hand, on the route that started this: Kißlegg → Aulendorf now returns three direct RB 53
  runs where it returned three changes through Memmingen.
