create table audit_log (
    id          bigserial primary key,
    entity      text not null,           -- ride | incident | claim | mail
    entity_id   uuid not null,
    from_status text,
    to_status   text not null,
    reason      text,
    at          timestamptz not null default now()
);
create index audit_entity_idx on audit_log (entity, entity_id);
