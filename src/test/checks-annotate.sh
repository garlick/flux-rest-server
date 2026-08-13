#!/bin/bash
#
#  Post-process testsuite logs and outputs after a failure and emit them
#  using GitHub Actions workflow commands so the cause is visible in the job
#  log.  Run as a separate `if: failure()` workflow step, after the container
#  has exited -- the sharness *.output, automake *.log, and *.trs files are
#  left behind in the bind-mounted source tree.
#
error() {
    printf "::error::$@\n"
}
catfile() {
    if test -f $1; then
        printf "::group::%s\n" "$1"
        cat $1
        printf "::endgroup::\n"
    fi
}
annotate_test_log() {
    #
    #  Look through a test's automake .log for failure indicators and emit a
    #  GH '::error::' annotation pinned to the .t file for each one.
    #
    local test=$1

    #  One annotation per failed assertion ('not ok'):
    grep 'not ok' ${test}.log | while read line; do
        printf "::error file=${test}.t::%s\n" "${line}"
    done

    #  One annotation per TAP driver ERROR line:
    grep '^ERROR: ' ${test}.log | while read line; do
        printf "::error file=${test}.t::%s\n" "${line}"
    done
}

#
#  Scan every automake .trs result file and, for any test whose global result
#  was not PASS or SKIP, annotate it and dump its .output (verbose sharness
#  log) and .log (TAP output).
#
logfile=$(mktemp)

errors=0
total=0
for trs in $(find . -name '*.trs'); do
    : $((total++))
    result=$(sed -n 's/^.*global-test-result: *//p' ${trs})
    if test "$result" != "PASS" -a "$result" != "SKIP"; then
        testbase=${trs%.trs}
        annotate_test_log $testbase >> $logfile
        catfile ${testbase}.output >> $logfile
        catfile ${testbase}.log >> $logfile
        : $((errors++))
    fi
done
if test $errors -gt 0; then
    printf "::warning::"
fi
printf "Found ${errors} errors from ${total} tests in testsuite\n"
cat $logfile
rm -f $logfile

#
#  Report any expected tests that produced no .trs file at all (i.e. never
#  ran) -- these have no result above to annotate.
#
ls -1 t/*.t 2>/dev/null | sort >/tmp/expected.$$
ls -1 t/*.trs 2>/dev/null | sed 's/rs$//' | sort >/tmp/actual.$$
if comm -23 /tmp/expected.$$ /tmp/actual.$$ | grep -q .; then
    error "Detected tests that did not run:"
    for f in $(comm -23 /tmp/expected.$$ /tmp/actual.$$); do
        printf "%s\n" "$f"
        catfile "${f%.t}.log"
        catfile "${f%.t}.output"
    done
else
    printf "No missing test runs detected\n"
fi
rm -f /tmp/expected.$$ /tmp/actual.$$
