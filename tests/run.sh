#!/bin/sh
# Checks every package here, as CI does: each type-checks on its own with
# no warnings, it's formatted, and the tests in its tests/lib.t (a
# dependent, by path) pass. Run from anywhere; `t` must be on PATH.
set -eu
cd "$(dirname "$0")/.."

for lib in */lib.t; do
    pkg=$(dirname "$lib")
    echo "== $pkg"
    t check --deny-warnings "$lib"
    find "$pkg" -name '*.t' -exec t fmt --check {} +
    if [ -f "$pkg/tests/lib.t" ]; then
        t test --deny-warnings "$pkg/tests/lib.t"
    fi
done
