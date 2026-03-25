-module(arizona_stream).
-moduledoc ~"""
Streams for efficient rendering of large collections.

Streams track a set of DOM element IDs and pending insert/delete operations.
The server only stores keys, not the full collection data. When the client
receives stream operations, it manipulates the DOM directly without morphdom.

## Example

```erlang
mount(_Arg, _Req) ->
    Items = [{<<"item-1">>, #{title => <<"First">>}},
             {<<"item-2">>, #{title => <<"Second">>}}],
    View = arizona_view:new(?MODULE, #{items => []}, none),
    arizona_stream:stream(items, Items, View).
```

After mount, the view bindings contain a `{stream, items, ...}` value
that the renderer can use to generate initial HTML. Subsequent
`stream_insert/3-4` and `stream_delete/3` calls produce pending
operations sent as separate wire messages.
""".

-export([
    stream/3,
    stream_insert/3,
    stream_insert/4,
    stream_delete/3,
    stream_reset/3,
    get_stream/2,
    get_pending_ops/2,
    clear_pending_ops/2
]).

-ignore_xref([
    stream/3,
    stream_insert/3,
    stream_insert/4,
    stream_delete/3,
    stream_reset/3,
    get_stream/2,
    get_pending_ops/2,
    clear_pending_ops/2
]).

-export_type([stream_item/0, stream_op/0]).

-nominal stream_item() :: {DomId :: binary(), Data :: map()}.
-nominal stream_op() ::
    {insert, DomId :: binary(), Data :: map(), Opts :: map()}
    | {delete, DomId :: binary()}.

-doc "Initialize a stream with a list of items.".
-spec stream(atom(), [stream_item()], arizona_view:view()) -> arizona_view:view().
stream(Name, Items, View) ->
    Keys = [DomId || {DomId, _Data} <- Items],
    InsertOps = [{insert, DomId, Data, #{at => -1}} || {DomId, Data} <- Items],
    State = arizona_view:get_state(View),
    StreamData = #{
        keys => Keys,
        pending_ops => InsertOps
    },
    State1 = arizona_stateful:put_binding({stream, Name}, StreamData, State),
    State2 = arizona_stateful:put_binding(Name, Items, State1),
    arizona_view:update_state(State2, View).

-doc "Insert an item into a stream at the default position (end).".
-spec stream_insert(atom(), stream_item(), arizona_view:view()) -> arizona_view:view().
stream_insert(Name, Item, View) ->
    stream_insert(Name, Item, #{at => -1}, View).

-doc "Insert an item at a specific position. `#{at => 0}` for beginning, `#{at => -1}` for end.".
-spec stream_insert(atom(), stream_item(), map(), arizona_view:view()) -> arizona_view:view().
stream_insert(Name, {DomId, Data}, Opts, View) ->
    State = arizona_view:get_state(View),
    StreamData = arizona_stateful:get_binding({stream, Name}, State),
    #{keys := Keys, pending_ops := Ops} = StreamData,
    NewKeys =
        case maps:get(at, Opts, -1) of
            0 -> [DomId | Keys];
            _ -> Keys ++ [DomId]
        end,
    NewOps = Ops ++ [{insert, DomId, Data, Opts}],
    State1 = arizona_stateful:put_binding(
        {stream, Name}, StreamData#{keys := NewKeys, pending_ops := NewOps}, State
    ),
    arizona_view:update_state(State1, View).

-doc "Delete an item from a stream by DOM ID.".
-spec stream_delete(atom(), binary(), arizona_view:view()) -> arizona_view:view().
stream_delete(Name, DomId, View) ->
    State = arizona_view:get_state(View),
    StreamData = arizona_stateful:get_binding({stream, Name}, State),
    #{keys := Keys, pending_ops := Ops} = StreamData,
    NewKeys = lists:delete(DomId, Keys),
    NewOps = Ops ++ [{delete, DomId}],
    State1 = arizona_stateful:put_binding(
        {stream, Name}, StreamData#{keys := NewKeys, pending_ops := NewOps}, State
    ),
    arizona_view:update_state(State1, View).

-doc "Reset a stream with a new list of items.".
-spec stream_reset(atom(), [stream_item()], arizona_view:view()) -> arizona_view:view().
stream_reset(Name, Items, View) ->
    State = arizona_view:get_state(View),
    StreamData = arizona_stateful:get_binding({stream, Name}, State),
    #{keys := OldKeys} = StreamData,
    NewKeys = [DomId || {DomId, _} <- Items],
    DeleteOps = [{delete, K} || K <- OldKeys],
    InsertOps = [{insert, DomId, Data, #{at => -1}} || {DomId, Data} <- Items],
    State1 = arizona_stateful:put_binding(
        {stream, Name},
        #{keys => NewKeys, pending_ops => DeleteOps ++ InsertOps},
        State
    ),
    State2 = arizona_stateful:put_binding(Name, Items, State1),
    arizona_view:update_state(State2, View).

-doc "Get the current stream data for a name.".
-spec get_stream(atom(), arizona_view:view()) -> map() | undefined.
get_stream(Name, View) ->
    State = arizona_view:get_state(View),
    arizona_stateful:get_binding({stream, Name}, State).

-doc "Get pending operations for a stream.".
-spec get_pending_ops(atom(), arizona_view:view()) -> [stream_op()].
get_pending_ops(Name, View) ->
    case get_stream(Name, View) of
        #{pending_ops := Ops} -> Ops;
        _ -> []
    end.

-doc "Clear pending operations for a stream (called after sending to client).".
-spec clear_pending_ops(atom(), arizona_view:view()) -> arizona_view:view().
clear_pending_ops(Name, View) ->
    State = arizona_view:get_state(View),
    case arizona_stateful:get_binding({stream, Name}, State) of
        #{} = StreamData ->
            State1 = arizona_stateful:put_binding(
                {stream, Name}, StreamData#{pending_ops := []}, State
            ),
            arizona_view:update_state(State1, View);
        _ ->
            View
    end.
