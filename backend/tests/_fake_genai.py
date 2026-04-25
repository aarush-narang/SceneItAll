"""Lightweight test doubles for the google-genai SDK.

Used to drive the agent loop's tool-calling cycle in tests without hitting
Gemini. A scripted list of `FakeResponse`s is returned in order from
`chat.send_message(...)`.
"""

from typing import Any


class FakeFunctionCall:
    def __init__(self, name: str, args: dict[str, Any]):
        self.name = name
        self.args = args


class FakeResponse:
    def __init__(self, function_calls: list[FakeFunctionCall] | None = None, text: str = ""):
        self.function_calls = function_calls or []
        self.text = text


class FakeChat:
    def __init__(self, scripted: list[FakeResponse]):
        self._scripted = list(scripted)
        self._idx = 0

    async def send_message(self, _message: Any) -> FakeResponse:
        if self._idx >= len(self._scripted):
            return FakeResponse(text="")
        resp = self._scripted[self._idx]
        self._idx += 1
        return resp


def fake_client_factory(scripted: list[FakeResponse]):
    """Returns a callable that mimics `google.genai.Client(api_key=...)`."""

    class _Aio:
        @property
        def chats(self):
            return self

        def create(self, **_kwargs):
            return FakeChat(scripted)

    class _Client:
        def __init__(self, *_args, **_kwargs):
            self.aio = _Aio()

    return _Client
