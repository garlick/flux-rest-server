ARG BASE_IMAGE=fluxrm/flux-core:bookworm
FROM ${BASE_IMAGE}

#  The testsuite drives the server with the curl CLI, which the fluxrm base
#  images do not ship (flux-core's own tests do not use it).  Install it only
#  where it is actually missing: Debian/Ubuntu minimal images lack it, while
#  RHEL-family images already provide it via curl-minimal -- and there
#  `dnf install curl` would fail with a curl/curl-minimal conflict.
RUN if ! command -v curl >/dev/null 2>&1; then \
        if command -v apt-get >/dev/null 2>&1; then \
            sudo apt-get update \
         && sudo apt-get install -y --no-install-recommends curl \
         && sudo rm -rf /var/lib/apt/lists/*; \
        elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y curl; \
        elif command -v yum >/dev/null 2>&1; then sudo yum install -y curl; \
        elif command -v apk >/dev/null 2>&1; then sudo apk add --no-cache curl; \
        else echo "no known package manager to install curl" >&2; exit 1; \
        fi; \
    fi

#  Create a user matching the host UID so the bind-mounted source tree is
#  writable and the flux broker -- which refuses to run as root -- has a valid
#  passwd entry to run the testsuite under.  The base image already provides
#  everything needed to build (autotools + python); the server itself is
#  pure-Python standard library, so no further runtime deps are needed.
ARG USER=fluxuser
ARG UID=1000
RUN if test "$USER" != "fluxuser"; then \
        sudo groupadd -g $UID $USER \
     && sudo useradd -g $USER -u $UID -d /home/$USER -m $USER \
     && sudo sh -c "printf '%s ALL=(ALL) NOPASSWD: ALL\n' $USER >> /etc/sudoers"; \
    fi

USER $USER
WORKDIR /home/$USER
