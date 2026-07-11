#!/usr/bin/env bash
#
# mayhem/build.sh — build librdkafka fuzz harness and test runner.
# Target: fuzz_regex — fuzzes the built-in regexp engine (src/regexp.c)
# Harness: tests/fuzzers/fuzz_regex.c
#
# Air-gapped: uses apt-installed system libs (libssl-dev, libzstd-dev,
# zlib1g-dev, libsasl2-dev) installed in the Dockerfile — no downloads here.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/usr/lib/libFuzzingEngine.a}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

SRC="${SRC:-/mayhem}"
cd "$SRC"

# Extract link flags from Makefile.config (works after ./configure)
# Makefile.config has: "LIBS+=\t-lm -lssl -lcrypto ..."
extract_link_flags() {
    grep "^LIBS+=" Makefile.config | sed 's/^LIBS+=//' | xargs
}

# ── Step 1: Sanitized library build (for fuzzing) ────────────────────────────
# Build with ASan+UBSan + -fsanitize=fuzzer-no-link so SanitizerCoverage
# instruments the library code (not just the harness TU).
echo "[build.sh] Building sanitized librdkafka for fuzzing..."

# Clean any prior configure/build state
make distclean 2>/dev/null || true

# mklove reads CC/CXX/CFLAGS/CXXFLAGS from the environment.
CC="$CC" CXX="$CXX" \
    CFLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS" \
    CXXFLAGS="$SANITIZER_FLAGS -fsanitize=fuzzer-no-link $DEBUG_FLAGS" \
    ./configure \
        --disable-regex-ext \
        --no-cache

make libs -j"$MAYHEM_JOBS"

LIBRDKAFKA_FUZZ="$SRC/src/librdkafka.a"
LINK_FLAGS=$(extract_link_flags)
echo "[build.sh] Link flags: $LINK_FLAGS"

# ── Step 2: Compile fuzz harness ─────────────────────────────────────────────
echo "[build.sh] Compiling fuzz_regex harness..."
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
    -I"$SRC/src" \
    "$SRC/tests/fuzzers/fuzz_regex.c" \
    "$LIBRDKAFKA_FUZZ" \
    $LINK_FLAGS \
    -o /mayhem/fuzz_regex

# ── Step 3: Compile standalone reproducer ────────────────────────────────────
echo "[build.sh] Compiling fuzz_regex-standalone reproducer..."
# Compile driver as C to preserve LLVMFuzzerTestOneInput C linkage
$CC $SANITIZER_FLAGS $DEBUG_FLAGS \
    -c "$STANDALONE_FUZZ_MAIN" \
    -o /tmp/standalone_main.o

$CC $SANITIZER_FLAGS $DEBUG_FLAGS \
    -I"$SRC/src" \
    "$SRC/tests/fuzzers/fuzz_regex.c" \
    /tmp/standalone_main.o \
    "$LIBRDKAFKA_FUZZ" \
    $LINK_FLAGS \
    -o /mayhem/fuzz_regex-standalone

# ── Step 4: Normal build for the test runner ─────────────────────────────────
echo "[build.sh] Building librdkafka with normal flags for test runner..."
make distclean 2>/dev/null || true

CC="$CC" CXX="$CXX" \
    CFLAGS="-O2 $COVERAGE_FLAGS" \
    CXXFLAGS="-O2 $COVERAGE_FLAGS" \
    ./configure \
        --disable-regex-ext \
        --no-cache

make libs -j"$MAYHEM_JOBS"

LIBRDKAFKA_TEST="$SRC/src/librdkafka.a"
TEST_LINK_FLAGS=$(extract_link_flags)
echo "[build.sh] Test link flags: $TEST_LINK_FLAGS"

# ── Step 5: Compile the test runner ─────────────────────────────────────────
echo "[build.sh] Compiling test runner (run_tests)..."
$CC -O2 $COVERAGE_FLAGS \
    -I"$SRC/src" \
    "$SRC/mayhem/run_tests.c" \
    "$LIBRDKAFKA_TEST" \
    $TEST_LINK_FLAGS \
    -o /mayhem/run_tests

echo "[build.sh] Done. Binaries:"
ls -lh /mayhem/fuzz_regex /mayhem/fuzz_regex-standalone /mayhem/run_tests
