-- this block will set some flags, and supress unneeded output.
-- this is a visualization that aids in development, it renders
-- a number of different shapes (roads, land areas) in SVG format.
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
-- this function draws all the shapes in the support, parcel and road tables
-- it differentiates between some shapes in order to better identify them in
-- the SVG output
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
            string_agg(svg_shape,'') AS svg_shapes
            FROM (
                -- draw objects differently depending on their type
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
                ) AS svg_shape
                FROM (
                    -- unpacking (for ST_Multi* structures)
                    SELECT
                    name,
                    _type,
                    (ST_Dump(way)).geom AS way
                    FROM a
                ) b
            ) q
        ), svg AS (
            SELECT
            (
                '<html><svg width="100%" height="100%" preserveAspectRatio="" viewBox="' ||
                concat_ws(' ', ST_XMin(d.env), ST_YMax(d.env) * -1, (ST_XMax(d.env) - ST_XMin(d.env)), (ST_YMax(d.env) - ST_YMin(d.env))) || '">' ||
                e.svg_shapes ||
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


-- Returns labels for the points received as input. A label can be one of 
-- N,E,S,W,NE,NW,SE,SW depending on their position on the bounding box. 
-- The input points are expected to be the extreme points on the boundary
-- of a polygon.
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
    --
    -- for example, the label 'NW' means the point is on both on the north
    -- and west edge of the bbox. this means it's the NW corner.
    labels := ARRAY[]::text[];
    extring := (
        SELECT
        ST_ExteriorRing(ST_ConvexHull(ST_Collect(way)))
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
            l := l || 'W';
        ELSIF ST_X(p) = ST_XMax(extring) THEN
            l := l || 'E';
        END IF;

        labels := (l || labels);
    END LOOP;

    RETURN labels;
END;
$$ LANGUAGE plpgsql;


-- 
-- split a geometry horizontally and return three geometries
-- - split line
-- - upper part
-- - lower part
--
-- the split line will be tmid distance down from the highest point of poly
CREATE OR REPLACE FUNCTION h_split(poly geometry, tmid float, bxmin float, bxmax float, bymin float, bymax float) RETURNS geometry[] AS $$
DECLARE
baseline  geometry;
splitline geometry;
result    geometry[];
BEGIN
    baseline  := ST_SetSRID(ST_MakeLine(ST_MakePoint(bxmin,bymin), ST_MakePoint(bxmax,bymin)), 900913);
    splitline := ST_Translate(baseline,0,tmid);
    -- split with horizontal line, we might
    -- get back more than two pieces (depending on the shape of poly).
    -- so we need to collect those above, and those below the cut.
    WITH parts AS (
        SELECT 
        a.piece
        FROM (
            SELECT ((ST_Dump((ST_Split(poly, splitline)))).geom) AS piece
        ) a
    ), U AS (
        SELECT
        ST_Multi(ST_Collect(piece)) AS shape
        FROM parts
        WHERE ST_YMin(piece) >= bymin + tmid
    ), D AS (
        SELECT
        ST_Multi(ST_Collect(piece)) AS shape
        FROM parts
        WHERE ST_YMin(piece)  < bymin + tmid
    )
    SELECT ARRAY[U.shape, D.shape] INTO result
    FROM U,D;

    RETURN (splitline || result);
END;
$$ LANGUAGE plpgsql;

-- 
-- split a geometry vertically and return three geometries
-- - split line
-- - left  part
-- - right part
--
-- the split line will be tmid distance right from the leftmost point of poly
CREATE OR REPLACE FUNCTION v_split(poly geometry, tmid float, bxmin float, bxmax float, bymin float, bymax float) RETURNS geometry[] AS $$
DECLARE
baseline  geometry;
splitline geometry;
result    geometry[];
BEGIN
    baseline  := ST_SetSRID(ST_MakeLine(ST_MakePoint(bxmin,bymin), ST_MakePoint(bxmin,bymax)), 900913);
    splitline := ST_Translate(baseline,tmid,0);
    -- split with horizontal line, we might
    -- get back more than two pieces (depending on the shape of poly).
    -- so we need to collect those above, and those below the cut.
    WITH parts AS (
        SELECT 
        a.piece
        FROM (
            SELECT ((ST_Dump((ST_Split(poly, splitline)))).geom) AS piece
        ) a
    ), L AS (
        SELECT
        ST_Multi(ST_Collect(piece)) AS shape
        FROM parts
        WHERE ST_XMin(piece)  < bxmin + tmid
    ), R AS (
        SELECT
        ST_Multi(ST_Collect(piece)) AS shape
        FROM parts
        WHERE ST_XMin(piece) >= bxmin + tmid
    )
    SELECT
    ARRAY[L.shape, R.shape] INTO result
    FROM L,R;

    RETURN (splitline || result);
END;
$$ LANGUAGE plpgsql;


-- input:
-- receives as parameters the initial polygon, the desired area,
-- an integer indicating which part we're searching for (1 for upper and 2 for lower)
-- the x/y min/max of the bbox for the polygon.
--
-- output:
-- returns the cut line
--
-- this cut is applied when the road is closest to the north-west corner
-- and therefore the NW corner will be cut. the sweep line will start in the
-- north and will travel towards south to find the required area above it.
--
-- the optimal cut line is found via binary search.  
CREATE OR REPLACE FUNCTION hcut_search(poly geometry, updown integer, area float, bxmin float, bxmax float, bymin float, bymax float) RETURNS geometry[] AS $$
DECLARE
-- width of bounding box;
bwidth    float;
-- length of bounding box;
bheight   float;
-- trial cursor will be between [0,bwidth] or between [0,bheight]
tlow      float;
tmid      float;
thigh     float;
-- trial cut area
tarea     float;
-- tsplit
tsplit geometry[];
-- iteration number
titer     integer;
BEGIN
    bwidth  := bxmax - bxmin;
    bheight := bymax - bymin;

    -- setting up the sweep line bsearch.
    -- we're looking for a cut between [0, bheight]
    -- (analogous situation for vertical sweep-line).

    -- north-south sweep line (this is a horizontal line that travels in north-south direction)
    titer := 0;
    tlow  := 0;
    thigh := bheight;
    WHILE tlow < thigh LOOP
        -- RAISE NOTICE 'loop';
        tmid      := (tlow + thigh)/2;
        tsplit    := h_split(poly,tmid,bxmin,bxmax,bymin,bymax);
        -- compute selected area (add 1 to skip over the split line)
        tarea     := ST_Area(tsplit[1 + updown]);
        -- re-adjust the range we're searching for the split
        -- depending on overshot/undershot relatve to the target area.
        IF    tarea > area AND updown = 1 THEN
            -- overshot  the upper target area
            tlow  := tmid;
        ELSIF tarea < area AND updown = 1 THEN
            -- undershot the upper target area
            thigh := tmid;
        ELSIF tarea > area AND updown = 2 THEN
            -- overshot  the lower target area
            thigh := tmid;
        ELSIF tarea < area AND updown = 2 THEN
            -- undershot the lower target area
            tlow  := tmid;
        END IF;

        RAISE NOTICE 'area selected by split: %', tarea;
        IF ABS(tarea - area) < 0.001 THEN
            RAISE NOTICE 'found split with reasonably close area';
            RAISE NOTICE 'delta for split: %', ABS(tarea-area);
            EXIT;
        END IF;
        
        IF titer > 70 THEN
            RAISE NOTICE 'exceeded search iterations';
            RETURN NULL;
        END IF;

        titer := titer + 1;
    END LOOP;

    RETURN tsplit;
END;
$$ LANGUAGE plpgsql;



-- same as hcut_search except the cut line is vertical here
CREATE OR REPLACE FUNCTION vcut_search(poly geometry, leftright integer, area float, bxmin float, bxmax float, bymin float, bymax float) RETURNS geometry[] AS $$
DECLARE
-- width of bounding box;
bwidth    float;
-- length of bounding box;
bheight   float;
-- trial cursor will be between [0,bwidth] or between [0,bheight]
tlow      float;
tmid      float;
thigh     float;
-- trial cut area
tarea     float;
-- tsplit
tsplit    geometry[];
-- iteration number
titer     integer;
BEGIN
    bwidth  := bxmax - bxmin;
    bheight := bymax - bymin;

    -- setting up the sweep line bsearch.
    -- we're looking for a cut between [0, bwidth]
    -- (analogous situation for vertical sweep-line).

    -- north-south sweep line (this is a horizontal line that travels in north-south direction)
    titer := 0;
    tlow  := 0;
    thigh := bwidth;

    WHILE tlow < thigh LOOP
        -- RAISE NOTICE 'loop';
        tmid    := (tlow + thigh)/2;
        -- compute selected area (add 1 to skip over the split line)
        tsplit  := v_split(poly,tmid,bxmin,bxmax,bymin,bymax);
        tarea   := ST_Area(tsplit[1 + leftright]);

        -- re-adjust the range we're searching for the split
        -- depending on overshot/undershot relatve to the target area.
        IF    tarea > area AND leftright = 1 THEN
            -- overshot  the left target area
            thigh := tmid;
        ELSIF tarea < area AND leftright = 1 THEN
            -- undershot the left target area
            tlow  := tmid;
        ELSIF tarea > area AND leftright = 2 THEN
            -- overshot  the right target area
            tlow  := tmid;
        ELSIF tarea < area AND leftright = 2 THEN
            -- undershot the right target area
            thigh := tmid;
        END IF;

        RAISE NOTICE 'area selected by split: %', tarea;
        IF ABS(tarea - area) < 0.001 THEN
            RAISE NOTICE 'found split with reasonably close area';
            RAISE NOTICE 'delta for split: %', ABS(tarea-area);
            EXIT;
        END IF;
        
        IF titer > 70 THEN
            RAISE NOTICE 'exceeded search iterations';
            RETURN NULL;
        END IF;

        titer := titer + 1;
    END LOOP;
    RETURN tsplit;
END;
$$ LANGUAGE plpgsql;

-- find which corner to cut
CREATE OR REPLACE FUNCTION find_cut_corner(lrc text[]) RETURNS text AS $$
DECLARE
rand_corner integer;
BEGIN
    IF     (ARRAY['N'] <@ lrc AND ARRAY['W'] <@ lrc) OR ARRAY['NW'] <@ lrc THEN
        RETURN 'NW';
    ELSIF  (ARRAY['N'] <@ lrc AND ARRAY['E'] <@ lrc) OR ARRAY['NE'] <@ lrc THEN
        RETURN 'NE';
    ELSIF  (ARRAY['S'] <@ lrc AND ARRAY['W'] <@ lrc) OR ARRAY['SW'] <@ lrc THEN
        RETURN 'SW';
    ELSIF  (ARRAY['S'] <@ lrc AND ARRAY['E'] <@ lrc) OR ARRAY['SE'] <@ lrc THEN
        RETURN 'SE';
    ELSE
        -- no definitive corner was identified.
        -- (this can happen if the two closest points to the road
        -- were both on the same edge of the bbox)
        -- so we pick a random corner
        rand_corner := (random() * 3 + 1)::int;
        RETURN (ARRAY['NW','NE','SE','SW'])[rand_corner];
    END IF;
END;
$$ LANGUAGE plpgsql;


--
-- This function will implement the corner-cut algorithm
-- the return value will be true if the parcel was found.
-- 
-- Return value:
-- -  NULL if there was an error
-- - false if a parcel was not found
-- -  true if a parcel was found
--
CREATE OR REPLACE FUNCTION pseudo_parcel(p_uid integer, target_area float) RETURNS boolean AS $$
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
cut_corner  text;
-- the result of the inset split
inset_split geometry[];
-- area of the input polygon
p_area     float;
-- cut line
cut_result  geometry[];
BEGIN
    poly   := (SELECT way FROM parcel WHERE gid = p_uid);
    p_area := ST_Area(poly);

    IF poly IS NULL THEN
        -- the input polygon was not found in the polygon table
        RAISE NOTICE 'input polygon not found';
        RETURN NULL;
    END IF;

    IF p_area < target_area THEN
        -- the input polygon is too small and we won't be able to
        -- to find a parcel with the required area.
        RAISE NOTICE 'the polygon area is too small';
        RETURN NULL;
    END IF;

    RAISE NOTICE 'original area: %', p_area;


    bbox := (
        -- get parcel boundary
        SELECT ST_ExteriorRing(ST_Envelope(way)) AS way
        FROM parcel
        WHERE gid = p_uid
    );
    INSERT INTO support(way) VALUES (bbox);

    -- get boundary extreme points for polygon
    boundary := (
        WITH points AS (
            SELECT
            (ST_DumpPoints(way)).geom AS p
            FROM (
                SELECT way 
                FROM parcel 
                WHERE gid = p_uid
            ) a
        ), west AS (
            SELECT p FROM points ORDER BY ST_X(p)      LIMIT 1
        ), east AS (
            SELECT p FROM points ORDER BY ST_X(p) DESC LIMIT 1
        ), north AS (
            SELECT p FROM points ORDER BY ST_Y(p)      LIMIT 1
        ), south AS (
            SELECT p FROM points ORDER BY ST_Y(p) DESC LIMIT 1
        )
        SELECT ARRAY[west.p, east.p, north.p, south.p]
        FROM west,east,north,south
    );
    nesw := get_nesw(boundary);

    RAISE NOTICE 'nesw: %', nesw;
    RAISE NOTICE 'boundary types %', (SELECT array_agg(ST_GeometryType(p)) FROM unnest(boundary) a(p));

    -- the closest two boundary points to a nearby road
    rc2 := (
        WITH c1 AS (
            SELECT
            b.way
            FROM road r, unnest(boundary) b(way)
            ORDER BY r.way <-> b.way
            LIMIT 1
        ), c2 AS (
            SELECT
            b.way
            FROM road r, unnest(boundary) b(way), c1
            WHERE ST_AsText(b.way) <> ST_AsText(c1.way)
            ORDER BY r.way <-> b.way
            LIMIT 1
        )
        SELECT
        ARRAY[c1.way,c2.way]
        FROM c1, c2
    );

    RAISE NOTICE 'rc2 types %', (SELECT array_agg(ST_GeometryType(p)) FROM unnest(rc2) a(p));

    -- get the NESW labels of the two closest boundary points to the nearby road
    lrc := (
        SELECT
        array_agg(nesw[nesw_idx])
        FROM generate_series(1,2) a(rc2_idx)
        JOIN generate_series(1,4) c(nesw_idx) ON ST_Distance(boundary[nesw_idx],rc2[rc2_idx]) < 0.001
    );
    -- lrc now has information about which corner we're going to cut.
    RAISE NOTICE 'lrc: %', lrc;

    INSERT INTO support(way) SELECT * FROM unnest(boundary);
    INSERT INTO support(way) SELECT * FROM unnest(rc2) a;

    SELECT ST_XMax(p),ST_XMin(p),ST_YMax(p),ST_YMin(p)
    INTO   bxmax,bxmin,bymax,bymin
    FROM (
        SELECT ST_Envelope(ST_Collect(w)) p
        FROM  unnest(boundary) a(w)
    ) c;

    bwidth  := bxmax - bxmin;
    bheight := bymax - bymin;

    cut_corner := find_cut_corner(lrc);
    RAISE NOTICE 'cut corner: %', cut_corner;

    --
    -- we have four cases(one for each corner). all of the cases are very similar.
    -- we make a horizontal split and if we don't have enough area we make a
    -- better horizontal split with the same goal. otherwise we make a vertical split
    -- to get the required area.
    --
    -- here's an example for the NW corner(with the two cases mentioned before):
    --
    -- 1)                               2)
    -- +-----------------+              +-----------------+
    -- | target |        |              | target          |
    -- +--------+--------+              |                 |
    -- |        |        |              +-----------------|
    -- |        |        |              |                 |
    -- |        |        |              |                 |
    -- |        |        |              |                 |
    -- +--------+--------+              +-----------------+
    -- 
    IF cut_corner = 'NW' THEN
        -- (bheight - sqrt(target_area)) is where the inset should be placed for NW corner
        inset_split := h_split(poly,bheight - sqrt(target_area),bxmin,bxmax,bymin,bymax);
        IF ST_Area(inset_split[2]) < target_area THEN
            -- the inset cut was insufficient so we search for a horizontal cut
            RAISE NOTICE 'hcut_search';
            cut_result := hcut_search(poly,1,target_area,bxmin,bxmax,bymin,bymax);
            -- INSERT INTO support(way) SELECT cut_result[1];

            -- update original parcel
            UPDATE parcel SET way = cut_result[3] WHERE gid = p_uid;
            -- insert the new parcel
            INSERT INTO parcel (way, pseudo, parent_id) VALUES(cut_result[2], true, p_uid);
        ELSE
            -- the inset produced an upper area which is beyond what we need, we're looking to cut that area further
            -- so we're now looking for a vertical cut but applied to the upper part of the inset split (not on original poly)
            RAISE NOTICE 'inset split + vcut_search';
            cut_result := vcut_search(inset_split[2],1,target_area,ST_XMin(inset_split[2]),ST_XMax(inset_split[2]),ST_YMin(inset_split[2]),ST_YMax(inset_split[2]));
            INSERT INTO support(way) SELECT inset_split[1];
            INSERT INTO support(way) SELECT cut_result[1];
            -- update the original parcel
            UPDATE parcel SET way = ST_Union(inset_split[3], cut_result[3]) WHERE gid = p_uid;
            -- insert the new parcel 
            INSERT INTO parcel (way, pseudo, parent_id) VALUES(cut_result[2], true, p_uid);
        END IF;
        RETURN true;
    ELSIF cut_corner = 'NE' THEN
        inset_split := h_split(poly,bheight - sqrt(target_area),bxmin,bxmax,bymin,bymax);
        IF ST_Area(inset_split[2]) < target_area THEN
            RAISE NOTICE 'hcut_search';
            cut_result := hcut_search(poly,1,target_area,bxmin,bxmax,bymin,bymax);
            -- update original parcel
            UPDATE parcel SET way = cut_result[3] WHERE gid = p_uid;
            -- insert the new parcel
            INSERT INTO parcel (way, pseudo, parent_id) VALUES(cut_result[2], true, p_uid);
        ELSE
            RAISE NOTICE 'inset split + vcut_search';
            cut_result := vcut_search(inset_split[2],2,target_area,ST_XMin(inset_split[2]),ST_XMax(inset_split[2]),ST_YMin(inset_split[2]),ST_YMax(inset_split[2]));
            INSERT INTO support(way) SELECT inset_split[1];
            INSERT INTO support(way) SELECT cut_result[1];
            UPDATE parcel SET way = ST_Union(inset_split[3], cut_result[2]) WHERE gid = p_uid;
            INSERT INTO parcel (way, pseudo, parent_id) VALUES(cut_result[3], true, p_uid);
        END IF;
        RETURN true;
    ELSIF cut_corner = 'SE' THEN
        inset_split := h_split(poly,sqrt(target_area),bxmin,bxmax,bymin,bymax);
        IF ST_Area(inset_split[3]) < target_area THEN
            RAISE NOTICE 'hcut_search';
            cut_result := hcut_search(poly,2,target_area,bxmin,bxmax,bymin,bymax);
            -- update original parcel
            UPDATE parcel SET way = cut_result[2] WHERE gid = p_uid;
            -- insert the new parcel
            INSERT INTO parcel (way, pseudo, parent_id) VALUES(cut_result[3], true, p_uid);
        ELSE
            RAISE NOTICE 'inset split + vcut_search';
            cut_result := vcut_search(inset_split[3],2,target_area,ST_XMin(inset_split[3]),ST_XMax(inset_split[3]),ST_YMin(inset_split[3]),ST_YMax(inset_split[3]));
            INSERT INTO support(way) SELECT inset_split[1];
            INSERT INTO support(way) SELECT cut_result[1];
            UPDATE parcel SET way = ST_Union(inset_split[2], cut_result[2]) WHERE gid = p_uid;
            INSERT INTO parcel (way, pseudo, parent_id) VALUES(cut_result[3], true, p_uid);
        END IF;
        RETURN true;
    ELSIF cut_corner = 'SW' THEN
        inset_split := h_split(poly,sqrt(target_area),bxmin,bxmax,bymin,bymax);
        IF ST_Area(inset_split[3]) < target_area THEN
            RAISE NOTICE 'hcut_search';
            cut_result := hcut_search(poly,2,target_area,bxmin,bxmax,bymin,bymax);
            -- update original parcel
            UPDATE parcel SET way = cut_result[2] WHERE gid = p_uid;
            -- insert the new parcel
            INSERT INTO parcel (way, pseudo, parent_id) VALUES(cut_result[3], true, p_uid);
        ELSE
            RAISE NOTICE 'inset split + vcut_search';
            cut_result := vcut_search(inset_split[3],1,target_area,ST_XMin(inset_split[3]),ST_XMax(inset_split[3]),ST_YMin(inset_split[3]),ST_YMax(inset_split[3]));
            INSERT INTO support(way) SELECT inset_split[1];
            INSERT INTO support(way) SELECT cut_result[1];
            UPDATE parcel SET way = ST_Union(inset_split[2], cut_result[3]) WHERE gid = p_uid;
            INSERT INTO parcel (way, pseudo, parent_id) VALUES(cut_result[2], true, p_uid);
        END IF;
        RETURN true;
    END IF;

    RETURN false;
END;
$$ LANGUAGE plpgsql;


-- suppress output
\o /dev/null
-- cut parcels until there's no more land to cut
DO $$
DECLARE
enough_land boolean;
target_parcel_area float;
BEGIN
    target_parcel_area := 8000;

    enough_land := true;
    WHILE enough_land IS NOT NULL AND enough_land = true
    LOOP
        RAISE NOTICE '----';
        enough_land := pseudo_parcel(1,target_parcel_area); 
    END LOOP;
END$$;
-- re-enable stdout output
-- TRUNCATE support RESTART IDENTITY; 
\o

-- Sample calls of pseudo_parcel:
-- - 1,4000.0   -> triggers inset + vcut
-- - 1,30000.0) -> triggers a NW-corner cut with hcut_search
\set QUIET 0

SELECT parcels_draw();
