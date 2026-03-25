-module(arizona_test_request).
-moduledoc ~"""
No-op request adapter for test environments. Returns empty defaults
for all request parsing callbacks.
""".
-behaviour(arizona_request).

-export([parse_bindings/1, parse_params/1, parse_cookies/1, parse_headers/1, read_body/1]).

-spec parse_bindings(term()) -> map().
parse_bindings(_RawRequest) -> #{}.

-spec parse_params(term()) -> list().
parse_params(_RawRequest) -> [].

-spec parse_cookies(term()) -> list().
parse_cookies(_RawRequest) -> [].

-spec parse_headers(term()) -> map().
parse_headers(_RawRequest) -> #{}.

-spec read_body(term()) -> {binary(), term()}.
read_body(RawRequest) -> {<<>>, RawRequest}.
