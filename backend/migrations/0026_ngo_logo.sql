-- docs/27 §5: the NGO's own mark, printed on a shared ticket beside its name. The partners have
-- agreed to be named and shown, and we use the logo as it stands rather than redrawing it.
--
-- Stored as a `data:image/…;base64,…` URI rather than a URL on purpose: the share card is
-- rendered on the phone and must work without a network, there is nowhere to host image files
-- yet, and hotlinking a partner's own server for something we print is not a thing to do. A few
-- kilobytes per NGO travels fine with the data that is already fetched.
alter table ngos add column logo text;
