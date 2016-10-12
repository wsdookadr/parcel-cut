-- this query evaluates how thin
-- the parcels area. fill ratio of the parcel
-- is how much of its convex hull area the parcel covers.
-- the parcels with high fill ratio are better because
-- they're less likely to be thin.
--
-- the thinness measure is how close the shape is
-- to a square.
-- 
SELECT
area,
area_chull,
area/area_chull AS fill_ratio,
LEAST(width/height,height/width) AS thinness
FROM (
    -- only get the parcels created
    -- after partitioning the land.
    SELECT
    gid,
    ST_Area(way) as area,
    ST_Area(ST_ConvexHull(way)) as area_chull,
    (ST_XMax(way)-ST_XMin(way)) as width,
    (ST_YMax(way)-ST_YMin(way)) as height
    FROM  parcel
    WHERE pseudo = true
    ORDER BY gid
) a
ORDER BY fill_ratio ASC;
