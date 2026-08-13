#
#  Helper functions for grouping CI output.  Under GitHub Actions these emit
#  workflow "group" commands so each build step is collapsible in the log; see
#  https://docs.github.com/actions/reference/workflow-commands-for-github-actions
#
if test "$CI" = "true"; then
  checks_group_start() {
    printf "::group::%s\n" "$1"
  }
  checks_group_end() {
    printf "::endgroup::\n"
  }
else
  checks_group_start() { echo "$@"; }
  checks_group_end()   { echo "$@"; }
fi

#
#  Usage: checks_group DESC COMMANDS...
#
checks_group() {
    local DESC="$1"
    shift 1
    checks_group_start "$DESC"
    eval "$@"
    rc=$?
    checks_group_end
    return $rc
}
