-- The catch-all route (#25).
--
-- A desk with no route of its own falls back to the row keyed '*'. No DDL is needed — it is an
-- ordinary row in mail_routes — so this migration only writes the reservation down where the next
-- person reading the schema will find it. The key is safe: mail_routes.desk is matched against the
-- desk string frozen onto a claim, which comes from operators.desk, and no operator can be filed
-- under '*'.
--
-- What has not changed: no fixture and no migration inserts a destination, and no environment
-- variable can name one. A route exists because somebody typed it with `stellwerk route set` or
-- `stellwerk route default`, or nothing is sent.
comment on column mail_routes.desk is
  'the desk a claim was filed under, or ''*'': the catch-all every desk without its own route uses';

-- `live` is no longer a label (#25). Migration 0028 wrote it down as one — "it does not change
-- behaviour, it records whether the operator believes to_address is the railway's real desk" — and
-- that is what made a Probelauf untrustworthy: the mail went out either way and only the subject
-- line said otherwise. It is now the one switch that decides delivery. A route that is not live
-- sends nothing at all; the claim is still built, recorded and shown, and the app says what would
-- have followed.
comment on column mail_routes.live is
  'whether mail really leaves for this route: true sends, false records the claim and sends nothing';
