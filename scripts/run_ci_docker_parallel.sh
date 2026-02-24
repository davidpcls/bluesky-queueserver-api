#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG_BASE="bluesky-queueserver-api-test:local"
WORKER_COUNT="3"
CHUNK_COUNT=""
PYTHON_VERSIONS="latest"
PYTEST_EXTRA_ARGS=""
ARTIFACTS_DIR="$ROOT_DIR/.docker-test-artifacts"

SUPPORTED_PYTHON_VERSIONS=("3.10" "3.11" "3.12" "3.13")

usage() {
    cat <<'EOF'
Run unit tests in Docker with dynamic chunk dispatch and optional Python-version matrix.

Usage:
  scripts/run_ci_docker_parallel.sh [options]

Options:
  --workers N, --worker-count N
      Number of concurrent chunk workers (default: 3).

  --chunks N, --chunk-count N
      Number of total chunks/splits to execute per Python version.
      Default: workers * 3.

  --python-versions VALUE
      Python version selection: latest | all | comma-separated list.
      Examples: latest, all, 3.12, 3.11,3.13
      Default: latest (currently 3.13).

  --pytest-args "ARGS"
      Extra arguments passed to pytest in each chunk.
      Example: --pytest-args "-k api --maxfail=1"

  --artifacts-dir PATH
      Output directory for all artifacts.
      Default: .docker-test-artifacts under repository root.

  --image-tag TAG
      Base docker image tag. Per-version tags will append -py<VERSION>.
      Default: bluesky-queueserver-api-test:local

  -h, --help
      Show this help message.

Examples:
  scripts/run_ci_docker_parallel.sh
  scripts/run_ci_docker_parallel.sh --workers 8 --chunks 24
  scripts/run_ci_docker_parallel.sh --python-versions all --workers 8 --chunks 24
  scripts/run_ci_docker_parallel.sh --python-versions 3.11,3.13 --pytest-args "-k test_api"
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workers|--worker-count)
            WORKER_COUNT="$2"
            shift 2
            ;;
        --chunks|--chunk-count)
            CHUNK_COUNT="$2"
            shift 2
            ;;
        --python-versions)
            PYTHON_VERSIONS="$2"
            shift 2
            ;;
        --pytest-args)
            PYTEST_EXTRA_ARGS="$2"
            shift 2
            ;;
        --artifacts-dir)
            ARTIFACTS_DIR="$2"
            shift 2
            ;;
        --image-tag)
            IMAGE_TAG_BASE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

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

normalize_python_versions() {
    local selection="$1"
    local raw
    local normalized=()

    if [[ "$selection" == "latest" ]]; then
        normalized=("3.13")
    elif [[ "$selection" == "all" ]]; then
        normalized=("${SUPPORTED_PYTHON_VERSIONS[@]}")
    else
        raw="${selection//,/ }"
        read -r -a normalized <<< "$raw"
    fi

    if [[ "${#normalized[@]}" -eq 0 ]]; then
        echo "PYTHON_VERSIONS selection produced no versions" >&2
        exit 2
    fi

    for version in "${normalized[@]}"; do
        if [[ ! " ${SUPPORTED_PYTHON_VERSIONS[*]} " =~ " ${version} " ]]; then
            echo "Unsupported Python version '${version}'. Supported: ${SUPPORTED_PYTHON_VERSIONS[*]}" >&2
            exit 2
        fi
    done

    echo "${normalized[@]}"
}

read -r -a SELECTED_PYTHON_VERSIONS <<< "$(normalize_python_versions "$PYTHON_VERSIONS")"

echo "==> Preparing artifacts directory: $ARTIFACTS_DIR"
rm -rf "$ARTIFACTS_DIR"
mkdir -p "$ARTIFACTS_DIR"

TESTS_START_EPOCH="$(date +%s)"
TESTS_START_HUMAN="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "==> Test run start time (UTC): $TESTS_START_HUMAN"
echo "==> Python versions selected: ${SELECTED_PYTHON_VERSIONS[*]}"

run_chunk() {
    local group="$1"
    local log_file="$CURRENT_ARTIFACTS_DIR/shard.${group}.log"

    if docker run --rm \
        -e SHARD_GROUP="$group" \
        -e SHARD_COUNT="$CHUNK_COUNT" \
        -e ARTIFACTS_DIR="/artifacts" \
        -e PYTEST_EXTRA_ARGS="$PYTEST_EXTRA_ARGS" \
        -v "$CURRENT_ARTIFACTS_DIR:/artifacts" \
        "$CURRENT_IMAGE_TAG" >"$log_file" 2>&1; then
        : > "$CURRENT_ARTIFACTS_DIR/.status.${group}.ok"
    else
        : > "$CURRENT_ARTIFACTS_DIR/.status.${group}.fail"
        exit 1
    fi
}

