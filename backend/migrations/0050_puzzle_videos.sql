-- docs/51 §9b: a picture can be the first frame of a short video, the reward for the finished
-- picture. The video is a file on the upload volume (`puzzle-videos/<image id>-<sha8>.mp4`,
-- relative to UPLOAD_DIR, storage.rs), not a bytea: at a few megabytes each it would make every
-- pg_dump carry them, and it is served in ranges. All six are null for a picture without a video
-- (every picture before this), and set together.

alter table puzzle_images
    add column video_path     text,
    add column video_bytes    bigint,
    add column video_seconds  double precision,
    add column video_sha256   text,
    add column video_width    integer,
    add column video_height   integer,
    add constraint puzzle_images_video_whole check (
        (video_path is null) = (video_bytes is null) and (video_path is null) = (video_seconds is null)
        and (video_path is null) = (video_sha256 is null) and (video_path is null) = (video_width is null)
        and (video_path is null) = (video_height is null)
    );
