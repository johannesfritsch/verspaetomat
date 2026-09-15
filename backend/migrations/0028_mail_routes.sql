-- Where a claim mail is actually allowed to go.
--
-- Until now the destination was `operators.email`, seeded into every database from a fixture
-- compiled into the binary — so DB's real EU-form desk was in the code, in the image, and in the
-- database, on every machine, from the first boot. What stood between a rehearsal and a real
-- railway was one optional environment variable, `CLAIM_MAIL_REDIRECT`, which failed OPEN in at
-- least five ways: unset, empty, whitespace, no '@', or the variable name typed wrong. And two
-- other paths — answering an inbound mail, and `stellwerk mail-test` — never consulted it at all.
--
-- This table inverts that. A destination exists only if somebody wrote it here, by hand, on this
-- machine. No fixture seeds it, no migration inserts into it, nothing in the repository knows a
-- railway's address. An empty table means nothing can be sent, which is the right state for a
-- system that has never been told where to send.
--
-- `live` is a label, not a switch: it does not change behaviour, it records whether the operator
-- believes `to_address` is the railway's real desk or a stand-in. It exists so `stellwerk routes`
-- can print the answer to "where does this actually go" without anybody reading code.
create table mail_routes (
    desk       text primary key,          -- matches claims.desk, frozen on the claim when drafted
    to_address text not null,             -- where the mail actually goes. The only source.
    label      text not null,             -- what this represents, for the person reading the list
    live       boolean not null default false,
    note       text,
    updated_at timestamptz not null default now()
);

comment on table mail_routes is 'the only source of an outbound claim destination; empty means nothing can be sent';
comment on column mail_routes.to_address is 'the address mail is actually delivered to, shown to the passenger before sending';
comment on column mail_routes.live is 'the operator asserts this is the railway''s real desk; a label, not a switch';

-- The real desk address must not survive anywhere it could be read back as a destination. The
-- operator directory keeps its postal address and whether the desk takes e-mail at all, because
-- both are product facts; the address itself is now this table's business alone.
update operators set email = null;
