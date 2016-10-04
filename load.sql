-- get a park in our table, we'll use it as our test
-- polygon
\copy (SELECT name, ST_Transform(way,4326) FROM planet_osm_polygon WHERE tags->'leisure'='park' AND name LIKE '%Herăstrău%') TO '/tmp/data.copy' DELIMITER ',' CSV HEADER;
SET search_path = public, plan;
\copy parcel (name, way) FROM '/tmp/data.copy' DELIMITER ',' CSV HEADER;
