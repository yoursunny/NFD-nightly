#!/bin/bash
BASEIMG=$1
OUTPUTDIR=$HOME/output

if [[ $BASEIMG == balenalib* ]]; then
  ENTRYPOINT='--entrypoint /usr/bin/qemu-arm-static'
  ENTRYPOINTARG='--execve -0 bash'
fi

docker run -v $OUTPUTDIR:/output -w=/root --rm $ENTRYPOINT $BASEIMG $ENTRYPOINTARG /bin/bash -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -qq --no-install-recommends ca-certificates devscripts equivs git lsb-release python
  DISTRO=$(lsb_release -sc)

  git clone --recursive https://github.com/named-data/ppa-packaging.git
  git clone --recursive https://github.com/named-data/ndn-cxx.git
  git clone --recursive https://github.com/named-data/NFD.git nfd
  git clone --recursive https://github.com/named-data/ndn-tools.git

  for PKG in ndn-cxx nfd ndn-tools; do
    cd ~/$PKG
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
    dpkg -i ../*.deb
    mv ../*.deb /output/
  done
'
