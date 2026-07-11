/*
 * mayhem/run_tests.c - test runner for librdkafka internal unit tests.
 *
 * Links against the NORMAL (non-sanitized) librdkafka.a built by build.sh.
 * Calls rd_kafka_unittest() which runs all internal unit tests (data structure
 * tests, hash functions, buffer ops, config parsing, etc.) — all offline.
 *
 * Output (to stderr via RD_UT_SAY): lines like
 *   "RDUT: INFO: ...: unittest: NAME:  PASS"
 *   "RDUT: INFO: ...: unittest: NAME:  FAIL"
 *
 * Exit code: 0 = all pass, non-zero = failures.
 * test.sh parses the PASS/FAIL counts from stderr.
 *
 * Anti-reward-hack: if this binary is neutered to exit(0), test.sh sees
 * 0 tests and 0 passes, detects the anomaly, and reports failure.
 */
#include <stdio.h>
#include <stdlib.h>

/* rd_kafka_unittest is declared in the rdkafka.h API */
#include "rdkafka.h"

int main(void) {
        int fails = rd_kafka_unittest();
        if (fails)
                fprintf(stderr, "UNIT_TEST_SUMMARY: FAILED (%d failures)\n", fails);
        else
                fprintf(stderr, "UNIT_TEST_SUMMARY: PASSED\n");
        return fails == 0 ? 0 : 1;
}
