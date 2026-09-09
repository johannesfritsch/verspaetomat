// Antragsformular für Erstattungen und Entschädigungen nach VO (EU) 2021/782,
// rebuilt as a clean document. Content and section numbers follow the official form
// (Durchführungsverordnung (EU) 2024/949). Filled by the backend; signed by the customer.
#import sys: inputs
#let d = inputs.claim

#set page(paper: "a4", margin: (x: 20mm, top: 14mm, bottom: 14mm), numbering: "1 / 1", number-align: right)
#set text(font: ("Helvetica Neue", "Arial", "Liberation Sans", "Libertinus Serif"), size: 9pt, lang: "de")
#set par(leading: 0.55em)

#let box_(mark) = if mark [ *[X]* ] else [ [ ] ]
#let field(label, value) = block(above: 0pt, below: 0pt)[
  #text(size: 7.5pt, fill: rgb("#555555"))[#label] \
  #text(size: 10pt)[#value]
]
#let section(title) = block(above: 10pt, below: 5pt)[
  #text(weight: "bold", size: 10.5pt)[#title]
  #line(length: 100%, stroke: 0.6pt + black)
]

#align(center)[
  #text(weight: "bold", size: 13pt)[ANTRAGSFORMULAR FÜR ERSTATTUNGEN UND ENTSCHÄDIGUNGEN] \
  #text(size: 9pt)[gemäß der Verordnung (EU) 2021/782 des Europäischen Parlaments und des Rates]
]
#v(4pt)
#text(size: 8pt, fill: rgb("#555555"))[
  Übermittelt über Verspätomat, eine Ausfüll- und Weiterleitungshilfe. Antragsteller:in ist die unter 5 genannte Person.
  Vorgang #d.claim_id · erstellt am #d.created
]

#section("1. Grund/Gründe für Ihren Antrag")
#box_(d.delay) Verspätung #h(1.5em) #box_(d.cancellation) Ausfall #h(1.5em) #box_(false) Verpasster Anschluss aufgrund einer Verspätung oder eines Ausfalls

#section("3. Angaben zu Ihrer Fahrt")
#grid(columns: (1fr, 1fr), column-gutter: 12pt, row-gutter: 7pt,
  field("3.1 Name des Eisenbahnunternehmens", d.operator),
  field("3.2.6 / 3.3.4 Zugnummer / Zugkategorie", d.first.line),
  field("3.2.1 Abreisedatum", d.first.date),
  field("3.2.7 Fahrkartennummer(n) / Buchungsnummer", d.ticket_number),
  field("3.2.2 Abreisebahnhof", d.first.from),
  field("3.2.3 Zielbahnhof", d.first.to),
  field("3.2.5 Ankunftszeit am Zielort laut Fahrplan", d.first.planned),
  field("3.3.3 Tatsächliche Ankunftszeit am Zielort", d.first.actual),
)
#if d.incidents.len() > 1 [
  #text(size: 8pt, fill: rgb("#555555"))[Weitere Fahrten dieser Zeitfahrkarte siehe Abschnitt 6.]
]

#section("4. Art Ihres Antrags an das Eisenbahnunternehmen")
#box_(false) Erstattung der Fahrkarte(n) \
#box_(true) *Entschädigung durch das Eisenbahnunternehmen* \
#h(1.5em) #box_(d.kind == "60") für eine Verspätung bei der Ankunft am Zielort von 60 bis 119 Minuten \
#h(1.5em) #box_(d.kind == "120") für eine Verspätung bei der Ankunft am Zielort von mindestens 120 Minuten \
#h(1.5em) #box_(d.kind == "season") für wiederholte Verspätungen oder Ausfälle, die Fahrgäste betreffen, die Inhaber einer Zeitfahrkarte sind \
#box_(false) Erstattung der Kosten für die Inanspruchnahme anderer Anbieter von Verkehrsdiensten oder sonstige Kosten

