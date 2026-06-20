# Minimal flux-sharness for flux-rest-server

export FLUX_EXEC_PATH_PREPEND="${SHARNESS_TEST_SRCDIR}/scripts":"${SHARNESS_TEST_SRCDIR}/../src/cmd"

# Simple test_under_flux that just re-execs under flux start
test_under_flux() {
    size=${1:-1}

    if test -n "$TEST_UNDER_FLUX_ACTIVE" ; then
        return
    fi

    # Name the log after the test (e.g. t1000-basic.broker.log) so it is both
    # identifiable and removed by the *.broker.log rule in clean-local. (Using
    # $TEST_NAME directly yields ".broker.log", a dotfile the glob misses,
    # which then survives distclean and fails distcheck.)
    log_file="$(basename "$0" .t).broker.log"
    flags=""
    if test "$verbose" = "t"; then
        flags="${flags} --verbose"
    fi
    if test "$debug" = "t"; then
        flags="${flags} --debug"
    fi

    # cd to test directory if set (sharness sets this)
    if test -n "$SHARNESS_TEST_DIRECTORY"; then
        cd $SHARNESS_TEST_DIRECTORY
    fi

    TEST_UNDER_FLUX_ACTIVE=t \
      exec flux start --test-size=${size} \
          -o -Slog-filename=${log_file} \
          "sh $0 ${flags}"
}

