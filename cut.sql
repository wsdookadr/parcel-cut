SET search_path = public, plan;
\o '/tmp/z.svg'
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
'<svg xmlns="http://www.w3.org/2000/svg" version="1.1" viewBox="' ||
concat_ws(' ', ST_XMin(d.env), ST_YMax(d.env) * -1, (ST_XMax(d.env) - ST_XMin(d.env)), (ST_YMax(d.env) - ST_YMin(d.env))) || '">' ||
'<g transform="scale(0.931)">' ||
'<path style="fill:none; stroke:red; stroke-width:6" d="' || ST_AsSVG(a.way) || '"/>' ||
'</g></svg>'
FROM a,d;
\o


