-- this block will set some flags, and supress unneeded output
-- from the output. this is the workbench program where most development
-- will be carried out and we want to output an SVG from here.
\set QUIET 1
\a
-- turn off footer
\pset footer off
-- turn off column names
\pset tuples_only
-- turn off any more verbose output from psql
\pset pager off
SET search_path = public, plan;
\set QUIET 0

\set QUIET 1
-- this function draws all available parcels as a SVG
DROP FUNCTION parcels_draw();
CREATE OR REPLACE FUNCTION parcels_draw() RETURNS text AS $$
DECLARE
retval text;
BEGIN
    retval := (
        WITH a AS (
            -- unions together all the objects
            -- we want to draw
            SELECT
            name, way, 'support' AS _type
            FROM support
            UNION ALL
            SELECT
            name, way, 'parcel' AS _type
            FROM parcel
            UNION ALL
            SELECT
            name, way, 'road' AS _type
            FROM road
        ), d AS (
            -- get bounding box of all shapes
            -- as it will be later used for the svg viewport
            SELECT
            ST_Envelope(ST_Collect(way)) env
            FROM a
        ), c AS (
            SELECT
            ST_Centroid(env) AS w
            FROM d
        ), e AS (
            SELECT
            string_agg(path,'') AS paths
            FROM (
                -- differentiate between different types of
                -- objects to be drawn
                SELECT
                (
                    CASE
                    WHEN _type = 'parcel' THEN
                        '<path fill="wheat" stroke="red"  stroke-width="4" d="' || ST_AsSVG(way) || '"/>'
                    WHEN _type = 'road' THEN
                        '<path fill-opacity="0" stroke="blue" stroke-width="8" d="' || ST_AsSVG(way) || '"/>'
                    WHEN _type = 'support' THEN
                        '<path fill="orange" stroke="green" stroke-width="20" d="' || ST_AsSVG(way) || '"/>'
                    END
                ) AS path
                FROM a
            ) q
        ), svg AS (
            SELECT
            (
                '<html><svg width="100%" height="100%" preserveAspectRatio="" viewBox="' ||
                concat_ws(' ', ST_XMin(d.env), ST_YMax(d.env) * -1, (ST_XMax(d.env) - ST_XMin(d.env)), (ST_YMax(d.env) - ST_YMin(d.env))) || '">' ||
                e.paths ||
                '</svg></html>'
            ) AS content
            FROM e, d
        )
        SELECT content
        FROM svg
    );

    RETURN retval;
END;
$$ LANGUAGE plpgsql;
\set QUIET 0


\set QUIET 1
TRUNCATE support RESTART IDENTITY;
-- this function will implement the corner-cut algorithm
DROP FUNCTION pseudo_parcel(integer, integer);
CREATE OR REPLACE FUNCTION pseudo_parcel(p_uid integer, area integer) RETURNS void AS $$
DECLARE
bbox geometry;
BEGIN
    bbox := (SELECT ST_Envelope(way) AS way FROM parcel WHERE gid = p_uid);
    INSERT INTO support(way) VALUES (bbox);
    RAISE NOTICE '%', bbox;
END;
$$ LANGUAGE plpgsql;
\set QUIET 0

SELECT pseudo_parcel(1,2);
SELECT pseudo_parcel(2,2);
SELECT pseudo_parcel(3,2);
SELECT pseudo_parcel(4,2);
SELECT parcels_draw();
