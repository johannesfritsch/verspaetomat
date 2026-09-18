-- `live` stopped being a label (#25).
--
-- Migration 0028 wrote it down as one — "it does not change behaviour, it records whether the
-- operator believes to_address is the railway's real desk" — and that is exactly what made a
-- Probelauf impossible to trust: the mail went out either way and only the subject line said
-- otherwise. It is now the one switch that decides delivery. A route that is not live sends
-- nothing at all; the claim is still built, recorded and shown, and the app says afterwards what
-- would have followed.
comment on column mail_routes.live is
  'whether mail really leaves for this route: true sends, false records the claim and sends nothing';
