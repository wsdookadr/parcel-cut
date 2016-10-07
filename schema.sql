-- we create a different schema. it's assumed that we already have
-- a postgis extension enabled database, and OSM data for bucharest
-- imported. we will use said data to populate the parcel table with
-- a few test polygons. we'll use that data afterwards in our algorithm.
CREATE SCHEMA plan;
SET search_path = public, plan;
CREATE TABLE parcel (
    gid serial primary key,
    name text,
    way geometry(Geometry,900913),
    -- will be true if this is a subdivision
    -- generated using corner-cutting. 
    pseudo boolean default false
);


CREATE INDEX parcel_index ON parcel USING gist (way);
CREATE TABLE road (
    gid serial primary key,
    name text,
    way geometry(LineString,900913)
);
CREATE INDEX road_index ON road USING gist (way);

-- we'll use this to store intermeddiary objects
-- (for development purposes)
CREATE TABLE support (
    gid serial primary key,
    name text,
    way geometry(Geometry,900913)
);
CREATE INDEX support_index ON support USING gist (way);
