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
