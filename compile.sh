#!/bin/bash
set -euo pipefail
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

if [[ -x ./waf ]] && ./waf version && [[ -f VERSION.info ]]; then
  SRCVER=$(cat VERSION.info)
else
  SRCVER=$(git show -s --format='%ct %H' | gawk '{ printf "0.0.0-%s-%s", strftime("%Y%m%d%H%M%S", $1), substr($2,1,12) }')
fi
PKGVER="${SRCVER}-nightly"

DEPVER_PKG=
DEPVER_LABEL=
if [[ $GROUP -eq 2 ]]; then
  DEPVER_PKG=libpsync
  DEPVER_LABEL=psync
elif [[ $GROUP -eq 1 ]]; then
  DEPVER_PKG=libndn-cxx
  DEPVER_LABEL=ndncxx
fi
if [[ -n $DEPVER_PKG ]]; then
  # ndn-cxx and PSync do not have a stable ABI, so the dependent version should contain their versions
  DEP_PKGVER=$(dpkg -s ${DEPVER_PKG} | gawk '$1=="Version:" { print $2 }')
  DEP_SRCVER=${DEP_PKGVER/~${DISTRO}/}
  DEP_SRCVER=${DEP_SRCVER/-nightly/}
  DEP_SRCVER=${DEP_SRCVER//-/.}
  PKGVER="${PKGVER}~${DEPVER_LABEL}${DEP_SRCVER}"
fi
PKGVER="${PKGVER}~${DISTRO}"

if ! [[ -d debian ]] && [[ -d ../ppa-packaging/$PROJ ]]; then
  cp -R ../ppa-packaging/$PROJ/debian .
fi

# enable parallel builds
# create automatic dbgsym packages
sed -i \
  -e '/override_dh_auto_build/,/^$/ s|./waf build$|./waf build -j'$(nproc)'|' \
  -e '/dh_strip/ d' \
  debian/rules
sed -i '/^Package: .*-dbg/,/^$/ d' debian/control

# use local source
rm -rf debian/source

# declare version
(
  echo "${PROJ} (${PKGVER}) ${DISTRO}; urgency=medium"
  echo "  * Automated build of version ${SRCVER}"
  echo " -- Junxiao Shi <deb@mail1.yoursunny.com>  $(date -R)"
) > debian/changelog

# delete unnecessary sudo-to-root
# replace sudo-to-user with gosu, which is safer in Docker
find debian -name '*.postinst' | xargs --no-run-if-empty sed -i -E \
  -e 's/^(\s*)sudo -u (\S+) -g (\S+)/\1gosu \2:\3 env/' \
  -e 's/^(\s*)sudo /\1/'
for F in $(grep -l 'gosu ' debian/*.postinst || true); do
  gawk -i inplace -vPKG=$(basename -s .postinst $F) '
    $1=="Package:" && $2==PKG { matching = 1 }
    matching==1 && $1=="Depends:" { $1 = $1 " gosu," }
    NF==0 { matching = 0 }
    { print }
  ' debian/control
done
gawk -i inplace '
  $1=="Depends:" { sub(/, sudo(\s[^,]+)?/, "", $0) }
  { print }
' debian/control

# replace Build-Depends libboost-all-dev with fewer packages
if [[ -f wscript ]] && [[ -f .waf-tools/boost.py ]]; then
  BOOST_PKGS=$((
    echo 'stacktrace_backend = ""'
    echo 'boost_libs = []'
    gawk '$0~/boost_libs/ && $0!~/conf\.check_boost/ { sub(/^[ \t]*/, "", $0); print }' wscript
    echo 'if type(boost_libs)==str:'
    echo '  boost_libs = boost_libs.split(" ")'
    echo 'boost_libs = set(boost_libs)'
    echo 'boost_libs.discard("unit_test_framework")'
    echo 'if "stacktrace_" in boost_libs:'
    echo '  boost_libs.discard("stacktrace_")'
    echo '  boost_libs.add("stacktrace")'
    echo 'print(",".join([("libboost-%s-dev" % x.replace("_","-")) for x in boost_libs]))'
  ) | python3)
else
  BOOST_PKGS=$(echo 'atomic chrono date-time filesystem iostreams log program-options regex stacktrace system thread' |
               sed -E -e "s/\S+/libboost-\\0-dev/g" -e 's/\s+/,/g')
fi
sed -i -E "s|libboost-all-dev( \\([^)]*\\))?|${BOOST_PKGS}|" debian/control

# as of 2022-05-01, libndn-cxx-dev is not listing some Boost libraries but they are still referenced in libndn-cxx.pc
if [[ $PROJ == ndn-cxx ]]; then
  gawk -i inplace -v BoostPkgs=${BOOST_PKGS} '
    $1=="Package:" { in_dev = $2=="libndn-cxx-dev" }
    in_dev && $1=="Depends:" { in_depends = 1 }
    in_depends {
      if (match($0, "libboost-[^-]+-dev")) {
        BoostDepends[substr($0, RSTART, RLENGTH)] = 1
      }
      if (substr($0, 1, 1) == " " && substr($0, length($0)) != ",") {
        nBoostPkgs = split(BoostPkgs, BoostPkgsA, ",")
        for (i=1; i<=nBoostPkgs; i++) {
          if (!BoostDepends[BoostPkgsA[i]]) {
            print " " BoostPkgsA[i] ","
          }
        }
        in_depends = 0
      }
    }
    { print }
  ' debian/control
fi

# ndn-cxx and PSync do not have a stable ABI, so that dependents should depend on exact version
if [[ -n $DEPVER_PKG ]]; then
  sed -i -E \
    -e "/^Depends:.*shlibs:Depends/ s|, ${DEPVER_PKG}\b||" \
    -e "/^Depends:/ s|(\\\$\{shlibs:Depends\})|${DEPVER_PKG} (= ${DEP_PKGVER}), \1|" \
    debian/control
fi

mk-build-deps -ir -t "apt-get -y -o Debug::pkgProblemResolver=yes --no-install-recommends"
debuild -us -uc

cd /source
find -not -name '*.deb' -delete
