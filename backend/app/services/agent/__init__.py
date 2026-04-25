"""Pydantic-first interior-design agent. The package's __init__ imports the
tools subpackage so registrations happen at import time."""

from . import tools  # noqa: F401  — side-effect: registers every tool
from .loop import run_agent_chat

__all__ = ["run_agent_chat"]
