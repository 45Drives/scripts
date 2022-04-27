#!/bin/bash
TEST_NAME="2U_STORNADO_THERMAL_BENCHMARK"
GRAPH_TITLE="2U_STORNADO - 4x Everflow F128038BUAF - 22°C"

./tplot -o output/$TEST_NAME.csv -d 3600 -i 60 -s 6 -f
./csv_converter -i output/$TEST_NAME.csv -o chart_csv/$TEST_NAME.csv
./make_graph -i chart_csv/$TEST_NAME.csv -o graphs/$TEST_NAME.png -t "$GRAPH_TITLE"