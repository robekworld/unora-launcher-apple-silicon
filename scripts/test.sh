#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
python3 -m unittest discover -s tests -p 'test_*.py' -v
xcrun clang -fobjc-arc -fblocks -arch arm64 -mmacosx-version-min=12.0 \
  -Wall -Wextra -Werror -Wno-unused-parameter -framework Cocoa \
  tests/host_tests.m -o build/host-tests
./build/host-tests
