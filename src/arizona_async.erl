-module(arizona_async).
-moduledoc ~"""
Async assigns for non-blocking data loading in views.

Spawns a monitored process to compute a value asynchronously. The binding
is set to `{async, loading}` immediately and updated to `{async, {ok, Value}}`
or `{async, {failed, Reason}}` when the spawned process completes.

The live process catches `'DOWN'` messages from the spawned process and
updates the binding, triggering a re-render.

## Example

```erlang
mount(_Arg, _Req) ->
    View = arizona_view:new(?MODULE, #{data => {async, loading}}, none),
    arizona_async:assign_async(data, fun() -> slow_db_call() end, View).

render(Bindings) ->
    arizona_async:render(data, Bindings, fun
        (loading) ->
            arizona_template:from_html(~\"\"\"<p>Loading...</p>\"\"\");
        ({ok, Value}) ->
            arizona_template:from_html(~\"\"\"<p>{Value}</p>\"\"\");
        ({failed, _Reason}) ->
            arizona_template:from_html(~\"\"\"<p>Error loading data</p>\"\"\")
    end).
```
""".

-export([
    assign_async/3,
    assign_async/4,
    render/3,
    cancel_async/2
]).

-ignore_xref([assign_async/3, assign_async/4, render/3, cancel_async/2]).

-export_type([async_status/0]).

-nominal async_status() :: loading | {ok, term()} | {failed, term()}.

-doc "Spawn an async task for a binding key with default options.".
-spec assign_async(atom(), fun(() -> term()), arizona_view:view()) -> arizona_view:view().
assign_async(Key, Fun, View) ->
    assign_async(Key, Fun, #{}, View).

-doc "Spawn an async task for a binding key with options.".
-spec assign_async(atom(), fun(() -> term()), map(), arizona_view:view()) -> arizona_view:view().
assign_async(Key, Fun, _Opts, View) ->
    State = arizona_view:get_state(View),
    State1 = arizona_stateful:put_binding(Key, {async, loading}, State),
    {_Pid, _Ref} = spawn_monitor(fun() ->
        exit({async_result, Key, Fun()})
    end),
    arizona_view:update_state(State1, View).

-doc "Render helper that dispatches on async status.".
-spec render(atom(), map(), fun((async_status()) -> term())) -> term().
render(Key, Bindings, RenderFun) ->
    case maps:get(Key, Bindings, {async, loading}) of
        {async, Status} -> RenderFun(Status);
        Value -> RenderFun({ok, Value})
    end.

-doc "Cancel a pending async task by killing its monitor.".
-spec cancel_async(atom(), arizona_view:view()) -> arizona_view:view().
cancel_async(Key, View) ->
    State = arizona_view:get_state(View),
    State1 = arizona_stateful:put_binding(Key, {async, {failed, cancelled}}, State),
    arizona_view:update_state(State1, View).
