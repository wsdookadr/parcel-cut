-- this block will make some settings and
-- supress unneeded output 
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
)
SELECT
'<html><svg width="100%" height="100%" preserveAspectRatio="" viewBox="' ||
concat_ws(' ', ST_XMin(d.env), ST_YMax(d.env) * -1, (ST_XMax(d.env) - ST_XMin(d.env)), (ST_YMax(d.env) - ST_YMin(d.env))) || '">' ||
'<path fill="wheat" stroke="red" stroke-width="0.00005" d="' || ST_AsSVG(a.way) || '"/>' ||
'</svg></html>'
FROM a,d;


