-- we create a different schema. it's assumed that we already have
-- a postgis extension enabled database, and OSM data for bucharest
-- imported. we will use said data to populate the parcel table with
-- a few test polygons. we'll use that data afterwards in our algorithm.
CREATE SCHEMA plan;
SET search_path = public, plan;
CREATE TABLE parcel (
    gid serial primary key,
    name text,
    way geometry(Geometry,4326)
);

CREATE INDEX parcel_index ON parcel USING gist (way);
CREATE TABLE road (
    gid serial primary key,
    name text,
    way geometry(LineString,4326)
);
CREATE INDEX road_index ON road USING gist (way);
