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
) >debian/changelog

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
  BOOST_PKGS=$( (
    tee <<EOT
stacktrace_backend, candidate = '', ''
LIBS = set()
class Conf:
  def check_boost(self, **kwds):
    lib = kwds.get('lib', [])
    if type(lib) == str:
      lib = lib.split(' ')
    LIBS.update(lib)
conf = Conf()
EOT
    gawk '$0~/boost_libs/ || $0~/conf\.check_boost/ { sub(/^[ \t]*/, "", $0); print }' wscript
    tee <<EOT
LIBS.discard('unit_test_framework')
if 'stacktrace_' in LIBS:
  LIBS.discard('stacktrace_')
  LIBS.add('stacktrace')
print(",".join([("libboost-%s-dev" % x.replace("_","-")) for x in LIBS]))
EOT
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

# as of 2025-04-20, ndn-tools has several binaries and manpages renamed
if [[ $PROJ == ndn-tools ]]; then
  sed -i \
    -e '1 i\usr/bin/ndndissect' \
    -e 's|ndn-dissect\.1|ndndissect.1|' \
    debian/ndn-dissect.install
  sed -i \
    -e '1 i\usr/bin/ndnget' \
    -e '1 i\usr/bin/ndnserve' \
    -e '1 i\usr/share/man/man1/ndnserve.1' \
    debian/ndnchunks.install
fi

# neither ndn-cxx nor PSync has a stable ABI, so that dependents should depend on exact version
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
