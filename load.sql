-- this program gets some land areas(polygons) from the OSM dataset
-- and a some roads near them.
-- 
-- we fill the tables `road` and `parcel` so they can later be used
-- for testing the cutting algorithm in cut.sql
SET search_path = public, plan;
CREATE TEMP VIEW parcels_v AS (
    SELECT
    name, way
    FROM planet_osm_polygon
    WHERE tags->'leisure'='park'
    AND name LIKE '%Herăstrău%'
    ORDER BY ST_Area(way) DESC
    LIMIT 4
);

CREATE TEMP VIEW roads_v AS (
    WITH roads AS (
        SELECT
        osm_id, name, way
        FROM planet_osm_line
        WHERE tags ? 'highway'
        AND tags->'highway' IN ('motorway','trunk','primary')
    )
    -- do KNN cross-join between parcels and roads
    -- to get nearby roads (rn), deduplicate the roads
    -- and insert them into the `road` table.
    SELECT
    DISTINCT ON (rn.osm_id)
    rn.name, rn.way
    FROM parcels_v p
    CROSS JOIN LATERAL (
        -- get 10 closest roads to each parcel
        SELECT
        *,
        -- distance to road
        ST_Distance(p.way,r.way) as dr
        FROM roads r
        ORDER BY p.way <-> r.way
        LIMIT 10
    ) rn
);

SET search_path = public, pg_catalog;
\copy (SELECT name, way AS way FROM parcels_v) TO '/tmp/parcels.copy' DELIMITER ',' CSV HEADER;
\copy (SELECT name, way AS way FROM   roads_v) TO '/tmp/roads.copy'   DELIMITER ',' CSV HEADER;

SET search_path = public, plan;
TRUNCATE parcel RESTART IDENTITY;
TRUNCATE road   RESTART IDENTITY;
\copy parcel (name, way) FROM '/tmp/parcels.copy' DELIMITER ',' CSV HEADER;
\copy road   (name, way) FROM '/tmp/roads.copy'   DELIMITER ',' CSV HEADER;

TRUNCATE support RESTART IDENTITY;
