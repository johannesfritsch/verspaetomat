-- Routing has no notion of a rehearsal any more (#25).
--
-- `live` was meant to record whether an address was the railway's real desk. It never earned that:
-- first it changed nothing but a subject line, then briefly it decided delivery. Both were the same
-- mistake — a demo is a thing the app does, not a property of a destination. The server now has one
-- job here: a desk has an address and mail goes to it. What the passenger is walking through, a
-- real claim or the walkthrough, is decided in the app, which simply does not send in its demo.
alter table mail_routes drop column live;

comment on table mail_routes is
  'the only source of an outbound claim destination; empty means nothing can be sent';
