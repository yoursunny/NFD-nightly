#!/bin/bash
set -euo pipefail

git ls-files -- '**.sh' |
  xargs --no-run-if-empty docker run --rm -u $(id -u):$(id -g) -v $PWD:/mnt -w /mnt mvdan/shfmt:v3 -l -w -s -i=2 -ci
