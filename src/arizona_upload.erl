-module(arizona_upload).
-moduledoc ~"""
File upload support for Arizona views.

Manages file upload lifecycle: configuration, validation, progress tracking,
and consumption. Upload entries go through phases:

1. **Configure**: `allow/3` sets accepted types, limits
2. **Validate**: Client sends metadata, server validates against config
3. **Transfer**: Client sends binary chunks, server tracks progress
4. **Consume**: View calls `consume/2` to get completed uploads

## Example

```erlang
mount(_Arg, _Req) ->
    View = arizona_view:new(?MODULE, #{}, none),
    arizona_upload:allow(avatar, View, #{
        accept => [<<".jpg">>, <<".png">>],
        max_entries => 1,
        max_file_size => 5_000_000
    }).

handle_event(~"save", _Params, View) ->
    {Entries, View1} = arizona_upload:consume(avatar, View),
    lists:foreach(fun(#{data := Data, name := Name}) ->
        file:write_file(<<"/uploads/", Name/binary>>, Data)
    end, Entries),
    {[], View1}.
```
""".

-export([
    allow/3,
    consume/2,
    get_entries/2,
    validate_entry/3,
    put_chunk/4,
    cancel_entry/3
]).

-ignore_xref([allow/3, consume/2, get_entries/2, validate_entry/3, put_chunk/4, cancel_entry/3]).

-export_type([upload_config/0, upload_entry/0]).

-nominal upload_config() :: #{
    accept := [binary()],
    max_entries := pos_integer(),
    max_file_size := pos_integer()
}.

-nominal upload_entry() :: #{
    ref := binary(),
    name := binary(),
    size := non_neg_integer(),
    type := binary(),
    progress := 0..100,
    data := binary(),
    status := pending | uploading | done | error,
    errors := [binary()]
}.

-doc "Configure an upload channel on the view.".
-spec allow(atom(), arizona_view:view(), map()) -> arizona_view:view().
allow(Name, View, Opts) ->
    Config = #{
        accept => maps:get(accept, Opts, []),
        max_entries => maps:get(max_entries, Opts, 10),
        max_file_size => maps:get(max_file_size, Opts, 10_000_000)
    },
    State = arizona_view:get_state(View),
    Uploads = arizona_stateful:get_binding({uploads}, State),
    CurrentUploads =
        case Uploads of
            undefined -> #{};
            M when is_map(M) -> M
        end,
    State1 = arizona_stateful:put_binding(
        {uploads},
        CurrentUploads#{Name => #{config => Config, entries => []}},
        State
    ),
    arizona_view:update_state(State1, View).

-doc "Consume completed upload entries, removing them from state.".
-spec consume(atom(), arizona_view:view()) -> {[upload_entry()], arizona_view:view()}.
consume(Name, View) ->
    State = arizona_view:get_state(View),
    Uploads = arizona_stateful:get_binding({uploads}, State),
    case Uploads of
        #{Name := #{entries := Entries} = UploadData} ->
            Completed = [E || E = #{status := done} <- Entries],
            Remaining = [E || E <- Entries, maps:get(status, E) =/= done],
            State1 = arizona_stateful:put_binding(
                {uploads},
                Uploads#{Name := UploadData#{entries := Remaining}},
                State
            ),
            {Completed, arizona_view:update_state(State1, View)};
        _ ->
            {[], View}
    end.

-doc "Get current entries for an upload channel.".
-spec get_entries(atom(), arizona_view:view()) -> [upload_entry()].
get_entries(Name, View) ->
    State = arizona_view:get_state(View),
    Uploads = arizona_stateful:get_binding({uploads}, State),
    case Uploads of
        #{Name := #{entries := Entries}} -> Entries;
        _ -> []
    end.

-doc "Validate and accept a new upload entry.".
-spec validate_entry(atom(), map(), arizona_view:view()) ->
    {ok, arizona_view:view()} | {error, [binary()]}.
validate_entry(Name, Meta, View) ->
    State = arizona_view:get_state(View),
    Uploads = arizona_stateful:get_binding({uploads}, State),
    case Uploads of
        #{Name := #{config := Config, entries := Entries} = UploadData} ->
            Errors = validate_meta(Meta, Config, Entries),
            case Errors of
                [] ->
                    Entry = #{
                        ref => maps:get(ref, Meta),
                        name => maps:get(name, Meta),
                        size => maps:get(size, Meta, 0),
                        type => maps:get(type, Meta, <<>>),
                        progress => 0,
                        data => <<>>,
                        status => pending,
                        errors => []
                    },
                    State1 = arizona_stateful:put_binding(
                        {uploads},
                        Uploads#{Name := UploadData#{entries := Entries ++ [Entry]}},
                        State
                    ),
                    {ok, arizona_view:update_state(State1, View)};
                _ ->
                    {error, Errors}
            end;
        _ ->
            {error, [<<"upload channel not configured">>]}
    end.

