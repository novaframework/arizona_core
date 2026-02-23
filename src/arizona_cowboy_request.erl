-module(arizona_cowboy_request).
-behaviour(arizona_request).

-export([new/1]).
-export([parse_bindings/1]).
-export([parse_params/1]).
-export([parse_cookies/1]).
-export([parse_headers/1]).
-export([read_body/1]).

-ignore_xref([new/1]).

-spec new(CowboyReq) -> Request when
    CowboyReq :: cowboy_req:req(),
    Request :: arizona_request:request().
new(CowboyReq) ->
    Method = cowboy_req:method(CowboyReq),
    Path = cowboy_req:path(CowboyReq),
    arizona_request:new(?MODULE, CowboyReq, #{
        method => Method,
        path => Path
    }).

-spec parse_bindings(CowboyReq) -> Bindings when
    CowboyReq :: cowboy_req:req(),
    Bindings :: arizona_request:bindings().
parse_bindings(CowboyReq) ->
    cowboy_req:bindings(CowboyReq).

-spec parse_params(CowboyReq) -> Params when
    CowboyReq :: cowboy_req:req(),
    Params :: arizona_request:params().
parse_params(CowboyReq) ->
    cowboy_req:parse_qs(CowboyReq).

-spec parse_cookies(CowboyReq) -> Cookies when
    CowboyReq :: cowboy_req:req(),
    Cookies :: arizona_request:cookies().
parse_cookies(CowboyReq) ->
    cowboy_req:parse_cookies(CowboyReq).

-spec parse_headers(CowboyReq) -> Headers when
    CowboyReq :: cowboy_req:req(),
    Headers :: arizona_request:headers().
parse_headers(CowboyReq) ->
    cowboy_req:headers(CowboyReq).

-spec read_body(CowboyReq) -> {Body, UpdatedCowboyReq} when
    CowboyReq :: cowboy_req:req(),
    Body :: arizona_request:body(),
    UpdatedCowboyReq :: cowboy_req:req().
read_body(CowboyReq) ->
    {ok, Body, CowboyReq1} = cowboy_req:read_body(CowboyReq),
    {Body, CowboyReq1}.
