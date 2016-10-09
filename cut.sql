-- this block will set some flags, and supress unneeded output.
-- this is the workbench program where most development
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
CREATE OR REPLACE FUNCTION parcels_draw() RETURNS text AS $$
DECLARE
retval text;
BEGIN
    retval := (
        WITH a AS (
            -- unions together all the objects
            -- we want to draw
            SELECT
            name, way, 'parcel' AS _type
            FROM parcel
            UNION ALL
            SELECT
            name, way, 'road' AS _type
            FROM road
            UNION ALL
            SELECT
            name, way, 'support' AS _type
            FROM support
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
                    WHEN _type = 'support' AND ST_GeometryType(way) = 'ST_LineString' THEN
                        '<path fill-opacity="0" stroke="violet" stroke-width="13" d="' || ST_AsSVG(way) || '"/>'
                    WHEN _type = 'support' AND ST_GeometryType(way) = 'ST_Polygon' THEN
                        '<path fill-opacity="0.2" fill="green" stroke="orange" stroke-width="13" d="' || ST_AsSVG(way) || '"/>'
                    WHEN _type = 'support' AND ST_GeometryType(way) = 'ST_Point' THEN
                        '<circle fill-opacity="1" fill="steelblue" stroke="royalblue" stroke-width="10" r="20" ' || ST_AsSVG(way) || '/>'
                    END
                ) AS path
                FROM (
                    -- unpack multi structures
                    SELECT
                    name,
                    _type,
                    (st_dump(way)).geom AS way
                    FROM a
                ) b
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


-- TODO: implement and use this function in pseudo_parcel
-- label boundary points with indicators based on which edge of the bounding
-- box they're on
CREATE OR REPLACE FUNCTION get_nesw(ps geometry[]) RETURNS text[] AS $$
DECLARE
extring   geometry;
p         geometry;
labels    text[];
l         text;
BEGIN
    -- the way we're going to label points is as follows
    -- we're going to check whether they have YMax or YMin
    -- and add an 'N' or 'S' and then we're going to check if they have
    -- an XMin or XMax and add an 'W' or 'E'.
    -- if a point is labelled with 'NW' then this means they're right on the
    -- north-west corner of the bounding-box.
    labels := ARRAY[]::text[];
    extring := (
        SELECT
        ST_ExteriorRing(ST_Envelope(ST_Collect(way)))
        FROM
        unnest(ps) m(way)
    );

    FOREACH p IN ARRAY ps
    LOOP
        l := '';

        IF    ST_Y(p) = ST_YMax(extring) THEN
            l := l || 'N';
        ELSIF ST_Y(p) = ST_YMin(extring) THEN
            l := l || 'S';
        END IF;

        IF    ST_X(p) = ST_XMin(extring) THEN
            l := l || 'E';
        ELSIF ST_X(p) = ST_XMax(extring) THEN
            l := l || 'W';
        END IF;

        labels := ARRAY[l]::text[] || labels;
    END LOOP;

    RETURN labels;
END;
$$ LANGUAGE plpgsql;

-- TODO: remove azimuth ordering because it's not required.
-- TODO: handle g1 <-> g2 distances and closest-points where both
--       geometries can be lines.


-- this function will implement the corner-cut algorithm
CREATE OR REPLACE FUNCTION pseudo_parcel(p_uid integer, area float) RETURNS void AS $$
DECLARE
-- original polygon
poly       geometry;
bbox       geometry;
-- extreme cardinal points on the polygon boundary
boundary   geometry[];
-- labels for boundary points
nesw       text[];
-- two extreme points closest to the nearest road, and the road point
rc2        geometry[];
-- labels for near-road points
lrc        text[];

-- width of bounding box;
bwidth     float;
-- length of bounding box;
bheight    float;

-- xmin,xmax,ymin,ymax for bbox
bxmin      float;
bxmax      float;
bymin      float;
bymax      float;

-- area of the input polygon
p_area     float;
-- green line and red line (sweep lines)
gline      geometry; 
rline      geometry;

-- trial cursor will be between [0,bwidth] or between [0,bheight]
tlow    float;
tmid    float;
thigh   float;
-- trial cut area
tarea      float;
-- trial sweep line
tline   geometry;
-- tsplit
tsplit  geometry[];
-- iteration number
titer   integer;
BEGIN
    poly   := (SELECT way FROM parcel WHERE gid = p_uid);
    p_area := ST_Area(poly);

    RAISE NOTICE 'original area: %', p_area;


    bbox := (
        -- get parcel boundary
        SELECT ST_ExteriorRing(ST_Envelope(way)) AS way
        FROM parcel
        WHERE gid = p_uid
    );
    INSERT INTO support(way) VALUES (bbox);

    -- identify extreme boundary points and sort them by azimuth
    -- relative to the centroid of the bbox.
    -- (so they will be clock-wise sorted)
    boundary := (
        WITH int AS (
            --
            -- intersect the polygon ring with the
            -- envelope(bounding-box) ring to get the boundary
            -- extremum points (north,east,south,west).
            --
            -- (the result is an ST_MultiPoint, so it will need
            --  to be unpacked in order to be used)
            SELECT ST_Intersection(ST_ExteriorRing(way), ST_ExteriorRing(ST_Envelope(way))) AS way
            FROM (
                SELECT way 
                FROM parcel 
                WHERE gid = p_uid
            ) a
        ), unpacked AS (
            -- TODO: handle cases where the intersection is a line and not a point
            -- (these cases are generated by the edge of the bounding box coinciding
            --  with the contour of the shape, for axis-parallel squares for example).
            -- will have to think how to handle those.
            -- 
            -- unpack ST_MultiPoint to ST_Point
            SELECT (ST_Dump(way)).geom AS p
            FROM int
        ), center AS (
            -- get centroid of polygon defined by N,E,S,W extreme points
            SELECT
            ST_Centroid(ST_ExteriorRing(ST_Envelope(ST_Collect(p)))) AS c
            FROM unpacked
        ), sorted_cw AS (
            -- sort extreme points clock-wise
            SELECT
            a.p AS way
            FROM unpacked a, center b
            ORDER BY ST_Azimuth(b.c, a.p)
        )
        SELECT array_agg(way)
        FROM sorted_cw
    );

    INSERT INTO support(way) SELECT unnest(boundary);

    INSERT INTO support(way)
    SELECT ST_ConvexHull(ST_Collect(way))
    FROM (SELECT unnest(boundary) AS way) a;

    -- Note: Here we need to figure out which corner we're going to cut.
    -- We can cut one of these corners: NW,NE,SE,SW.
    -- We decide which corner based on two-closest extreme points
    -- to a nearby road.
    rc2 := (
        WITH close_pair AS (
            -- find the closest point on all of the nearby roads
            -- that's nearest to one of the extreme boundary points.
            SELECT
            ST_ClosestPoint(a.way,b.way) AS on_road,
            b.way AS on_parcel
            FROM road a, (SELECT way FROM unnest(boundary) m(way)) b
            ORDER BY ST_ClosestPoint(a.way,b.way) <-> b.way
            LIMIT 1
        ), other_extreme AS (
            -- find the other extreme point close to the road point
            SELECT
            b.on_parcel
            FROM close_pair a, (SELECT way AS on_parcel FROM unnest(boundary) m(way)) b
            WHERE ST_AsText(a.on_parcel) <> ST_AsText(b.on_parcel)
            ORDER BY b.on_parcel <-> a.on_road
            LIMIT 1
        )
        SELECT
        ARRAY[a.on_parcel, b.on_parcel, a.on_road]
        FROM close_pair a, other_extreme b
    );

    INSERT INTO support(way) SELECT ST_MakeLine(rc2[1], rc2[3]);
    INSERT INTO support(way) SELECT ST_MakeLine(rc2[2], rc2[3]);

    nesw := get_nesw(boundary);
    RAISE NOTICE '%', nesw;

    -- TODO: call get_nesw to get labels for boundary points
    --       distinguish between multiple cases. these cases come up
    --       due to position of the nearby-road relative to the boundary points.
    --       the goal is to decide which corner we're going to cut: NW,NE,SE or SW.
    -- TODO: Need to take the decision here on which
    --       direction to sweep in
    -- TODO: Need to compute the lrc (based on boundary, nesw and rc2).
    RAISE NOTICE '%', bbox;

    SELECT ST_XMax(p),ST_XMin(p),ST_YMax(p),ST_YMin(p)
    INTO   bxmax     ,bxmin     ,bymax     ,bymin
    FROM (
        SELECT ST_Envelope(ST_Collect(w)) p
        FROM  unnest(boundary) a(w)
    ) c;

    bwidth  := bxmax - bxmin;
    bheight := bymax - bymin;

    RAISE NOTICE '%', bwidth;
    RAISE NOTICE '%', bheight;

    -- setting up the sweep line bsearch.
    -- in order to create the sweeping line, we just get a copy of the
    -- bbox north edge and ST_Translate it from 0 to bheight
    -- (analogous situation for vertical sweep-line).

    -- north-south sweep line (this is a horizontal line that travels in north-south direction)
    gline := ST_SetSRID(ST_MakeLine(ST_MakePoint(bxmin,bymax), ST_MakePoint(bxmax,bymax)), 900913);
    titer := 0;
    tlow  := 0;
    thigh := bheight;
    WHILE tlow < thigh LOOP
        -- RAISE NOTICE 'loop';
        tmid    := (tlow + thigh)/2;
        tline   := ST_Translate(gline,0,-tmid);
        -- split with horizontal line, get two polygons back 
        tsplit  := (
            SELECT
            array_agg(b.piece)
            FROM (
                SELECT 
                a.piece
                FROM (
                    SELECT ((ST_Dump((ST_Split(poly, tline)))).geom) AS piece
                ) a
                ORDER BY ST_YMax(piece) DESC
            ) b
        );
        tarea := ST_Area(tsplit[1]);

        IF tarea > area THEN
            thigh := tmid;
        ELSIF tarea < area THEN
            tlow  := tmid;
        END IF;

        RAISE NOTICE 'area above split: %', tarea;
        RAISE NOTICE 'delta: %', ABS(tarea-area);
        
        IF ABS(tarea - area) < 0.001 OR titer > 1000 THEN
            EXIT;
        END IF;

        titer := titer + 1;
    END LOOP;

END;
$$ LANGUAGE plpgsql;
\set QUIET 0

SELECT pseudo_parcel(1,3000.0);
SELECT parcels_draw();
