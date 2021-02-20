#!/bin/bash
set -eo pipefail
PROJ=$1
TARGET=$2

BASEIMG=$(jq -r '.target | to_entries[] | select(.key == "'$TARGET'") | .value.base' matrix.json)

(
  echo 'FROM '$BASEIMG
  if [[ $BASEIMG == balenalib* ]]; then
    echo 'RUN ["cross-build-start"]'
  fi
  if [[ -d deps ]]; then
    echo 'COPY deps /deps'
  fi
  echo 'COPY compile.sh matrix.json /'
  echo 'RUN /bin/bash /compile.sh '$PROJ
) > Dockerfile

docker build -t nfd-nightly-build .

CTID=$(docker container create nfd-nightly-build)
docker cp $CTID:/source ./output
docker container stop $CTID
