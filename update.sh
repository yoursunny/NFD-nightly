#!/bin/bash
set -eo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
ROOTDIR=$(pwd)
source .env

curl_gh() {
  curl -sf -H "Authorization: token ${GH_PAT}" "$@"
}

ARTIFACTS_URL=$(curl_gh https://api.github.com/repos/${REPO}/actions/runs | \
  jq -r "[ .workflow_runs[] | select(.conclusion==\"success\" and .head_branch==\"${BRANCH}\") ] [0] | .artifacts_url")
DOWNLOAD_URLS=$(curl_gh "${ARTIFACTS_URL}?per_page=100" | jq -r '.artifacts[] | .archive_download_url')

rm -rf $ROOTDIR/dl
mkdir -p $ROOTDIR/dl
cd $ROOTDIR/dl
for DOWNLOAD_URL in $DOWNLOAD_URLS; do
  ASSET_URL=$(curl_gh -I $DOWNLOAD_URL | \
    awk 'tolower($1)=="location:" { print $2; found=1 } END { exit 1-found }')
  wget -q --content-disposition $ASSET_URL
done

add_zips() {
  TMPDIR=/tmp/nfd-nightly-apt-$1-$2
  [[ -d $TMPDIR ]] && rm -rf $TMPDIR
  mkdir -p $TMPDIR
  cd $TMPDIR
  for ZIP in "${ROOTDIR}/dl/*$3.zip"; do
    unzip "$ZIP"
  done
  reprepro -v -b $ROOTDIR/public/$1 -A $4 removematched $2 '*'
  reprepro -v -b $ROOTDIR/public/$1 includedeb $2 *.deb
  cd $ROOTDIR
  [[ -d $TMPDIR ]] && rm -rf $TMPDIR
}

add_zips debian buster buster-amd64 amd64
add_zips debian buster buster-armv7 armhf
add_zips ubuntu bionic bionic-amd64 amd64
add_zips ubuntu focal focal-amd64 amd64
add_zips raspberrypi buster buster-armv6 armhf
