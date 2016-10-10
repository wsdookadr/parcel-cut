#!/bin/bash
## dump tables invoved in project
pg_dump --data-only -d dbgeo1 -t parcel -t road > data/plan.dump
