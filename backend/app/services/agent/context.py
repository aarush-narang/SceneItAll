"""Agent execution context shared across every tool call in one turn."""

from typing import Any

from pydantic import BaseModel, ConfigDict, PrivateAttr

from ...db import designs_col, preferences_col


class AgentContext(BaseModel):
    """Per-turn agent state.

    Identity fields (`user_id`, `design_id`, `session_id`) are frozen. The
    design document and preference profile are lazy-loaded once per turn and
    cached on the instance, so a sequence of tools (e.g. `get_room_state` →
    `check_constraints` → `place_item`) only hits Mongo once each.

    Mutation tools call `invalidate_design()` after they $push / $pull / $set
    so that subsequent tools in the same turn see the updated state.
    """

    model_config = ConfigDict(frozen=True)

    user_id: str
    design_id: str
    session_id: str | None = None

    _design: dict[str, Any] | None = PrivateAttr(default=None)
    _prefs: dict[str, Any] | None = PrivateAttr(default=None)
    _prefs_loaded: bool = PrivateAttr(default=False)

    async def load_design(self) -> dict[str, Any]:
        if self._design is None:
            doc = await designs_col().find_one(
                {"_id": self.design_id, "deleted_at": None}
            )
            if not doc:
                raise ValueError(f"Design {self.design_id} not found")
            self._design = doc
        return self._design

    async def load_preferences(self) -> dict[str, Any] | None:
        if not self._prefs_loaded:
            self._prefs = await preferences_col().find_one({"user_id": self.user_id})
            self._prefs_loaded = True
        return self._prefs

    def invalidate_design(self) -> None:
        self._design = None
