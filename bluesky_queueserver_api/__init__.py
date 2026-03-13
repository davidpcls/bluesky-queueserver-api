from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("bluesky-queueserver-api")
except PackageNotFoundError:
    __version__ = "0+unknown"

from .api_base import WaitMonitor  # noqa: F401, E402
from .item import BFunc, BInst, BItem, BPlan  # noqa: F401, E402