export -f run_chunk
export CHUNK_COUNT PYTEST_EXTRA_ARGS

for PYTHON_VERSION in "${SELECTED_PYTHON_VERSIONS[@]}"; do
    CURRENT_IMAGE_TAG="${IMAGE_TAG_BASE}-py${PYTHON_VERSION}"
    CURRENT_ARTIFACTS_DIR="$ARTIFACTS_DIR/py${PYTHON_VERSION}"
    export CURRENT_IMAGE_TAG CURRENT_ARTIFACTS_DIR

    echo "==> Building test image: $CURRENT_IMAGE_TAG (Python $PYTHON_VERSION)"
    docker build \
        --build-arg PYTHON_VERSION="$PYTHON_VERSION" \
        -f "$ROOT_DIR/docker/test.Dockerfile" \
        -t "$CURRENT_IMAGE_TAG" \
        "$ROOT_DIR"

    mkdir -p "$CURRENT_ARTIFACTS_DIR"

    echo "==> [Python $PYTHON_VERSION] Starting dynamic dispatch: $WORKER_COUNT workers over $CHUNK_COUNT chunks"
    if ! seq 1 "$CHUNK_COUNT" | xargs -P "$WORKER_COUNT" -I {} bash -lc 'run_chunk "$1"' _ {}; then
        echo "One or more chunks failed for Python $PYTHON_VERSION." >&2
        for group in $(seq 1 "$CHUNK_COUNT"); do
            if [[ -f "$CURRENT_ARTIFACTS_DIR/.status.${group}.fail" ]]; then
                echo "Chunk $group failed. Log: $CURRENT_ARTIFACTS_DIR/shard.${group}.log" >&2
            fi
        done
        exit 1
    fi

    for group in $(seq 1 "$CHUNK_COUNT"); do
        if [[ -f "$CURRENT_ARTIFACTS_DIR/.status.${group}.ok" ]]; then
            echo "[Python $PYTHON_VERSION] Chunk $group completed successfully"
        fi
    done

    rm -f "$CURRENT_ARTIFACTS_DIR"/.status.*.ok "$CURRENT_ARTIFACTS_DIR"/.status.*.fail

    echo "==> [Python $PYTHON_VERSION] Merging coverage artifacts"
    docker run --rm \
        --entrypoint bash \
        -v "$CURRENT_ARTIFACTS_DIR:/artifacts" \
        "$CURRENT_IMAGE_TAG" \
        -lc "set -euo pipefail; \
             python -m coverage combine /artifacts/.coverage.* && \
             python -m coverage xml -o /artifacts/coverage.xml && \
             python -m coverage report -m > /artifacts/coverage.txt"

    if [[ "${#SELECTED_PYTHON_VERSIONS[@]}" -eq 1 ]]; then
        cp "$CURRENT_ARTIFACTS_DIR/coverage.xml" "$ROOT_DIR/coverage.xml"
    else
        cp "$CURRENT_ARTIFACTS_DIR/coverage.xml" "$ROOT_DIR/coverage.py${PYTHON_VERSION}.xml"
    fi

    if compgen -G "$CURRENT_ARTIFACTS_DIR/junit.*.xml" > /dev/null; then
        read -r TOTAL_TESTS TOTAL_FAILURES TOTAL_ERRORS < <(
            python - "$CURRENT_ARTIFACTS_DIR" <<'PY'
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
        echo "==> [Python $PYTHON_VERSION] JUnit summary: tests=$TOTAL_TESTS failures=$TOTAL_FAILURES errors=$TOTAL_ERRORS"
    fi
done

TESTS_END_EPOCH="$(date +%s)"
TESTS_END_HUMAN="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
TESTS_ELAPSED_SEC=$(( TESTS_END_EPOCH - TESTS_START_EPOCH ))
echo "==> Test run end time (UTC): $TESTS_END_HUMAN"
echo "==> Test run elapsed: ${TESTS_ELAPSED_SEC}s"

echo "==> Completed. Artifacts:"
echo "    versioned logs      : $ARTIFACTS_DIR/py<VERSION>/shard.<N>.log"
echo "    versioned junit     : $ARTIFACTS_DIR/py<VERSION>/junit.<N>.xml"
echo "    versioned coverage  : $ARTIFACTS_DIR/py<VERSION>/{coverage.txt,coverage.xml}"

if [[ "${#SELECTED_PYTHON_VERSIONS[@]}" -eq 1 ]]; then
    echo "    root coverage xml   : $ROOT_DIR/coverage.xml"
else
    echo "    root coverage xmls  : $ROOT_DIR/coverage.py<VERSION>.xml"
fi
