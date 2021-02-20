#!/bin/bash
set -eo pipefail
PROJ=$1

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -qq --no-install-recommends ca-certificates devscripts equivs gawk git jq lsb-release python3
DISTRO=$(lsb_release -sc)
REPO=$(jq -r '.proj | to_entries[] | select(.key == "'$PROJ'") | .value.repo' /matrix.json)
DEP_NDNCXX=$(jq -r '.proj | to_entries[] | select(.key == "'$PROJ'") | .value.dep_ndncxx' /matrix.json)

mkdir -p /source

cd /source
git clone --recursive --depth=1 https://github.com/named-data/ppa-packaging.git
git clone --recursive $REPO $PROJ # `./waf version` needs full clone

if [[ -d /deps ]]; then
  cd /deps
  dpkg -i *.deb || apt-get install -f -qq
fi

cd /source/$PROJ

if [[ -x ./waf ]]; then
  ./waf version
  SRCVER=$(cat VERSION.info)
else
  SRCVER=$(git show -s --format='%ct %H' | gawk '{ printf "0.0.0-%s-%s", strftime("%Y%m%d%H%M%S", $1), substr($2,1,12) }')
fi
PKGVER="${SRCVER}-nightly"

if [[ ${DEP_NDNCXX} == true ]]; then
  # ndn-cxx does not have a stable ABI, so the dependent version should contain ndn-cxx version
  NDNCXX_PKGVER=$(dpkg -s libndn-cxx | awk '$1=="Version:" { print $2 }')
  NDNCXX_SRCVER=${NDNCXX_PKGVER/-nightly~*}
  NDNCXX_SRCVER=${NDNCXX_SRCVER//-/.}
  PKGVER="${PKGVER}~ndncxx${NDNCXX_SRCVER}"
fi
PKGVER="${PKGVER}~${DISTRO}"

if [[ -d debian ]]; then
  true
elif [[ -d ../ppa-packaging/$PROJ ]]; then
  cp -R ../ppa-packaging/$PROJ/debian .
fi
sed -i '/override_dh_auto_build/,/^$/ s|./waf build$|./waf build -j'$(nproc)'|' debian/rules

rm -rf debian/source

(
  echo "${PROJ} (${PKGVER}) ${DISTRO};"
  echo "  * Automated build of version ${SRCVER}"
  echo " -- Junxiao Shi <deb@mail1.yoursunny.com>  $(date -R)"
) > debian/changelog

if [[ ${DEP_NDNCXX} == true ]]; then
  # ndn-cxx does not have a stable ABI, so the dependent should depend on exact ndn-cxx version
  sed -i -E \
    -e '/^Depends:.*shlibs:Depends/ s|, libndn-cxx\b||' \
    -e "/^Depends:/ s|(\\\$\{shlibs:Depends\})|libndn-cxx (= ${NDNCXX_PKGVER}), \1|" \
    debian/control
fi

mk-build-deps -ir -t "apt-get -qq --no-install-recommends"
debuild -us -uc

cd /source
find -not -name '*.deb' -delete
