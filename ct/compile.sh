#!/bin/bash
set -e
set -o pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -qq --no-install-recommends ca-certificates devscripts equivs git lsb-release python
DISTRO=$(lsb_release -sc)

mkdir -p /source /output

cd /source
git clone --recursive --depth=1 https://github.com/named-data/ppa-packaging.git
git clone --recursive --depth=1 https://github.com/named-data/ndn-cxx.git
git clone --recursive --depth=1 https://github.com/named-data/NFD.git nfd
git clone --recursive --depth=1 https://github.com/named-data/ndn-tools.git

for PKG in ndn-cxx nfd ndn-tools; do
  cd /source/$PKG
  ./waf version
  PKGVER=$(cat VERSION.info)
  cp -R ../ppa-packaging/$PKG/debian .
  rm -rf debian/source
  (
    echo "$PKG ($PKGVER-nightly~$DISTRO) $DISTRO;"
    echo "  * Automated build of version $PKGVER"
    echo " -- Junxiao Shi <deb@mail1.yoursunny.com>  $(date -R)"
  ) > debian/changelog
  mk-build-deps -ir -t "apt-get -qq --no-install-recommends"
  debuild -us -uc
  dpkg -i ../*.deb || apt-get install -f -qq
  mv ../*.deb /output/
done
