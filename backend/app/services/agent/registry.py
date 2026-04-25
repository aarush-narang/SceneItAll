"""Pydantic-first agent tool registry.

Each tool registers a typed input + output model and a handler. The registry
auto-derives google-genai `FunctionDeclaration`s from pydantic JSON schemas,
and the dispatcher validates raw Gemini arguments against the input model
before executing — invalid args come back to the model as a structured error
so it can self-correct rather than crashing the loop.
"""

from dataclasses import dataclass
from typing import Any, Awaitable, Callable

from google.genai import types
from pydantic import BaseModel, ValidationError

from .context import AgentContext


ToolHandler = Callable[[AgentContext, BaseModel], Awaitable[BaseModel]]


@dataclass(frozen=True)
class ToolEntry:
    name: str
    description: str
    input_model: type[BaseModel]
    output_model: type[BaseModel]
    handler: ToolHandler
    mutates: bool
    tier: int


_REGISTRY: dict[str, ToolEntry] = {}


def register(
    *,
    name: str,
    description: str,
    input: type[BaseModel],
    output: type[BaseModel],
    mutates: bool = False,
    tier: int = 1,
):
    """Decorator that registers a tool handler. Usage:

        @register(name="search_catalog", description="...",
                  input=SearchCatalogInput, output=SearchCatalogOutput)
        async def search_catalog(ctx, inp): ...
    """

    def decorator(handler: ToolHandler) -> ToolHandler:
        if name in _REGISTRY:
            raise ValueError(f"Tool {name!r} already registered")
        _REGISTRY[name] = ToolEntry(
            name=name,
            description=description,
            input_model=input,
            output_model=output,
            handler=handler,
            mutates=mutates,
            tier=tier,
        )
        return handler

    return decorator


def get_tool(name: str) -> ToolEntry | None:
    return _REGISTRY.get(name)


def all_tools() -> list[ToolEntry]:
    return list(_REGISTRY.values())


def function_declarations(*, mutating_only: bool | None = None) -> list[types.FunctionDeclaration]:
    """Build a `FunctionDeclaration` per registered tool.

    `mutating_only=True` returns only mutation tools, `False` returns only
    read-only tools, `None` (default) returns everything.
    """
    entries = _REGISTRY.values()
    if mutating_only is True:
        entries = [e for e in entries if e.mutates]
    elif mutating_only is False:
        entries = [e for e in entries if not e.mutates]
    return [_to_declaration(e) for e in entries]


async def dispatch(name: str, raw_args: dict[str, Any], ctx: AgentContext) -> dict[str, Any]:
    """Validate, run, and serialise one tool call.

    Returns a JSON-safe dict. Validation errors come back as
    `{"error": ..., "validation": [...]}` so Gemini can fix and retry.
    Runtime errors come back as `{"error": ...}` with the exception message.
    """
    entry = _REGISTRY.get(name)
    if entry is None:
        return {"error": f"Unknown tool {name!r}"}

    try:
        inp = entry.input_model.model_validate(raw_args)
    except ValidationError as exc:
        return {
            "error": f"Invalid arguments for {name}",
            "validation": [
                {"loc": ".".join(str(p) for p in err["loc"]), "msg": err["msg"]}
                for err in exc.errors()
            ],
        }

    try:
        out = await entry.handler(ctx, inp)
    except Exception as exc:
        return {"error": f"{name} failed: {exc}"}

    if not isinstance(out, entry.output_model):
        return {"error": f"{name} returned wrong type: {type(out).__name__}"}
    return out.model_dump(mode="json")


# --- pydantic JSON schema → google-genai Schema ----------------------------------


def _to_declaration(entry: ToolEntry) -> types.FunctionDeclaration:
    schema = entry.input_model.model_json_schema()
    defs = schema.get("$defs", {})
    return types.FunctionDeclaration(
        name=entry.name,
        description=entry.description,
        parameters=_convert(schema, defs),
    )


_PRIMITIVE_TYPES = {
    "string": types.Type.STRING,
    "number": types.Type.NUMBER,
    "integer": types.Type.INTEGER,
    "boolean": types.Type.BOOLEAN,
}


def _resolve_ref(node: dict, defs: dict) -> dict:
    seen: set[str] = set()
    while "$ref" in node:
        ref = node["$ref"]
        if ref in seen:
            return {}
        seen.add(ref)
        name = ref.rsplit("/", 1)[-1]
        node = defs.get(name, {})
    return node


def _convert(node: dict, defs: dict) -> types.Schema:
    """Recursively convert a JSON schema node into a google-genai Schema."""
    node = _resolve_ref(node, defs)

    # `Optional[X]` from pydantic v2 → anyOf: [X, {"type": "null"}]
    if "anyOf" in node:
        variants = node["anyOf"]
        non_null = [v for v in variants if v.get("type") != "null"]
        nullable = len(non_null) < len(variants)
        if non_null:
            inner = _convert(non_null[0], defs)
            inner.nullable = True if nullable else inner.nullable
            if not inner.description and node.get("description"):
                inner.description = node["description"]
            return inner

    description = node.get("description")
    type_str = node.get("type")

    if type_str == "object" or (type_str is None and "properties" in node):
        properties = {
            k: _convert(v, defs) for k, v in (node.get("properties") or {}).items()
        }
        return types.Schema(
            type=types.Type.OBJECT,
            properties=properties or None,
            required=list(node.get("required", [])) or None,
            description=description,
        )

    if type_str == "array":
        if "items" in node:
            item_schema = _convert(node["items"], defs)
        elif "prefixItems" in node:
            # tuple[float, float, float] (Vec3/Vec2) → prefixItems; all same type
            item_schema = _convert(node["prefixItems"][0], defs)
        else:
            item_schema = types.Schema(type=types.Type.NUMBER)
        return types.Schema(
            type=types.Type.ARRAY,
            items=item_schema,
            description=description,
        )

    enum_vals = node.get("enum")
    if enum_vals is not None:
        return types.Schema(
            type=types.Type.STRING,
            enum=[str(v) for v in enum_vals],
            description=description,
        )

    return types.Schema(
        type=_PRIMITIVE_TYPES.get(type_str or "string", types.Type.STRING),
        description=description,
    )
