#!/bin/bash
# Install debian build dependencies for flux-rest-server

apt install \
  autoconf \
  automake \
  make \
  debhelper \
  dh-python \
  python3-all \
  python3-setuptools \
  flux-core \
  python3-pytest

