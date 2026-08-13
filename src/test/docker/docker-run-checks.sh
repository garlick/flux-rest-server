#!/bin/bash
#
#  Build a flux-rest-server "checks" docker image from a base fluxrm/flux-core
#  image and run the testsuite inside it as the current user and group.  The
#  flux broker refuses to run as root, so the image bakes in a user matching
#  the host UID and the source tree is bind-mounted and built under that user.
#
#  Arguments after `--` are passed through to ./configure.
#
PROJECT=flux-rest-server
BASE_DOCKER_REPO=fluxrm/flux-core

WORKDIR=/usr/src
IMAGE=bookworm
JOBS=2

declare -r prog=${0##*/}
die() { echo -e "$prog: $@"; exit 1; }

declare -r long_opts="help,quiet,interactive,image:,jobs:,no-cache,distcheck,recheck"
declare -r short_opts="hqIdi:j:r"
declare -r usage="
Usage: $prog [OPTIONS] -- [CONFIGURE_ARGS...]\n\
Build a docker image for CI and run the testsuite inside it as the current\n\
user and group, using the current git checkout.\n\
\n\
Options:\n\
 -h, --help          Display this message\n\
     --no-cache      Disable docker layer caching\n\
 -q, --quiet         Pass --quiet to docker build\n\
 -i, --image=NAME    Base image distro tag (default=$IMAGE)\n\
 -j, --jobs=N        Value for make -j (default=$JOBS)\n\
 -d, --distcheck     Run 'make distcheck' instead of 'make check'\n\
 -r, --recheck       Run 'make recheck' after a failed 'make check'\n\
 -I, --interactive   Run an interactive shell instead of the testsuite\n\
"

GETOPTS=$(/usr/bin/getopt -u -o $short_opts -l $long_opts -n $prog -- "$@") \
    || die "$usage"
eval set -- "$GETOPTS"
while true; do
    case "$1" in
      -h|--help)         echo -ne "$usage";       exit 0  ;;
      -q|--quiet)        QUIET="--quiet";          shift   ;;
      -i|--image)        IMAGE="$2";               shift 2 ;;
      -j|--jobs)         JOBS="$2";                shift 2 ;;
      -d|--distcheck)    DISTCHECK=t;              shift   ;;
      -r|--recheck)      RECHECK=t;                shift   ;;
      -I|--interactive)  INTERACTIVE="/bin/bash";  shift   ;;
      --no-cache)        NO_CACHE="--no-cache";    shift   ;;
      --)                shift; break;                     ;;
      *)                 die "Invalid option '$1'\n$usage"  ;;
    esac
done

TOP=$(git rev-parse --show-toplevel 2>&1) \
    || die "not inside $PROJECT git repository!"
which docker >/dev/null \
    || die "unable to find a docker binary"
if docker buildx version >/dev/null 2>&1; then
    DOCKER_BUILD="docker buildx build --load"
else
    DOCKER_BUILD="docker build"
fi

CONFIGURE_ARGS="$@"

. ${TOP}/src/test/checks-lib.sh

BUILD_IMAGE=${PROJECT}-checks:${IMAGE}

# A single Dockerfile serves every distro: it only layers a host-UID user onto
# the base image (the server is pure-Python, so there are no per-distro build
# dependencies to install).  The base image is selected by build arg.
checks_group "Building $IMAGE image for $USER ($(id -u):$(id -g))" \
  ${DOCKER_BUILD} \
    ${NO_CACHE} \
    ${QUIET} \
    -f ${TOP}/src/test/docker/Dockerfile \
    --build-arg BASE_IMAGE="$BASE_DOCKER_REPO:$IMAGE" \
    --build-arg USER=$USER \
    --build-arg UID=$(id -u) \
    -t ${BUILD_IMAGE} \
    ${TOP}/src/test/docker \
    || die "docker build failed"

echo "mounting $TOP as $WORKDIR"

export JOBS DISTCHECK RECHECK PROJECT

docker run --rm \
    --workdir=$WORKDIR \
    --volume=$TOP:$WORKDIR \
    -e JOBS \
    -e DISTCHECK \
    -e RECHECK \
    -e TEST_INSTALL \
    -e PROJECT \
    -e CI \
    -e TAP_DRIVER_QUIET \
    -e FLUX_TEST_TIMEOUT \
    -e FLUX_TEST_SIZE_MAX \
    --tty \
    ${INTERACTIVE:+--interactive} \
    --network=host \
    ${BUILD_IMAGE} \
    ${INTERACTIVE:-./src/test/checks_run.sh ${CONFIGURE_ARGS}} \
    || die "docker run failed"
