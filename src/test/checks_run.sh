#!/bin/bash
#
#  Testsuite runner, executed inside the CI docker container by
#  docker-run-checks.sh.  Any arguments are passed through to ./configure.
#
#  Influenced by the following environment variables:
#
#    JOBS          value for make's -j option (default 2)
#    DISTCHECK     run 'make distcheck' instead of 'make check' if set to "t"
#    TEST_INSTALL  'make install' and run 'make check' against the installed
#                  copy if set to "t"
#    RECHECK       run 'make recheck' after a failed 'make check' if set to "t"
#
. src/test/checks-lib.sh

ARGS="$@"
JOBS=${JOBS:-2}
MAKE="make --no-print-directory"
MAKECMDS="${MAKE} -j${JOBS}"
CHECKCMDS="${MAKE} -j${JOBS} ${DISTCHECK:+dist}check"

# Keep CI flux instances small to avoid spurious timeouts and capture sharness
# logs so failures can be diagnosed from the CI output.
export FLUX_TEST_SIZE_MAX=5
export FLUX_TESTS_LOGFILE=t

# The version comes from git-describe, which needs tags; a shallow CI clone may
# lack them.  Ignore the error when the clone is already complete.
checks_group "git fetch tags" git fetch --unshallow --tags || true

if test "$TEST_INSTALL" = "t"; then
    # Install alongside flux-core (prefix /usr) so that `flux rest-server`
    # resolves the installed subcommand, then run the suite against it.
    ARGS="$ARGS --prefix=/usr --sysconfdir=/etc"
    CHECKCMDS="sudo make install && \
               FLUX_TEST_INSTALLED_PATH=/usr ${MAKE} -j${JOBS} check"
fi

export DISTCHECK_CONFIGURE_FLAGS="${ARGS}"

checks_group "autogen.sh" ./autogen.sh
checks_group "configure ${ARGS}" ./configure ${ARGS} \
    || (printf "::error::configure failed\n"; cat config.log; exit 1)
checks_group "make clean" make clean

if test "$DISTCHECK" != "t"; then
    checks_group "${MAKECMDS}" ${MAKECMDS} \
        || (printf "::error::${MAKECMDS} failed\n"; exit 1)
fi

checks_group "${CHECKCMDS}" "${CHECKCMDS}"
RC=$?

if test "$RECHECK" = "t" -a $RC -ne 0 -a -s t/t0000-sharness.trs; then
    printf "::warning::make check failed; running recheck in ./t\n"
    (cd t && checks_group "make recheck" ${MAKE} -j${JOBS} recheck)
    RC=$?
fi

exit $RC
