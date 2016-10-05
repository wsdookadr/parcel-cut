-- get a park from the OSM data to use as a test polygon.
-- we'll then run the algorithm on it (to cut pieces from it).
\copy (SELECT name, ST_Transform(way,4326) FROM planet_osm_polygon WHERE tags->'leisure'='park' AND name LIKE '%Herăstrău%') TO '/tmp/data.copy' DELIMITER ',' CSV HEADER;
SET search_path = public, plan;
\copy parcel (name, way) FROM '/tmp/data.copy' DELIMITER ',' CSV HEADER;