-doc "Append a binary chunk to an upload entry.".
-spec put_chunk(atom(), binary(), binary(), arizona_view:view()) -> arizona_view:view().
put_chunk(Name, Ref, Chunk, View) ->
    State = arizona_view:get_state(View),
    Uploads = arizona_stateful:get_binding({uploads}, State),
    case Uploads of
        #{Name := #{entries := Entries} = UploadData} ->
            NewEntries = lists:map(
                fun
                    (#{ref := R} = E) when R =:= Ref ->
                        CurrentData = maps:get(data, E),
                        TotalSize = maps:get(size, E),
                        NewData = <<CurrentData/binary, Chunk/binary>>,
                        Progress =
                            case TotalSize of
                                0 -> 100;
                                _ -> min(100, (byte_size(NewData) * 100) div TotalSize)
                            end,
                        Status =
                            case Progress of
                                100 -> done;
                                _ -> uploading
                            end,
                        E#{data := NewData, progress := Progress, status := Status};
                    (E) ->
                        E
                end,
                Entries
            ),
            State1 = arizona_stateful:put_binding(
                {uploads},
                Uploads#{Name := UploadData#{entries := NewEntries}},
                State
            ),
            arizona_view:update_state(State1, View);
        _ ->
            View
    end.

-doc "Cancel an upload entry by ref.".
-spec cancel_entry(atom(), binary(), arizona_view:view()) -> arizona_view:view().
cancel_entry(Name, Ref, View) ->
    State = arizona_view:get_state(View),
    Uploads = arizona_stateful:get_binding({uploads}, State),
    case Uploads of
        #{Name := #{entries := Entries} = UploadData} ->
            NewEntries = [E || #{ref := R} = E <- Entries, R =/= Ref],
            State1 = arizona_stateful:put_binding(
                {uploads},
                Uploads#{Name := UploadData#{entries := NewEntries}},
                State
            ),
            arizona_view:update_state(State1, View);
        _ ->
            View
    end.

%%----------------------------------------------------------------------
%% Internal
%%----------------------------------------------------------------------

validate_meta(Meta, Config, Entries) ->
    #{max_entries := MaxEntries, max_file_size := MaxSize, accept := Accept} = Config,
    Errors0 =
        case length(Entries) >= MaxEntries of
            true -> [<<"too many files">>];
            false -> []
        end,
    Size = maps:get(size, Meta, 0),
    Errors1 =
        case Size > MaxSize of
            true -> [<<"file too large">> | Errors0];
            false -> Errors0
        end,
    case Accept of
        [] ->
            Errors1;
        _ ->
            FileName = maps:get(name, Meta, <<>>),
            Ext = filename_ext(FileName),
            case lists:member(Ext, Accept) of
                true -> Errors1;
                false -> [<<"file type not accepted">> | Errors1]
            end
    end.

filename_ext(Name) ->
    case binary:split(Name, <<".">>, [global]) of
        [_] -> <<>>;
        Parts -> <<".", (lists:last(Parts))/binary>>
    end.
