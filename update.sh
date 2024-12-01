#!/bin/bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
ROOTDIR=$(pwd)
source .env
rm -rf $ROOTDIR/dl
mkdir -p $ROOTDIR/dl
cd $ROOTDIR/dl

curl_gh() {
  curl -fsS -H "Authorization: token ${GH_PAT}" "$@"
}

ARTIFACTS_URL=$(curl_gh https://api.github.com/repos/${REPO}/actions/runs |
  jq -r --arg branch $BRANCH '.workflow_runs | map(select(.conclusion=="success" and .head_branch==$branch))[0] | .artifacts_url')
curl_gh "${ARTIFACTS_URL}?per_page=100" | jq -r '.artifacts[] | [.name,.archive_download_url] | @tsv' >artifacts.tsv

while IFS="" read ARTIFACT; do
  ASSET_FILENAME="$(echo "$ARTIFACT" | cut -f1).zip"
  ASSET_URL="$(echo "$ARTIFACT" | cut -f2)"
  curl_gh -L -o "$ASSET_FILENAME" "$ASSET_URL"
done <artifacts.tsv

add_zips() {
  TMPDIR=/tmp/nfd-nightly-apt-$1-$2
  rm -rf $TMPDIR
  mkdir -p $TMPDIR
  cd $TMPDIR
  for ZIP in "${ROOTDIR}/dl/*$3.zip"; do
    unzip "$ZIP"
  done
  reprepro -v -b $ROOTDIR/public/$1 --delete clearvanished
  reprepro -v -b $ROOTDIR/public/$1 -A $4 removematched $2 '*'
  reprepro -v -b $ROOTDIR/public/$1 includedeb $2 *.deb
  cd $ROOTDIR
  [[ -d $TMPDIR ]] && rm -rf $TMPDIR
}

add_zips debian bookworm bookworm-amd64 amd64
add_zips debian bookworm bookworm-arm64 arm64
add_zips ubuntu jammy jammy-amd64 amd64
add_zips ubuntu noble noble-amd64 amd64

rm -rf $ROOTDIR/dl
