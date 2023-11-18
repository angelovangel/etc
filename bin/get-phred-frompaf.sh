#! /usr/bin/env bash

# get the qscore from a paf with a de:f tag (as in minimap2 -c)

cat "${1:-/dev/stdin}" | awk '$12 >= 60' | grep -o 'de:f:[.0-9]*' | cut -d: -f3 | awk '{print -10*(log($1)/log(10))}'