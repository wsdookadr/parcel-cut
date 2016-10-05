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
DROP FUNCTION parcels_draw();
CREATE OR REPLACE FUNCTION parcels_draw() RETURNS text AS $$
DECLARE
retval text;
BEGIN
    retval := (
        WITH a AS (
            SELECT
            name, way
            FROM parcel
            LIMIT 1
        ), d AS (
            SELECT
            ST_Envelope(ST_Collect(way)) env
            FROM a
        ), c AS (
            SELECT
            ST_Centroid(env) AS w
            FROM d
        ), svg AS (
            SELECT
            (
            '<html><svg width="100%" height="100%" preserveAspectRatio="" viewBox="' ||
            concat_ws(' ', ST_XMin(d.env), ST_YMax(d.env) * -1, (ST_XMax(d.env) - ST_XMin(d.env)), (ST_YMax(d.env) - ST_YMin(d.env))) || '">' ||
            '<path fill="wheat" stroke="red" stroke-width="0.00005" d="' || ST_AsSVG(a.way) || '"/>' ||
            '</svg></html>'
            ) AS content
            FROM a,d
        )
        SELECT content
        FROM svg
    );

    RETURN retval;
END;
$$ LANGUAGE plpgsql;
\set QUIET 0

SELECT parcels_draw();

