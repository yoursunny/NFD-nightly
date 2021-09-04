#!/bin/bash
set -eo pipefail
PROJ=$1
REPO=$2
GROUP=$3
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
# as of 2021-08-18, all packages use Python 3, but ppa-packaging is not yet updated
sed -i -E \
  -e '/dh-systemd/ d' \
  -e 's/python \([^)]+\)/python3 (>= 3.6.0)/' \
  -e 's/python2.7-minimal/python3-minimal/' \
  debian/control

if [[ $PROJ == 'nlsr' ]]; then
  # as of 2021-04-07, NLSR does not need ChronoSync, but ppa-packaging is not yet updated
  sed -i -e '/libchronosync-dev/ d' debian/control
fi

# delete unnecessary sudo-to-root
# replace sudo-to-user with gosu, which is safer in Docker
find debian -name '*.postinst' | xargs --no-run-if-empty sed -i -E \
  -e 's/^(\s*)sudo -u (\S+) -g (\S+)/\1gosu \2:\3 env/' \
  -e 's/^(\s*)sudo /\1/'
for F in $(grep -l 'gosu ' debian/*.postinst || true); do
  awk -i inplace -vPKG=$(basename -s .postinst $F) '
    $1=="Package:" && $2==PKG { matching = 1 }
    matching==1 && $1=="Depends:" { $1 = $1 " gosu," }
    NF==0 { matching = 0 }
    { print }
  ' debian/control
done

BOOST_VER=$(apt-cache show libboost-dev | awk '$1=="Depends:" { gsub("libboost|-dev","",$2); print $2 }')
BOOST_PKGS=(
  atomic
  chrono
  date-time
  filesystem
  iostreams
  log
  program-options
  regex
  stacktrace
  system
  thread
)
BOOST_PKGS_REPL=$(echo "${BOOST_PKGS[@]}" | sed -E -e "s/\S+/libboost-\\0${BOOST_VER}-dev\\\\1/g" -e 's/\s+/,\0/g')
sed -i -E "s|libboost-all-dev( \\([^)]*\\))?|${BOOST_PKGS_REPL}|" debian/control

if [[ -n $DEPVER_PKG ]]; then
  # ndn-cxx and PSync do not have a stable ABI, so that dependents should depend on exact version
  sed -i -E \
    -e "/^Depends:.*shlibs:Depends/ s|, ${DEPVER_PKG}\b||" \
    -e "/^Depends:/ s|(\\\$\{shlibs:Depends\})|${DEPVER_PKG} (= ${DEP_PKGVER}), \1|" \
    debian/control
fi

mk-build-deps -ir -t "apt-get -y -o Debug::pkgProblemResolver=yes --no-install-recommends"
debuild -us -uc

cd /source
find -not -name '*.deb' -delete
if [[ $PROJ == 'nlsr' ]]; then
  rm -f ndn-cxx_*.deb ndn-cxx-dbg_*.deb ndn-cxx-dev_*.deb
fi
