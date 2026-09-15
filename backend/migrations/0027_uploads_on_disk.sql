-- Uploads become files. The bytea column said "object storage later" from the day it was written
-- (0008_claims.sql), and a photograph of a ticket is the day: a drawn PNG was forty kilobytes,
-- a phone photo is three megabytes, and every read pulled the whole blob through the API process
-- and every pg_dump carried it.
--
-- `path` is relative to UPLOAD_DIR, and it is the upload's own id. Rows written before this
-- migration keep their bytes and have no path; the reader prefers the file and falls back to the
-- column, so nothing has to be moved.
alter table uploads add column path text;
alter table uploads alter column bytes drop not null;

comment on column uploads.path is 'file under UPLOAD_DIR, named by the upload id; null for rows written before 0027';
comment on column uploads.bytes is 'legacy inline bytes; null for rows written after 0027, empty for rows cleared by retention';