#section("5. Angaben zur Person")
#grid(columns: (1fr, 1fr), column-gutter: 12pt, row-gutter: 7pt,
  field("5.1.1 Vorname / 5.1.2 Familienname", d.person.name),
  field("5.3.1 E-Mail-Adresse", d.person.email),
  field("5.2 Anschrift", d.person.address),
  field("5.3.2 Telefonnummer", "–"),
)
#v(7pt)
#field("5.4 Bevorzugte Auszahlungsform", [#box_(true) Geld #h(1.5em) #box_(false) Gutscheine und/oder andere Dienstleistungen])
#v(7pt)
#grid(columns: (1fr, 1fr), column-gutter: 12pt, row-gutter: 7pt,
  field("5.5.1 IBAN (Kontonummer)", d.payee.iban),
  field("5.5.4 Name des Kontoinhabers", text(weight: "bold")[#d.payee.holder]),
)
#text(size: 8pt, fill: rgb("#555555"))[
  Die Entschädigung ist an den oben genannten Kontoinhaber zu überweisen. Der Kontoinhaber ist eine gemeinnützige Organisation; die Zahlung erfolgt auf Wunsch des Fahrgastes direkt dorthin.
]

#section("6. Zusätzliche Angaben zu Ihrer Fahrkarte / Ihrer Fahrt")
#if d.incidents.len() > 1 [
  Wiederholte Verspätungen bzw. Ausfälle mit Zeitfahrkarte #d.ticket_type Nr. #d.ticket_number:
  #v(2pt)
  #table(
    columns: (auto, auto, 1fr, auto, auto, auto, auto),
    stroke: 0.4pt + rgb("#999999"),
    inset: 4pt,
    align: (left, left, left, right, right, right, right),
    text(size: 8pt, weight: "bold")[Datum], text(size: 8pt, weight: "bold")[Zug], text(size: 8pt, weight: "bold")[Strecke],
    text(size: 8pt, weight: "bold")[Plan], text(size: 8pt, weight: "bold")[Ist], text(size: 8pt, weight: "bold")[Verspätung], text(size: 8pt, weight: "bold")[Anspruch],
    ..d.incidents.map(i => (
      text(size: 8pt)[#i.date], text(size: 8pt)[#i.line], text(size: 8pt)[#i.from – #i.to],
      text(size: 8pt)[#i.planned], text(size: 8pt)[#i.actual], text(size: 8pt)[#i.delay Min#if i.cancelled [, Ausfall]], text(size: 8pt)[#i.amount],
    )).flatten()
  )
  #v(2pt)
  Summe: *#d.total* (#d.incidents.len() Fälle). Beträge unter 4 € werden gesammelt eingereicht.
] else [
  Fahrpreis #d.fare, Anspruch *#d.total*. #if d.first.self_entered [Ankunftszeit vom Fahrgast selbst eingetragen.]
]
#if d.notes != "" [ #v(4pt) #d.notes ]

#v(6pt)
#line(length: 100%, stroke: 0.6pt + black)
#v(2pt)
*Hiermit erkläre ich, dass alle in diesem Formular gemachten Angaben in jeder Hinsicht und für alle Fahrgäste der Wahrheit entsprechen und zutreffend sind.*
Ich erkläre, dass der Empfänger dieses Formulars meine personenbezogenen Daten erforderlichenfalls zum Zwecke der Bearbeitung meines Antrags weitergeben darf. #box_(true) JA

#v(8pt)
#grid(columns: (1fr, 1fr, 1fr, 1.3fr), column-gutter: 12pt,
  field("Datum der Antragstellung", d.signed_on),
  field("Ort der Antragstellung", d.place),
  field("Name des Fahrgastes", d.person.name),
  field("Unterschrift", if d.signature != none { box(height: 34pt)[#image(d.signature, height: 34pt)] } else { text(size: 8pt, fill: rgb("#555555"))[elektronisch, Name eingegeben] }),
)
