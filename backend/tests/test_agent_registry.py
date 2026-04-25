"""Unit tests for the pydantic-first tool registry."""

import pytest
from google.genai import types

import app.services.agent  # noqa: F401  — registers all tools
from app.services.agent.context import AgentContext
from app.services.agent.registry import all_tools, dispatch, function_declarations


_EXPECTED_MUTATING = {"place_item", "remove_item", "move_item", "swap_style", "balance_budget"}
_EXPECTED_READONLY = {
    "search_catalog",
    "get_room_state",
    "get_preferences",
    "check_constraints",
    "find_empty_zones",
    "furnish_room",
}


def test_all_expected_tools_registered():
    names = {t.name for t in all_tools()}
    assert names == _EXPECTED_MUTATING | _EXPECTED_READONLY


def test_mutation_flags_match_expectations():
    for tool in all_tools():
        if tool.name in _EXPECTED_MUTATING:
            assert tool.mutates is True, f"{tool.name} should be marked mutating"
        else:
            assert tool.mutates is False, f"{tool.name} should be marked read-only"


def test_function_declarations_round_trip():
    """Every registered tool's pydantic Input converts to a valid FunctionDeclaration."""
    declarations = function_declarations()
    assert len(declarations) == len(_EXPECTED_MUTATING | _EXPECTED_READONLY)

    for fd in declarations:
        assert fd.name
        assert fd.description
        assert fd.parameters is not None
        assert fd.parameters.type == types.Type.OBJECT


def test_function_declarations_filters_by_mutation():
    mutating = {fd.name for fd in function_declarations(mutating_only=True)}
    readonly = {fd.name for fd in function_declarations(mutating_only=False)}
    assert mutating == _EXPECTED_MUTATING
    assert readonly == _EXPECTED_READONLY


@pytest.mark.anyio
async def test_dispatch_unknown_tool_returns_structured_error():
    ctx = AgentContext(user_id="u", design_id="d")
    result = await dispatch("not_a_real_tool", {}, ctx)
    assert "error" in result
    assert "Unknown tool" in result["error"]


@pytest.mark.anyio
async def test_dispatch_invalid_args_returns_validation_error():
    """Bad args come back as a structured error so Gemini can self-correct."""
    ctx = AgentContext(user_id="u", design_id="d")
    # place_item requires catalog_id, position, rationale; pass nothing
    result = await dispatch("place_item", {}, ctx)
    assert "error" in result
    assert "validation" in result
    assert isinstance(result["validation"], list)
    assert len(result["validation"]) > 0


@pytest.mark.anyio
async def test_dispatch_extra_args_are_ignored():
    """pydantic v2 default allows extra fields; the validator accepts but drops them."""
    ctx = AgentContext(user_id="u", design_id="d")
    result = await dispatch(
        "find_empty_zones",
        {"limit": 1, "garbage": "ignored"},
        ctx,
    )
    # Either the tool succeeds (it would, if a design existed), OR fails with the
    # design lookup — not with a "garbage" validation error.
    if "error" in result:
        assert "garbage" not in str(result["error"])
