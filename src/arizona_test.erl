-module(arizona_test).
-moduledoc ~"""
Test helpers for Arizona views and components.

Provides a high-level API for testing views without a real WebSocket
connection. Starts an `arizona_live` process with the test process as
transport and captures `actions_response` messages for assertions.

## Quick Start

```erlang
-include_lib("arizona_core/include/arizona_test.hrl").

my_test(Config) ->
    {ok, Ctx} = arizona_test:mount(my_view),
    HTML = arizona_test:render(Ctx),
    ?assertArizonaMatch(<<"Welcome">>, HTML),
    {ok, Ctx1} = arizona_test:render_click(Ctx, ~"increment"),
    HTML1 = arizona_test:render(Ctx1),
    ?assertArizonaMatch(<<"1">>, HTML1).
```

## Test Context

The `ctx()` record holds the live process PID, last rendered view,
hierarchical structure, diff, and actions. Use `render/1` to get
the current HTML and `render_click/2-4`, `render_submit/3`, or
`render_change/3` to simulate events.
""".

-export([
    mount/1,
    mount/2,
    render/1,
    render_click/2,
    render_click/4,
    render_submit/3,
    render_change/3,
    broadcast/3,
    send_info/2,
    has_element/2,
    stop/1
]).

-ignore_xref([
    mount/1,
    mount/2,
    render/1,
    render_click/2,
    render_click/4,
    render_submit/3,
    render_change/3,
    broadcast/3,
    send_info/2,
    has_element/2,
    stop/1
]).

-include("../include/arizona_test.hrl").

-doc "Mount a view module with no mount argument.".
-spec mount(module()) -> {ok, ctx()}.
mount(Module) ->
    mount(Module, #{}).

-doc "Mount a view module with a mount argument.".
-spec mount(module(), arizona_view:mount_arg()) -> {ok, ctx()}.
mount(Module, MountArg) ->
    ensure_pg_groups(),
    Request = arizona_request:new(arizona_test_request, #{}, #{}),
    {ok, Pid} = arizona_live:start_link(Module, MountArg, Request, self()),
    {HierarchicalStructure, Diff} = arizona_live:initial_render(Pid),
    View = arizona_live:get_view(Pid),
    {ok, #ctx{
        pid = Pid,
        view = View,
        hierarchical = HierarchicalStructure,
        diff = Diff,
        actions = []
    }}.

-doc "Render the current view state to an HTML binary.".
-spec render(ctx()) -> binary().
render(#ctx{diff = Diff}) ->
    iolist_to_binary(format_diff(Diff)).

-doc "Simulate a click event on the view (no stateful ID).".
-spec render_click(ctx(), binary()) -> {ok, ctx()}.
render_click(Ctx, Event) ->
    render_click(Ctx, undefined, Event, #{}).

-doc "Simulate a click event with stateful ID and params.".
-spec render_click(ctx(), binary() | undefined, binary(), map()) -> {ok, ctx()}.
render_click(#ctx{pid = Pid} = Ctx, StatefulId, Event, Params) ->
    ok = arizona_live:handle_event(Pid, StatefulId, Event, Params),
    await_response(Ctx).

-doc "Simulate a form submit event.".
-spec render_submit(ctx(), binary(), map()) -> {ok, ctx()}.
render_submit(#ctx{pid = Pid} = Ctx, Event, FormData) ->
    ok = arizona_live:handle_event(Pid, undefined, Event, FormData),
    await_response(Ctx).

-doc "Simulate a form change event.".
-spec render_change(ctx(), binary(), map()) -> {ok, ctx()}.
render_change(#ctx{pid = Pid} = Ctx, Event, Params) ->
    ok = arizona_live:handle_event(Pid, undefined, Event, Params),
    await_response(Ctx).

-doc "Broadcast a PubSub message to the live process.".
-spec broadcast(ctx(), binary(), term()) -> {ok, ctx()}.
broadcast(#ctx{pid = Pid} = Ctx, Topic, Data) ->
    Pid ! {pubsub_message, Topic, Data},
    await_response(Ctx).

-doc "Send a raw Erlang message to the live process.".
-spec send_info(ctx(), term()) -> {ok, ctx()}.
send_info(#ctx{pid = Pid} = Ctx, Message) ->
    Pid ! Message,
    await_response(Ctx).

-doc "Check if a pattern exists in the current rendered HTML.".
-spec has_element(ctx(), binary()) -> boolean().
has_element(Ctx, Pattern) ->
    HTML = render(Ctx),
    nomatch =/= binary:match(HTML, Pattern).

-doc "Stop the live process.".
-spec stop(ctx()) -> ok.
stop(#ctx{pid = Pid}) ->
    gen_server:stop(Pid),
    ok.

%%----------------------------------------------------------------------
%% Internal
%%----------------------------------------------------------------------

await_response(#ctx{pid = Pid} = Ctx) ->
    receive
        {actions_response, _StatefulId, Diff, Hierarchical, Actions} ->
            View = arizona_live:get_view(Pid),
            {ok, Ctx#ctx{
                view = View,
                diff = Diff,
                hierarchical = Hierarchical,
                actions = Actions
            }}
    after 5000 ->
        error(timeout_waiting_for_actions_response)
    end.

ensure_pg_groups() ->
    ensure_pg(arizona_live),
    ensure_pg(arizona_pubsub).

ensure_pg(Scope) ->
    case pg:start(Scope) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end.

format_diff(Diff) when is_map(Diff) ->
    maps:fold(
        fun(_K, V, Acc) ->
            [Acc, format_diff(V)]
        end,
        [],
        Diff
    );
format_diff(Diff) when is_binary(Diff) ->
    Diff;
format_diff(Diff) when is_list(Diff) ->
    [format_diff(E) || E <- Diff];
format_diff(_) ->
    <<>>.
