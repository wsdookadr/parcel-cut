#!/bin/bash
psql -d dbgeo1 < load.sql
psql -d dbgeo1 < cut.sql > render.html
