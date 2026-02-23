#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="${IMAGE_TAG:-bluesky-queueserver-api-test:local}"
WORKER_COUNT="${WORKER_COUNT:-${SHARD_COUNT:-3}}"
CHUNK_COUNT="${CHUNK_COUNT:-}"
PYTEST_EXTRA_ARGS="${PYTEST_EXTRA_ARGS:-}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT_DIR/.docker-test-artifacts}"

if [[ "$WORKER_COUNT" -lt 1 ]]; then
    echo "WORKER_COUNT must be >= 1" >&2
    exit 2
fi

if [[ -z "$CHUNK_COUNT" ]]; then
    CHUNK_COUNT=$(( WORKER_COUNT * 3 ))
fi

if [[ "$CHUNK_COUNT" -lt 1 ]]; then
    echo "CHUNK_COUNT must be >= 1" >&2
    exit 2
fi

echo "==> Building test image: $IMAGE_TAG"
docker build -f "$ROOT_DIR/docker/test.Dockerfile" -t "$IMAGE_TAG" "$ROOT_DIR"

echo "==> Preparing artifacts directory: $ARTIFACTS_DIR"
rm -rf "$ARTIFACTS_DIR"
mkdir -p "$ARTIFACTS_DIR"

TESTS_START_EPOCH="$(date +%s)"
TESTS_START_HUMAN="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "==> Test run start time (UTC): $TESTS_START_HUMAN"

echo "==> Starting dynamic dispatch: $WORKER_COUNT workers over $CHUNK_COUNT chunks"

run_chunk() {
    local group="$1"
    local log_file="$ARTIFACTS_DIR/shard.${group}.log"

    if docker run --rm \
        -e SHARD_GROUP="$group" \
        -e SHARD_COUNT="$CHUNK_COUNT" \
        -e ARTIFACTS_DIR="/artifacts" \
        -e PYTEST_EXTRA_ARGS="$PYTEST_EXTRA_ARGS" \
        -v "$ARTIFACTS_DIR:/artifacts" \
        "$IMAGE_TAG" >"$log_file" 2>&1; then
        : > "$ARTIFACTS_DIR/.status.${group}.ok"
    else
        : > "$ARTIFACTS_DIR/.status.${group}.fail"
        exit 1
    fi
}

export -f run_chunk
export ARTIFACTS_DIR IMAGE_TAG CHUNK_COUNT PYTEST_EXTRA_ARGS

if ! seq 1 "$CHUNK_COUNT" | xargs -P "$WORKER_COUNT" -I {} bash -lc 'run_chunk "$1"' _ {}; then
    echo "One or more chunks failed." >&2
    for group in $(seq 1 "$CHUNK_COUNT"); do
        if [[ -f "$ARTIFACTS_DIR/.status.${group}.fail" ]]; then
            echo "Chunk $group failed. Log: $ARTIFACTS_DIR/shard.${group}.log" >&2
        fi
    done
    exit 1
fi

for group in $(seq 1 "$CHUNK_COUNT"); do
    if [[ -f "$ARTIFACTS_DIR/.status.${group}.ok" ]]; then
        echo "Chunk $group completed successfully"
    fi
done

rm -f "$ARTIFACTS_DIR"/.status.*.ok "$ARTIFACTS_DIR"/.status.*.fail

echo "==> Merging coverage artifacts"
docker run --rm \
    --entrypoint bash \
    -v "$ARTIFACTS_DIR:/artifacts" \
    "$IMAGE_TAG" \
    -lc "set -euo pipefail; \
         python -m coverage combine /artifacts/.coverage.* && \
         python -m coverage xml -o /artifacts/coverage.xml && \
         python -m coverage report -m > /artifacts/coverage.txt"

cp "$ARTIFACTS_DIR/coverage.xml" "$ROOT_DIR/coverage.xml"

TESTS_END_EPOCH="$(date +%s)"
TESTS_END_HUMAN="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
TESTS_ELAPSED_SEC=$(( TESTS_END_EPOCH - TESTS_START_EPOCH ))
echo "==> Test run end time (UTC): $TESTS_END_HUMAN"
echo "==> Test run elapsed: ${TESTS_ELAPSED_SEC}s"

if compgen -G "$ARTIFACTS_DIR/junit.*.xml" > /dev/null; then
    read -r TOTAL_TESTS TOTAL_FAILURES TOTAL_ERRORS < <(
        python - "$ARTIFACTS_DIR" <<'PY'
import glob
import os
import sys
import xml.etree.ElementTree as ET

artifacts_dir = sys.argv[1]
tests = failures = errors = 0

for path in sorted(glob.glob(os.path.join(artifacts_dir, "junit.*.xml"))):
    try:
        root = ET.parse(path).getroot()
    except Exception:
        continue

    if root.tag == "testsuite":
        suites = [root]
    elif root.tag == "testsuites":
        suites = root.findall("testsuite")
    else:
        suites = []

    for suite in suites:
        tests += int(suite.attrib.get("tests", 0) or 0)
        failures += int(suite.attrib.get("failures", 0) or 0)
        errors += int(suite.attrib.get("errors", 0) or 0)

print(f"{tests} {failures} {errors}")
PY
    )
    echo "==> JUnit summary: tests=$TOTAL_TESTS failures=$TOTAL_FAILURES errors=$TOTAL_ERRORS"
fi

echo "==> Completed. Artifacts:"
echo "    shard logs      : $ARTIFACTS_DIR/shard.<N>.log"
echo "    junit reports   : $ARTIFACTS_DIR/junit.<N>.xml"
echo "    coverage report : $ARTIFACTS_DIR/coverage.txt"
echo "    coverage xml    : $ARTIFACTS_DIR/coverage.xml"
