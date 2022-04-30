#!/bin/bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

docker run --rm --user $(id -u):$(id -g) \
  --mount type=bind,source=$(pwd),target=/work -w /work \
  nfd-nightly-reprepro ./update.sh