#!/bin/bash
psql -d dbgeo1 < cut.sql > rendered-map.html
