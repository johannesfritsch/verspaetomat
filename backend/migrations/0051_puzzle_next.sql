-- docs/51 §9c: the Stellwerk can pin the picture the next journey's piece goes to, so testing a
-- rare piece is not a roll of the dice (one piece in four goes to another Verein). One-shot: the
-- next award reads it and clears it, whether the picture had a slot for that journey or not.
-- Refused in production like every call that simulates the world.

alter table customers add column puzzle_next_image uuid references puzzle_images(id) on delete set null;
