#!/bin/bash
set -e
set -o pipefail
PROJ=$1
TARGET=$2

case $TARGET in
  bionic-amd64) BASEIMG=ubuntu:18.04 ;;
  buster-amd64) BASEIMG=debian:buster ;;
  buster-armv7) BASEIMG=balenalib/generic-armv7ahf:buster-build ;;
  buster-armv6) BASEIMG=balenalib/raspberry-pi:buster-build ;;
esac

(
  echo 'FROM '$BASEIMG
  if [[ $BASEIMG == balenalib* ]]; then
    echo 'RUN ["cross-build-start"]'
  fi
  if [[ -f output.txz ]]; then
    mv output.txz deps.txz
    echo 'COPY deps.txz /'
  fi
  echo 'COPY compile.sh /'
  echo 'RUN /bin/bash /compile.sh '$PROJ
) > Dockerfile

docker build -t nfd-nightly-build .

CTID=$(docker container create nfd-nightly-build)
docker cp $CTID:/output.txz ./
docker container stop $CTID
