#!/bin/bash
set -e
set -o pipefail
PROJ=$1

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -qq --no-install-recommends ca-certificates devscripts equivs git lsb-release python3
DISTRO=$(lsb_release -sc)

mkdir -p /deps /source

cd /source
git clone --recursive --depth=1 https://github.com/named-data/ppa-packaging.git
case $PROJ in
  ndn-cxx)
    git clone --recursive https://github.com/named-data/ndn-cxx.git
    ;;
  nfd)
    git clone --recursive https://github.com/named-data/NFD.git nfd
    ;;
  ndn-tools)
    git clone --recursive https://github.com/named-data/ndn-tools.git
    ;;
esac

if [[ -f /deps.txz ]]; then
  cd /deps
  tar xJf /deps.txz
  dpkg -i *.deb || apt-get install -f -qq
fi

cd /source/$PROJ
./waf version
PKGVER=$(cat VERSION.info)
cp -R ../ppa-packaging/$PROJ/debian .
sed -i '/override_dh_auto_build/,/^$/ s|./waf build$|./waf build -j2|' debian/rules
rm -rf debian/source
(
  echo "$PROJ ($PKGVER-nightly~$DISTRO) $DISTRO;"
  echo "  * Automated build of version $PKGVER"
  echo " -- Junxiao Shi <deb@mail1.yoursunny.com>  $(date -R)"
) > debian/changelog
mk-build-deps -ir -t "apt-get -qq --no-install-recommends"
debuild -us -uc

cd /source
tar cJf /output.txz *.deb
