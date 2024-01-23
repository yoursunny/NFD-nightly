#!/bin/bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

docker run -it --rm --user $(id -u):$(id -g) \
  --mount type=bind,source=$(pwd),target=/work -w /work \
  localhost/nfd-nightly-reprepro ./update.sh
