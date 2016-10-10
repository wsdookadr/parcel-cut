This is an algorithm for land subdivision under certain constraints.
The goal is to cut a corner of a given area from a polygon. The corner
that is cut is the one closest to a nearby road.
The current version includes code to render the existing data in SVG format
for development purposes.

The algorithm is expected to work on
- PostgreSQL >= 9.4.7
- PostGIS    >= 2.2.2

You can find some test data for this in `data/plan.dump`.

Program descriptions:

| Program               | Usage                                                              |
| --------------------- | ------------------------------------------------------------------ |
| schema.sql            | Creates tables to hold the data                                    |
| load.sql              | Transfers some test data from OSM to the `parcel` and `road` table |
| cut.sql               | Runs the parcel splitting algorithm                                |


