#!/bin/bash
set -e
set -o pipefail

ID=$1
BASEIMG=$2
OUTPUTIMG=nfd-nightly-output-$ID
BUILDDIR=build-$ID
OUTPUTDIR=output-$ID

mkdir -p $BUILDDIR $OUTPUTDIR
cp ct/* $BUILDDIR/

(
  echo 'FROM '$BASEIMG
  if [[ $BASEIMG == balenalib* ]]; then
    echo 'RUN ["cross-build-start"]'
  fi
  echo 'COPY compile.sh /'
  echo 'RUN /bin/bash /compile.sh'
) > $BUILDDIR/Dockerfile

docker build -t $OUTPUTIMG $BUILDDIR

CTID=$(docker container create $OUTPUTIMG)
docker cp $CTID:/output/ ./$OUTPUTDIR/
docker container stop $CTID
