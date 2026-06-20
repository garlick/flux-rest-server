#!/bin/sh
PACKAGE=flux-rest-server
USER=$(git config --get user.name)
DEBFULLNAME=$USER
EMAIL=$(git config --get user.email)
DEBEMAIL=$EMAIL

SRCDIR=${1:-$(pwd)}

die() { echo "debbuild: $@" >&2; exit 1; }
log() { echo "debbuild: $@"; }

test -z "$USER" && die "User name not set in git-config"
test -z "$EMAIL" && die "User email not set in git-config"

log "Running make dist"
make dist >/dev/null || exit 1

log "Building package from latest dist tarball"
tarball=$(ls -tr *.tar.gz 2>/dev/null | tail -1)
test -f "$tarball" || die "No tarball found (run make dist first)"
version=$(echo $tarball | sed "s|${PACKAGE}-\(.*\)\.tar\.gz|\1|")

# dpkg requires the version to begin with a digit. An untagged tree yields a
# bare "git describe" hash (e.g. ab07b68); synthesize a valid placeholder so
# test builds work. Tag the tree, or set FLUX_REST_SERVER_VERSION before
# ./autogen.sh, for a meaningful version.
case "$version" in
    [0-9]*) debversion=$version ;;
    *)      debversion="0.0.0+$version" ;;
esac

rm -rf debbuild
mkdir -p debbuild && cd debbuild

cp ../$tarball .

log "Unpacking $tarball"
tar xvfz $(basename $tarball) >/dev/null

log "Creating debian directory and files"
cd ${PACKAGE}-${version}
cp -a ${SRCDIR}/debian . || die "failed to copy debian dir"

export DEBEMAIL DEBFULLNAME
log "Creating debian/changelog"
dch --create --package=$PACKAGE --newversion $debversion build tree release

log "Running dpkg-buildpackage -b"
dpkg-buildpackage -b -us -uc
log "Check debbuild directory for results"
