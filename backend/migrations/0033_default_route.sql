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
