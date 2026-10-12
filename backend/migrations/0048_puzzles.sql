-- docs/51: puzzles. A Verein sends pictures of its work; every finished journey brings one piece
-- of one of them, preferably from a Verein the passenger supports. The pictures live here rather
-- than on the volume because the nightly pg_dump then takes them along, and there are a few dozen
-- of them, not thousands. Nothing in here carries image data: pictures arrive through the
-- Stellwerk (`stellwerk ngo image add`), never through a migration or a fixture.

create table puzzle_images (
    id            uuid primary key,
    ngo_id        text not null references ngos(id),
    title         text not null,
    -- One sentence on what the picture shows; the app prints it under the finished picture.
    caption       text not null default '',
    -- The grid. A piece is numbered row by row from the top left: row * cols + col.
    rows          integer not null check (rows between 2 and 8),
    cols          integer not null check (cols between 2 and 8),
    -- The tier of every slot, row by row (docs/51 §2a): `minute`, `quarter` or `hour`. Fixed at
    -- upload — the hours in the middle, the quarters scattered — so the picture waits for the same
    -- rare pieces on every phone.
    tiers         text[] not null,
    content_type  text not null check (content_type in ('image/jpeg', 'image/png', 'image/webp')),
    -- At most 1 MB; the admin route checks it and the magic bytes before anything is stored.
    bytes         bytea not null,
    width         integer not null check (width > 0),
    height        integer not null check (height > 0),
    -- Hex digest of `bytes`, served as the ETag. A picture never changes; a new one gets a new id.
    sha256        text not null,
    -- Out of the distribution. Whoever already has pieces of it keeps it and can still finish it.
    retired_at    timestamptz,
    created_at    timestamptz not null default now(),
    check (cardinality(tiers) = rows * cols and tiers <@ array['minute', 'quarter', 'hour'])
);
create index puzzle_images_ngo_idx on puzzle_images (ngo_id, created_at);

-- Which pieces a passenger holds. A piece is never taken away (docs/51 §3): deleting the journey
-- that brought it leaves it, so `journey_id` only forgets the journey. Deleting the account takes
-- the pieces with it, like everything else the customer owns.
create table puzzle_pieces (
    customer_id  uuid not null references customers(id) on delete cascade,
    -- No cascade: an image with pieces awarded is retired, never deleted.
    image_id     uuid not null references puzzle_images(id),
    piece        integer not null check (piece >= 0 and piece < 64),
    -- One journey, at most one piece: a second finish of the same journey brings nothing.
    journey_id   uuid unique references journeys(id) on delete set null,
    -- Whether the picture's Verein was one of the passenger's own when the piece came: the one
    -- chosen then, or one a case or claim of theirs went to. A fact of that moment, kept as it was.
    own_cause    boolean not null default false,
    awarded_at   timestamptz not null,
    primary key (customer_id, image_id, piece)
);
-- The daily cap counts a customer's pieces of one Berlin day.
create index puzzle_pieces_customer_idx on puzzle_pieces (customer_id, awarded_at);
create index puzzle_pieces_image_idx on puzzle_pieces (image_id);
