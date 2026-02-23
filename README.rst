========================
Bluesky Queue Server API
========================

.. image:: https://img.shields.io/pypi/v/bluesky-queueserver-api.svg
        :target: https://pypi.python.org/pypi/bluesky-queueserver-api

.. image:: https://img.shields.io/conda/vn/conda-forge/bluesky-queueserver-api
        :target: https://anaconda.org/conda-forge/bluesky-queueserver-api

.. image:: https://img.shields.io/codecov/c/github/bluesky/bluesky-queueserver-api
        :target: https://codecov.io/gh/bluesky/bluesky-queueserver-api

.. image:: https://img.shields.io/github/commits-since/bluesky/bluesky-queueserver-api/latest
        :target: https://github.com/bluesky/bluesky-queueserver-api

.. image:: https://img.shields.io/pypi/dm/bluesky-queueserver-api?label=PyPI%20downloads
        :target: https://pypi.python.org/pypi/bluesky-queueserver-api

.. image:: https://img.shields.io/conda/dn/conda-forge/bluesky-queueserver-api?label=Conda-Forge%20downloads
        :target: https://anaconda.org/conda-forge/bluesky-queueserver-api


Python API for Bluesky Queue Server

The project is currently containing a prototype of the API, which can change at any moment.

* Free software: 3-clause BSD license
* Documentation: https://bluesky.github.io/bluesky-queueserver-api.


Build and link from source
==========================

Build distribution artifacts
----------------------------

From a local checkout, build source and wheel distributions:

.. code-block:: bash

        cd bluesky-queueserver-api
        uv build

The resulting files are created in ``dist/``.

You can also build with ``pip`` tooling:

.. code-block:: bash

        cd bluesky-queueserver-api
        python -m pip install --upgrade build
        python -m build


Install or link a local checkout
--------------------------------

Install this package in editable mode from the repository root:

.. code-block:: bash

        cd bluesky-queueserver-api
        python -m pip install -e .

From another project, link to this repository as a local editable dependency
using ``uv``:

.. code-block:: bash

        uv add --editable ../bluesky-queueserver-api

Note: the directory name uses hyphens (``bluesky-queueserver-api``), not
underscores.


Run tests in parallel with Docker
=================================

Use isolated containers to run test shards in parallel and avoid local port/process
interference.

.. code-block:: bash

        cd bluesky-queueserver-api
        chmod +x scripts/run_ci_docker_parallel.sh scripts/docker/run_shard_in_container.sh
        ./scripts/run_ci_docker_parallel.sh

By default, the script runs with dynamic dispatch using ``3`` workers and
``9`` chunks (``CHUNK_COUNT=WORKER_COUNT*3``). As workers finish, the next
chunk is started automatically to keep utilization high.

You can tune workers/chunks and pass extra pytest arguments:

.. code-block:: bash

        WORKER_COUNT=4 CHUNK_COUNT=16 PYTEST_EXTRA_ARGS="-k api --maxfail=1" ./scripts/run_ci_docker_parallel.sh

Backward compatibility: ``SHARD_COUNT`` still works as an alias for
``WORKER_COUNT``.

When filtering to a small subset (for example with ``-k``), some chunks may
have no selected tests. Those chunks are treated as successful by default.

Artifacts are written to ``.docker-test-artifacts/``:

* ``shard.<N>.log``: per-shard container output
* ``junit.<N>.xml``: per-shard JUnit reports
* ``coverage.txt`` and ``coverage.xml``: merged coverage outputs

The script also copies merged ``coverage.xml`` to the repository root.


Local CI helper (no unit tests)
===============================

The helper script ``scripts/run_ci_local.sh`` runs local CI-style checks
(dependency install, style checks, docs build, package build), but
intentionally skips unit-test execution.

Run unit tests with ``scripts/run_ci_docker_parallel.sh`` instead.

Example:

.. code-block:: bash

        cd bluesky-queueserver-api
        WORKER_COUNT=10 CHUNK_COUNT=30 ./scripts/run_ci_docker_parallel.sh
