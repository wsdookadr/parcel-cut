So far, this setup assumes that there is a database called dbgeo1 loaded
with OSM data for the city of Bucharest. This is for test purposes.

This is a very early version, where we create a separate schema called
"plan" (which is separate from the regular schema of the database).
We'll use this schema to create two tables, one for parcels, the other
for roads.  We'll transfer some limited amount of data from OSM to
populate tables in the "plan" schema.

The current version includes code to render the existing polygons in
the parcel table.
