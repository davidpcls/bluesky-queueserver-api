"""
Communication tests - this file imports tests from separate modules for backwards compatibility.

Tests have been split into:
- test_comm_base.py: Tests for ReManagerAPI_Base class
- test_comm_threads.py: Tests for synchronous (threads) communication classes
- test_comm_async.py: Tests for asynchronous communication classes
- test_comm_oidc.py: Tests for OIDC authentication functionality

You can run individual test files or this file to run all communication tests.
"""

# Import all tests from separate modules for backwards compatibility
from .test_comm_base import *  # noqa: F401, F403
from .test_comm_threads import *  # noqa: F401, F403
from .test_comm_async import *  # noqa: F401, F403
from .test_comm_oidc import *  # noqa: F401, F403

