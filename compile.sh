#!/bin/bash
set -eo pipefail
PROJ=$1
REPO=$2

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -qq --no-install-recommends ca-certificates devscripts equivs git lsb-release python3
DISTRO=$(lsb_release -sc)

mkdir -p /source

cd /source
git clone --recursive --depth=1 https://github.com/named-data/ppa-packaging.git
git clone --recursive $REPO $PROJ # `./waf version` needs full clone

if [[ -d /deps ]]; then
  cd /deps
  dpkg -i *.deb || apt-get install -f -qq
fi

cd /source/$PROJ
./waf version
PKGVER=$(cat VERSION.info)
cp -R ../ppa-packaging/$PROJ/debian .
sed -i '/override_dh_auto_build/,/^$/ s|./waf build$|./waf build -j'$(nproc)'|' debian/rules
rm -rf debian/source
(
  echo "$PROJ ($PKGVER-nightly~$DISTRO) $DISTRO;"
  echo "  * Automated build of version $PKGVER"
  echo " -- Junxiao Shi <deb@mail1.yoursunny.com>  $(date -R)"
) > debian/changelog
mk-build-deps -ir -t "apt-get -qq --no-install-recommends"
debuild -us -uc

cd /source
find -not -name '*.deb' -delete
