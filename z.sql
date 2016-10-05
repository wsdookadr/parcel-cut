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

WITH settings AS (
        SELECT    'wheat' :: text AS fill_poly
                , 'white' :: text AS stroke_poly
                , 'gray' :: text AS fill_text
                , 5e-4 AS stroke_width
                , 5e-3 AS font_size
), a AS (
        SELECT name, way, ST_Centroid(way) poi
        FROM parcel
        LIMIT 1
), b AS (
        SELECT concat('<path d="'
                , ST_AsSVG(way, 0, 10)
                , '" fill="', fill_poly
                , '" stroke="', stroke_poly
                , '" stroke-width="', stroke_width
                , '" stroke-linejoin="round" />')
        FROM a, settings
), c AS (
        SELECT concat('<text x="'
                , ST_X(poi)
                , '" y="', ST_Y(poi) * -1
                , '" fill="', fill_text
                , '" font-size="', font_size
                , '" text-anchor="middle">'
                , name, '</text>')
        FROM a, settings
), d AS (
        SELECT ST_Envelope(ST_Collect(way)) env FROM a
)
SELECT concat('<html><svg viewBox="'
                , concat_ws(' ', ST_XMin(env)
                        , ST_YMax(env) * -1
                        , ST_XMax(env) - ST_XMin(env)
                        , ST_YMax(env) - ST_YMin(env))
                , '">')
FROM d
UNION ALL SELECT * FROM b
UNION ALL SELECT * FROM c
UNION ALL SELECT '</svg></html>';
