#!/bin/bash
set -eo pipefail
PROJ=$1

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -qq --no-install-recommends ca-certificates devscripts equivs gawk git jq lsb-release python3
DISTRO=$(lsb_release -sc)
REPO=$(jq -r '.proj["'$PROJ'"].repo' /matrix.json)
GROUP=$(jq -r '.proj["'$PROJ'"].group' /matrix.json)

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

if [[ $GROUP -eq 2 ]]; then
  DEPVER_PKG=libpsync
  DEPVER_LABEL=psync
elif [[ $GROUP -eq 1 ]]; then
  DEPVER_PKG=libndn-cxx
  DEPVER_LABEL=ndncxx
fi
if [[ -n $DEPVER_PKG ]]; then
  # ndn-cxx and PSync do not have a stable ABI, so the dependent version should contain their versions
  DEP_PKGVER=$(dpkg -s ${DEPVER_PKG} | awk '$1=="Version:" { print $2 }')
  DEP_SRCVER=${DEP_PKGVER/~${DISTRO}/}
  DEP_SRCVER=${DEP_SRCVER/-nightly/}
  DEP_SRCVER=${DEP_SRCVER//-/.}
  PKGVER="${PKGVER}~${DEPVER_LABEL}${DEP_SRCVER}"
fi
PKGVER="${PKGVER}~${DISTRO}"

if ! [[ -d debian ]] && [[ -d ../ppa-packaging/$PROJ ]]; then
  cp -R ../ppa-packaging/$PROJ/debian .
fi
sed -i '/override_dh_auto_build/,/^$/ s|./waf build$|./waf build -j'$(nproc)'|' debian/rules

rm -rf debian/source

(
  echo "${PROJ} (${PKGVER}) ${DISTRO}; urgency=medium"
  echo "  * Automated build of version ${SRCVER}"
  echo " -- Junxiao Shi <deb@mail1.yoursunny.com>  $(date -R)"
) > debian/changelog

# dh-systemd is part of debhelper, and has been removed in bullseye
sed -i -e '/\bdh-systemd\b/ d' debian/control

if [[ $PROJ == 'nlsr' ]]; then
  # as of 2021-04-07, NLSR does not need ChronoSync, but ppa-packaging is not yet updated
  sed -i -e '/\blibchronosync-dev\b/ d' debian/control
fi

if [[ -n $DEPVER_PKG ]]; then
  # ndn-cxx and PSync do not have a stable ABI, so the dependent should depend on exact version
  sed -i -E \
    -e "/^Depends:.*shlibs:Depends/ s|, ${DEPVER_PKG}\b||" \
    -e "/^Depends:/ s|(\\\$\{shlibs:Depends\})|${DEPVER_PKG} (= ${DEP_PKGVER}), \1|" \
    debian/control
fi

mk-build-deps -ir -t "apt-get -y -o Debug::pkgProblemResolver=yes --no-install-recommends"
debuild -us -uc

cd /source
find -not -name '*.deb' -delete
