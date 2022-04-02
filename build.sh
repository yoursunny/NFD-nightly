#!/bin/bash
set -euo pipefail
PROJ=$1
TARGET=$2

BASEIMG=$(jq -r --arg target "$TARGET" '.target[$target]' matrix.json)
REPO=$(jq -r --arg proj "$PROJ" '.proj[$proj].repo' matrix.json)
GROUP=$(jq -r --arg proj "$PROJ" '.proj[$proj].group' matrix.json)

(
  echo 'FROM '$BASEIMG
  if [[ $BASEIMG == balenalib* ]]; then
    echo 'RUN ["cross-build-start"]'
  fi
  echo 'ENV DEBIAN_FRONTEND=noninteractive'
  echo 'RUN apt-get update \'
  echo ' && apt-get install -qq --no-install-recommends ca-certificates devscripts equivs gawk git lsb-release python3'
  if [[ -d deps ]]; then
    echo 'COPY deps /deps'
  fi
  echo 'COPY compile.sh /'
  echo 'RUN /bin/bash /compile.sh '$PROJ $REPO $GROUP
) > Dockerfile

docker build -t nfd-nightly-build .

CTID=$(docker container create nfd-nightly-build)
docker cp $CTID:/source ./output
docker container stop $CTID
