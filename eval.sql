--
-- this query evaluates parcel quality.
-- fill ratio of the parcel is how much of its convex
-- hull area the parcel covers.
--
-- the parcels with high fill ratio are better because
-- they're less likely to be thin.
--
-- the thinness measure is how close the shape is
-- to a square.
--
SELECT
parent_id,
area,
area_chull,
area/area_chull AS fill_ratio,
LEAST(width/height,height/width) AS thinness
FROM (
    -- only get the parcels created
    -- after partitioning the land.
    SELECT
    gid,
    parent_id,
    ST_Area(way) as area,
    ST_Area(ST_ConvexHull(way)) as area_chull,
    (ST_XMax(way)-ST_XMin(way)) as width,
    (ST_YMax(way)-ST_YMin(way)) as height
    FROM  parcel
    WHERE pseudo = true
    ORDER BY gid
) a
ORDER BY fill_ratio ASC;


-- compute leftover area after partitioning
-- and coverage ratio for each partitioned polygon.
SELECT
pids.pid AS pid,
parent.area AS leftover,
covered.area / (covered.area + parent.area) AS coverage
FROM (
    -- get all distinct parent ids, in other words
    -- the ids for the polygons that have been
    -- partitioned
    SELECT
    DISTINCT ON(parent_id)
    parent_id AS pid
    FROM parcel
    WHERE pseudo = true
) pids,
LATERAL (
    SELECT
    SUM(ST_Area(way)) AS area
    FROM parcel
    WHERE parcel.parent_id = pids.pid
) covered,
LATERAL (
    SELECT
    ST_Area(way) AS area
    FROM parcel
    WHERE gid = pids.pid
) parent;

--
-- find overlapping parcels (there should be none)
--
WITH X AS (
    SELECT
    *
    FROM parcel
    WHERE pseudo = false
)
SELECT a.gid, b.gid
FROM X a
JOIN X b
ON  ST_Overlaps(a.way,b.way)
AND ST_AsText(a.way) <> ST_AsText(b.way);






