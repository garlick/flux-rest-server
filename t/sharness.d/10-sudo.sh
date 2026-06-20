##
# Is non-interactive sudo (or doas) available?  Tests that must connect as a
# different uid use this to exercise the SO_PEERCRED access check.
##
if sudo --non-interactive true >/dev/null 2>&1; then
    test_set_prereq SUDO
    SUDO="sudo -E"
elif _probeenv=xyz doas -n printenv _probeenv >/dev/null 2>&1; then
    test_set_prereq SUDO
    SUDO="doas"
fi
