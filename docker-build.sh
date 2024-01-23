#!/bin/bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

docker build -t localhost/nfd-nightly-reprepro - <Dockerfile.reprepro
