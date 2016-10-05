#!/bin/bash
## dump tables invoved in project
pg_dump -d dbgeo1 -t parcel -t road
