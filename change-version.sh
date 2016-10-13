#!/bin/sh -xe

make clean || true

perl -p -i -e "s/\\b$1\\b/$2/ if /VERSION\s*=/" \
    bin/* \
    lib/Devel/NYTProf.pm lib/Devel/NYTProf/Core.pm

ack --literal "$1"
ack --literal "$2"
