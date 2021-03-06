%%   The contents of this file are subject to the Mozilla Public License
%%   Version 1.1 (the "License"); you may not use this file except in
%%   compliance with the License. You may obtain a copy of the License at
%%   http://www.mozilla.org/MPL/
%%
%%   Software distributed under the License is distributed on an "AS IS"
%%   basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%%   License for the specific language governing rights and limitations
%%   under the License.
%%
%%   The Original Code is RabbitMQ Management Console.
%%
%%   The Initial Developer of the Original Code is GoPivotal, Inc.
%%   Copyright (c) 2007-2016 Pivotal Software, Inc.  All rights reserved.
%%

-module(rabbit_mgmt_test_http).

-include("rabbit_mgmt_test.hrl").

-export([http_get/1, http_put/3, http_delete/2]).

-import(rabbit_mgmt_test_util, [assert_list/2, assert_item/2, test_item/2,
                                assert_keys/2]).
-import(rabbit_misc, [pget/2]).

cors_test() ->
    %% With CORS disabled. No header should be received.
    {ok, {_, HdNoCORS, _}} = req(get, "/overview", [auth_header("guest", "guest")]),
    false = lists:keymember("access-control-allow-origin", 1, HdNoCORS),
    %% The Vary header should include "Origin" regardless of CORS configuration.
    {_, "accept-encoding, origin"} = lists:keyfind("vary", 1, HdNoCORS),
    %% Enable CORS.
    application:set_env(rabbitmq_management, cors_allow_origins, ["http://rabbitmq.com"]),
    %% We should only receive allow-origin and allow-credentials from GET.
    {ok, {_, HdGetCORS, _}} = req(get, "/overview",
        [{"origin", "http://rabbitmq.com"}, auth_header("guest", "guest")]),
    true = lists:keymember("access-control-allow-origin", 1, HdGetCORS),
    true = lists:keymember("access-control-allow-credentials", 1, HdGetCORS),
    false = lists:keymember("access-control-expose-headers", 1, HdGetCORS),
    false = lists:keymember("access-control-max-age", 1, HdGetCORS),
    false = lists:keymember("access-control-allow-methods", 1, HdGetCORS),
    false = lists:keymember("access-control-allow-headers", 1, HdGetCORS),
    %% We should receive allow-origin, allow-credentials and allow-methods from OPTIONS.
    {ok, {_, HdOptionsCORS, _}} = req(options, "/overview",
        [{"origin", "http://rabbitmq.com"}, auth_header("guest", "guest")]),
    true = lists:keymember("access-control-allow-origin", 1, HdOptionsCORS),
    true = lists:keymember("access-control-allow-credentials", 1, HdOptionsCORS),
    false = lists:keymember("access-control-expose-headers", 1, HdOptionsCORS),
    true = lists:keymember("access-control-max-age", 1, HdOptionsCORS),
    true = lists:keymember("access-control-allow-methods", 1, HdOptionsCORS),
    false = lists:keymember("access-control-allow-headers", 1, HdOptionsCORS),
    %% We should receive allow-headers when request-headers is sent.
    {ok, {_, HdAllowHeadersCORS, _}} = req(options, "/overview",
        [{"origin", "http://rabbitmq.com"},
         auth_header("guest", "guest"),
         {"access-control-request-headers", "x-piggy-bank"}]),
    {_, "x-piggy-bank"} = lists:keyfind("access-control-allow-headers", 1, HdAllowHeadersCORS),
    %% Disable preflight request caching.
    application:set_env(rabbitmq_management, cors_max_age, undefined),
    %% We shouldn't receive max-age anymore.
    {ok, {_, HdNoMaxAgeCORS, _}} = req(options, "/overview",
        [{"origin", "http://rabbitmq.com"}, auth_header("guest", "guest")]),
    false = lists:keymember("access-control-max-age", 1, HdNoMaxAgeCORS),
    %% Disable CORS again.
    application:set_env(rabbitmq_management, cors_allow_origins, []),
    ok.

overview_test() ->
    %% Rather crude, but this req doesn't say much and at least this means it
    %% didn't blow up.
    true = 0 < length(pget(listeners, http_get("/overview"))),
    http_put("/users/myuser", [{password, <<"myuser">>},
                               {tags,     <<"management">>}], [?CREATED, ?NO_CONTENT]),
    http_get("/overview", "myuser", "myuser", ?OK),
    http_delete("/users/myuser", ?NO_CONTENT),
    %% TODO uncomment when priv works in test
    %%http_get(""),
    ok.

cluster_name_test() ->
    http_put("/users/myuser", [{password, <<"myuser">>},
                               {tags,     <<"management">>}], [?CREATED, ?NO_CONTENT]),
    http_put("/cluster-name", [{name, "foo"}], "myuser", "myuser", ?NOT_AUTHORISED),
    http_put("/cluster-name", [{name, "foo"}], ?NO_CONTENT),
    [{name, <<"foo">>}] = http_get("/cluster-name", "myuser", "myuser", ?OK),
    http_delete("/users/myuser", ?NO_CONTENT),
    ok.

nodes_test() ->
    http_put("/users/user", [{password, <<"user">>},
                             {tags, <<"management">>}], [?CREATED, ?NO_CONTENT]),
    http_put("/users/monitor", [{password, <<"monitor">>},
                                {tags, <<"monitoring">>}], [?CREATED, ?NO_CONTENT]),
    DiscNode = [{type, <<"disc">>}, {running, true}],
    assert_list([DiscNode], http_get("/nodes")),
    assert_list([DiscNode], http_get("/nodes", "monitor", "monitor", ?OK)),
    http_get("/nodes", "user", "user", ?NOT_AUTHORISED),
    [Node] = http_get("/nodes"),
    Path = "/nodes/" ++ binary_to_list(pget(name, Node)),
    assert_item(DiscNode, http_get(Path, ?OK)),
    assert_item(DiscNode, http_get(Path, "monitor", "monitor", ?OK)),
    http_get(Path, "user", "user", ?NOT_AUTHORISED),
    http_delete("/users/user", ?NO_CONTENT),
    http_delete("/users/monitor", ?NO_CONTENT),
    ok.

memory_test() ->
    [Node] = http_get("/nodes"),
    Path = "/nodes/" ++ binary_to_list(pget(name, Node)) ++ "/memory",
    Result = http_get(Path, ?OK),
    assert_keys([memory], Result),
    Keys = [total, connection_readers, connection_writers, connection_channels,
            connection_other, queue_procs, queue_slave_procs, plugins,
            other_proc, mnesia, mgmt_db, msg_index, other_ets, binary, code,
            atom, other_system],
    assert_keys(Keys, pget(memory, Result)),
    http_get("/nodes/nonode/memory", ?NOT_FOUND),
    %% Relative memory as a percentage of the total
    Result1 = http_get(Path ++ "/relative", ?OK),
    assert_keys([memory], Result1),
    Breakdown = pget(memory, Result1),
    assert_keys(Keys, Breakdown),
    assert_item([{total, 100}], Breakdown),
    assert_percentage(Breakdown),
    http_get("/nodes/nonode/memory/relative", ?NOT_FOUND),
    ok.

assert_percentage(Breakdown) ->
    Total = lists:sum([P || {K, P} <- Breakdown, K =/= total]),
    Count = length(Breakdown) - 1,
    %% Rounding up and down can lose some digits. Never more than the number
    %% of items in the breakdown.
    case ((Total =< 100 + Count) andalso (Total >= 100 - Count)) of
        false ->
            throw({bad_percentage, Total, Breakdown});
        true ->
            ok
    end.

auth_test() ->
    http_put("/users/user", [{password, <<"user">>},
                             {tags, <<"">>}], [?CREATED, ?NO_CONTENT]),
    test_auth(?NOT_AUTHORISED, []),
    test_auth(?NOT_AUTHORISED, [auth_header("user", "user")]),
    test_auth(?NOT_AUTHORISED, [auth_header("guest", "gust")]),
    test_auth(?OK, [auth_header("guest", "guest")]),
    http_delete("/users/user", ?NO_CONTENT),
    ok.

%% This test is rather over-verbose as we're trying to test understanding of
%% Webmachine
vhosts_test() ->
    assert_list([[{name, <<"/">>}]], http_get("/vhosts")),
    %% Create a new one
    http_put("/vhosts/myvhost", none, [?CREATED, ?NO_CONTENT]),
    %% PUT should be idempotent
    http_put("/vhosts/myvhost", none, ?NO_CONTENT),
    %% Check it's there
    assert_list([[{name, <<"/">>}], [{name, <<"myvhost">>}]],
                http_get("/vhosts")),
    %% Check individually
    assert_item([{name, <<"/">>}], http_get("/vhosts/%2f", ?OK)),
    assert_item([{name, <<"myvhost">>}],http_get("/vhosts/myvhost")),
    %% Delete it
    http_delete("/vhosts/myvhost", ?NO_CONTENT),
    %% It's not there
    http_get("/vhosts/myvhost", ?NOT_FOUND),
    http_delete("/vhosts/myvhost", ?NOT_FOUND).

vhosts_trace_test() ->
    http_put("/vhosts/myvhost", none, [?CREATED, ?NO_CONTENT]),
    Disabled = [{name,  <<"myvhost">>}, {tracing, false}],
    Enabled  = [{name,  <<"myvhost">>}, {tracing, true}],
    Disabled = http_get("/vhosts/myvhost"),
    http_put("/vhosts/myvhost", [{tracing, true}], ?NO_CONTENT),
    Enabled = http_get("/vhosts/myvhost"),
    http_put("/vhosts/myvhost", [{tracing, true}], ?NO_CONTENT),
    Enabled = http_get("/vhosts/myvhost"),
    http_put("/vhosts/myvhost", [{tracing, false}], ?NO_CONTENT),
    Disabled = http_get("/vhosts/myvhost"),
    http_delete("/vhosts/myvhost", ?NO_CONTENT).

users_test() ->
    assert_item([{name, <<"guest">>}, {tags, <<"administrator">>}],
                http_get("/whoami")),
    http_get("/users/myuser", ?NOT_FOUND),
    http_put_raw("/users/myuser", "Something not JSON", ?BAD_REQUEST),
    http_put("/users/myuser", [{flim, <<"flam">>}], ?BAD_REQUEST),
    http_put("/users/myuser", [{tags, <<"management">>}], [?CREATED, ?NO_CONTENT]),
    http_put("/users/myuser", [{password_hash, <<"not_hash">>}], ?BAD_REQUEST),
    http_put("/users/myuser", [{password_hash,
                                <<"IECV6PZI/Invh0DL187KFpkO5Jc=">>},
                               {tags, <<"management">>}], ?NO_CONTENT),
    assert_item([{name, <<"myuser">>}, {tags, <<"management">>},
                 {password_hash, <<"IECV6PZI/Invh0DL187KFpkO5Jc=">>},
                 {hashing_algorithm, <<"rabbit_password_hashing_sha256">>}],
                http_get("/users/myuser")),

    http_put("/users/myuser", [{password_hash,
                                <<"IECV6PZI/Invh0DL187KFpkO5Jc=">>},
                               {hashing_algorithm, <<"rabbit_password_hashing_md5">>},
                               {tags, <<"management">>}], ?NO_CONTENT),
    assert_item([{name, <<"myuser">>}, {tags, <<"management">>},
                 {password_hash, <<"IECV6PZI/Invh0DL187KFpkO5Jc=">>},
                 {hashing_algorithm, <<"rabbit_password_hashing_md5">>}],
                http_get("/users/myuser")),
    http_put("/users/myuser", [{password, <<"password">>},
                               {tags, <<"administrator, foo">>}], ?NO_CONTENT),
    assert_item([{name, <<"myuser">>}, {tags, <<"administrator,foo">>}],
                http_get("/users/myuser")),
    assert_list([[{name, <<"myuser">>}, {tags, <<"administrator,foo">>}],
                 [{name, <<"guest">>}, {tags, <<"administrator">>}]],
                http_get("/users")),
    test_auth(?OK, [auth_header("myuser", "password")]),
    http_delete("/users/myuser", ?NO_CONTENT),
    test_auth(?NOT_AUTHORISED, [auth_header("myuser", "password")]),
    http_get("/users/myuser", ?NOT_FOUND),
    ok.

users_legacy_administrator_test() ->
    http_put("/users/myuser1", [{administrator, <<"true">>}], [?CREATED, ?NO_CONTENT]),
    http_put("/users/myuser2", [{administrator, <<"false">>}], [?CREATED, ?NO_CONTENT]),
    assert_item([{name, <<"myuser1">>}, {tags, <<"administrator">>}],
                http_get("/users/myuser1")),
    assert_item([{name, <<"myuser2">>}, {tags, <<"">>}],
                http_get("/users/myuser2")),
    http_delete("/users/myuser1", ?NO_CONTENT),
    http_delete("/users/myuser2", ?NO_CONTENT),
    ok.

permissions_validation_test() ->
    Good = [{configure, <<".*">>}, {write, <<".*">>}, {read, <<".*">>}],
    http_put("/permissions/wrong/guest", Good, ?BAD_REQUEST),
    http_put("/permissions/%2f/wrong", Good, ?BAD_REQUEST),
    http_put("/permissions/%2f/guest",
             [{configure, <<"[">>}, {write, <<".*">>}, {read, <<".*">>}],
             ?BAD_REQUEST),
    http_put("/permissions/%2f/guest", Good, ?NO_CONTENT),
    ok.

permissions_list_test() ->
    [[{user,<<"guest">>},
      {vhost,<<"/">>},
      {configure,<<".*">>},
      {write,<<".*">>},
      {read,<<".*">>}]] =
        http_get("/permissions"),

    http_put("/users/myuser1", [{password, <<"">>}, {tags, <<"administrator">>}],
             [?CREATED, ?NO_CONTENT]),
    http_put("/users/myuser2", [{password, <<"">>}, {tags, <<"administrator">>}],
             [?CREATED, ?NO_CONTENT]),
    http_put("/vhosts/myvhost1", none, [?CREATED, ?NO_CONTENT]),
    http_put("/vhosts/myvhost2", none, [?CREATED, ?NO_CONTENT]),

    Perms = [{configure, <<"foo">>}, {write, <<"foo">>}, {read, <<"foo">>}],
    http_put("/permissions/myvhost1/myuser1", Perms, [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/myvhost2/myuser1", Perms, [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/myvhost1/myuser2", Perms, [?CREATED, ?NO_CONTENT]),

    4 = length(http_get("/permissions")),
    2 = length(http_get("/users/myuser1/permissions")),
    1 = length(http_get("/users/myuser2/permissions")),

    http_get("/users/notmyuser/permissions", ?NOT_FOUND),
    http_get("/vhosts/notmyvhost/permissions", ?NOT_FOUND),

    http_delete("/users/myuser1", ?NO_CONTENT),
    http_delete("/users/myuser2", ?NO_CONTENT),
    http_delete("/vhosts/myvhost1", ?NO_CONTENT),
    http_delete("/vhosts/myvhost2", ?NO_CONTENT),
    ok.

permissions_test() ->
    http_put("/users/myuser", [{password, <<"myuser">>}, {tags, <<"administrator">>}],
             [?CREATED, ?NO_CONTENT]),
    http_put("/vhosts/myvhost", none, [?CREATED, ?NO_CONTENT]),

    http_put("/permissions/myvhost/myuser",
             [{configure, <<"foo">>}, {write, <<"foo">>}, {read, <<"foo">>}],
             [?CREATED, ?NO_CONTENT]),

    Permission = [{user,<<"myuser">>},
                  {vhost,<<"myvhost">>},
                  {configure,<<"foo">>},
                  {write,<<"foo">>},
                  {read,<<"foo">>}],
    Default = [{user,<<"guest">>},
               {vhost,<<"/">>},
               {configure,<<".*">>},
               {write,<<".*">>},
               {read,<<".*">>}],
    Permission = http_get("/permissions/myvhost/myuser"),
    assert_list([Permission, Default], http_get("/permissions")),
    assert_list([Permission], http_get("/users/myuser/permissions")),
    http_delete("/permissions/myvhost/myuser", ?NO_CONTENT),
    http_get("/permissions/myvhost/myuser", ?NOT_FOUND),

    http_delete("/users/myuser", ?NO_CONTENT),
    http_delete("/vhosts/myvhost", ?NO_CONTENT),
    ok.

connections_test() ->
    {ok, Conn} = amqp_connection:start(#amqp_params_network{}),
    LocalPort = local_port(Conn),
    Path = binary_to_list(
             rabbit_mgmt_format:print(
               "/connections/127.0.0.1%3A~w%20->%20127.0.0.1%3A5672",
               [LocalPort])),
    http_get(Path, ?OK),
    http_delete(Path, ?NO_CONTENT),
    %% TODO rabbit_reader:shutdown/2 returns before the connection is
    %% closed. It may not be worth fixing.
    timer:sleep(200),
    http_get(Path, ?NOT_FOUND).

test_auth(Code, Headers) ->
    {ok, {{_, Code, _}, _, _}} = req(get, "/overview", Headers).

exchanges_test() ->
    %% Can pass booleans or strings
    Good = [{type, <<"direct">>}, {durable, <<"true">>}],
    http_put("/vhosts/myvhost", none, [?CREATED, ?NO_CONTENT]),
    http_get("/exchanges/myvhost/foo", ?NOT_AUTHORISED),
    http_put("/exchanges/myvhost/foo", Good, ?NOT_AUTHORISED),
    http_put("/permissions/myvhost/guest",
             [{configure, <<".*">>}, {write, <<".*">>}, {read, <<".*">>}],
             [?CREATED, ?NO_CONTENT]),
    http_get("/exchanges/myvhost/foo", ?NOT_FOUND),
    http_put("/exchanges/myvhost/foo", Good, [?CREATED, ?NO_CONTENT]),
    http_put("/exchanges/myvhost/foo", Good, ?NO_CONTENT),
    http_get("/exchanges/%2f/foo", ?NOT_FOUND),
    assert_item([{name,<<"foo">>},
                 {vhost,<<"myvhost">>},
                 {type,<<"direct">>},
                 {durable,true},
                 {auto_delete,false},
                 {internal,false},
                 {arguments,[]}],
                http_get("/exchanges/myvhost/foo")),

    http_put("/exchanges/badvhost/bar", Good, ?NOT_FOUND),
    http_put("/exchanges/myvhost/bar", [{type, <<"bad_exchange_type">>}],
             ?BAD_REQUEST),
    http_put("/exchanges/myvhost/bar", [{type, <<"direct">>},
                                        {durable, <<"troo">>}],
             ?BAD_REQUEST),
    http_put("/exchanges/myvhost/foo", [{type, <<"direct">>}],
             ?BAD_REQUEST),

    http_delete("/exchanges/myvhost/foo", ?NO_CONTENT),
    http_delete("/exchanges/myvhost/foo", ?NOT_FOUND),

    http_delete("/vhosts/myvhost", ?NO_CONTENT),
    http_get("/exchanges/badvhost", ?NOT_FOUND),
    ok.

queues_test() ->
    Good = [{durable, true}],
    http_get("/queues/%2f/foo", ?NOT_FOUND),
    http_put("/queues/%2f/foo", Good, [?CREATED, ?NO_CONTENT]),
    http_put("/queues/%2f/foo", Good, ?NO_CONTENT),
    http_get("/queues/%2f/foo", ?OK),

    http_put("/queues/badvhost/bar", Good, ?NOT_FOUND),
    http_put("/queues/%2f/bar",
             [{durable, <<"troo">>}],
             ?BAD_REQUEST),
    http_put("/queues/%2f/foo",
             [{durable, false}],
             ?BAD_REQUEST),

    http_put("/queues/%2f/baz", Good, [?CREATED, ?NO_CONTENT]),

    Queues = http_get("/queues/%2f"),
    Queue = http_get("/queues/%2f/foo"),
    assert_list([[{name,        <<"foo">>},
                  {vhost,       <<"/">>},
                  {durable,     true},
                  {auto_delete, false},
                  {exclusive,   false},
                  {arguments,   []}],
                 [{name,        <<"baz">>},
                  {vhost,       <<"/">>},
                  {durable,     true},
                  {auto_delete, false},
                  {exclusive,   false},
                  {arguments,   []}]], Queues),
    assert_item([{name,        <<"foo">>},
                 {vhost,       <<"/">>},
                 {durable,     true},
                 {auto_delete, false},
                 {exclusive,   false},
                 {arguments,   []}], Queue),

    http_delete("/queues/%2f/foo", ?NO_CONTENT),
    http_delete("/queues/%2f/baz", ?NO_CONTENT),
    http_delete("/queues/%2f/foo", ?NOT_FOUND),
    http_get("/queues/badvhost", ?NOT_FOUND),
    ok.

bindings_test() ->
    XArgs = [{type, <<"direct">>}],
    QArgs = [],
    http_put("/exchanges/%2f/myexchange", XArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/queues/%2f/myqueue", QArgs, [?CREATED, ?NO_CONTENT]),
    BArgs = [{routing_key, <<"routing">>}, {arguments, []}],
    http_post("/bindings/%2f/e/myexchange/q/myqueue", BArgs, [?CREATED, ?NO_CONTENT]),
    http_get("/bindings/%2f/e/myexchange/q/myqueue/routing", ?OK),
    http_get("/bindings/%2f/e/myexchange/q/myqueue/rooting", ?NOT_FOUND),
    Binding =
        [{source,<<"myexchange">>},
         {vhost,<<"/">>},
         {destination,<<"myqueue">>},
         {destination_type,<<"queue">>},
         {routing_key,<<"routing">>},
         {arguments,[]},
         {properties_key,<<"routing">>}],
    DBinding =
        [{source,<<"">>},
         {vhost,<<"/">>},
         {destination,<<"myqueue">>},
         {destination_type,<<"queue">>},
         {routing_key,<<"myqueue">>},
         {arguments,[]},
         {properties_key,<<"myqueue">>}],
    Binding = http_get("/bindings/%2f/e/myexchange/q/myqueue/routing"),
    assert_list([Binding],
                http_get("/bindings/%2f/e/myexchange/q/myqueue")),
    assert_list([Binding, DBinding],
                http_get("/queues/%2f/myqueue/bindings")),
    assert_list([Binding],
                http_get("/exchanges/%2f/myexchange/bindings/source")),
    http_delete("/bindings/%2f/e/myexchange/q/myqueue/routing", ?NO_CONTENT),
    http_delete("/bindings/%2f/e/myexchange/q/myqueue/routing", ?NOT_FOUND),
    http_delete("/exchanges/%2f/myexchange", ?NO_CONTENT),
    http_delete("/queues/%2f/myqueue", ?NO_CONTENT),
    http_get("/bindings/badvhost", ?NOT_FOUND),
    http_get("/bindings/badvhost/myqueue/myexchange/routing", ?NOT_FOUND),
    http_get("/bindings/%2f/e/myexchange/q/myqueue/routing", ?NOT_FOUND),
    ok.

bindings_post_test() ->
    XArgs = [{type, <<"direct">>}],
    QArgs = [],
    BArgs = [{routing_key, <<"routing">>}, {arguments, [{foo, <<"bar">>}]}],
    http_put("/exchanges/%2f/myexchange", XArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/queues/%2f/myqueue", QArgs, [?CREATED, ?NO_CONTENT]),
    http_post("/bindings/%2f/e/myexchange/q/badqueue", BArgs, ?NOT_FOUND),
    http_post("/bindings/%2f/e/badexchange/q/myqueue", BArgs, ?NOT_FOUND),
    Headers1 = http_post("/bindings/%2f/e/myexchange/q/myqueue", [], [?CREATED, ?NO_CONTENT]),
    "../../../../%2F/e/myexchange/q/myqueue/~" = pget("location", Headers1),
    Headers2 = http_post("/bindings/%2f/e/myexchange/q/myqueue", BArgs, [?CREATED, ?NO_CONTENT]),
    PropertiesKey = "routing~V4mGFgnPNrdtRmluZIxTDA",
    PropertiesKeyBin = list_to_binary(PropertiesKey),
    "../../../../%2F/e/myexchange/q/myqueue/" ++ PropertiesKey =
        pget("location", Headers2),
    URI = "/bindings/%2F/e/myexchange/q/myqueue/" ++ PropertiesKey,
    [{source,<<"myexchange">>},
     {vhost,<<"/">>},
     {destination,<<"myqueue">>},
     {destination_type,<<"queue">>},
     {routing_key,<<"routing">>},
     {arguments,[{foo,<<"bar">>}]},
     {properties_key,PropertiesKeyBin}] = http_get(URI, ?OK),
    http_get(URI ++ "x", ?NOT_FOUND),
    http_delete(URI, ?NO_CONTENT),
    http_delete("/exchanges/%2f/myexchange", ?NO_CONTENT),
    http_delete("/queues/%2f/myqueue", ?NO_CONTENT),
    ok.

bindings_e2e_test() ->
    BArgs = [{routing_key, <<"routing">>}, {arguments, []}],
    http_post("/bindings/%2f/e/amq.direct/e/badexchange", BArgs, ?NOT_FOUND),
    http_post("/bindings/%2f/e/badexchange/e/amq.fanout", BArgs, ?NOT_FOUND),
    Headers = http_post("/bindings/%2f/e/amq.direct/e/amq.fanout", BArgs, [?CREATED, ?NO_CONTENT]),
    "../../../../%2F/e/amq.direct/e/amq.fanout/routing" =
        pget("location", Headers),
    [{source,<<"amq.direct">>},
     {vhost,<<"/">>},
     {destination,<<"amq.fanout">>},
     {destination_type,<<"exchange">>},
     {routing_key,<<"routing">>},
     {arguments,[]},
     {properties_key,<<"routing">>}] =
        http_get("/bindings/%2f/e/amq.direct/e/amq.fanout/routing", ?OK),
    http_delete("/bindings/%2f/e/amq.direct/e/amq.fanout/routing", ?NO_CONTENT),
    http_post("/bindings/%2f/e/amq.direct/e/amq.headers", BArgs, [?CREATED, ?NO_CONTENT]),
    Binding =
        [{source,<<"amq.direct">>},
         {vhost,<<"/">>},
         {destination,<<"amq.headers">>},
         {destination_type,<<"exchange">>},
         {routing_key,<<"routing">>},
         {arguments,[]},
         {properties_key,<<"routing">>}],
    Binding = http_get("/bindings/%2f/e/amq.direct/e/amq.headers/routing"),
    assert_list([Binding],
                http_get("/bindings/%2f/e/amq.direct/e/amq.headers")),
    assert_list([Binding],
                http_get("/exchanges/%2f/amq.direct/bindings/source")),
    assert_list([Binding],
                http_get("/exchanges/%2f/amq.headers/bindings/destination")),
    http_delete("/bindings/%2f/e/amq.direct/e/amq.headers/routing", ?NO_CONTENT),
    http_get("/bindings/%2f/e/amq.direct/e/amq.headers/rooting", ?NOT_FOUND),
    ok.

permissions_administrator_test() ->
    http_put("/users/isadmin", [{password, <<"isadmin">>},
                                {tags, <<"administrator">>}], [?CREATED, ?NO_CONTENT]),
    http_put("/users/notadmin", [{password, <<"notadmin">>},
                                 {tags, <<"administrator">>}], [?CREATED, ?NO_CONTENT]),
    http_put("/users/notadmin", [{password, <<"notadmin">>},
                                 {tags, <<"management">>}], ?NO_CONTENT),
    Test =
        fun(Path) ->
                http_get(Path, "notadmin", "notadmin", ?NOT_AUTHORISED),
                http_get(Path, "isadmin", "isadmin", ?OK),
                http_get(Path, "guest", "guest", ?OK)
        end,
    %% All users can get a list of vhosts. It may be filtered.
    %%Test("/vhosts"),
    Test("/vhosts/%2f"),
    Test("/vhosts/%2f/permissions"),
    Test("/users"),
    Test("/users/guest"),
    Test("/users/guest/permissions"),
    Test("/permissions"),
    Test("/permissions/%2f/guest"),
    http_delete("/users/notadmin", ?NO_CONTENT),
    http_delete("/users/isadmin", ?NO_CONTENT),
    ok.

permissions_vhost_test() ->
    QArgs = [],
    PermArgs = [{configure, <<".*">>}, {write, <<".*">>}, {read, <<".*">>}],
    http_put("/users/myuser", [{password, <<"myuser">>},
                               {tags, <<"management">>}], [?CREATED, ?NO_CONTENT]),
    http_put("/vhosts/myvhost1", none, [?CREATED, ?NO_CONTENT]),
    http_put("/vhosts/myvhost2", none, [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/myvhost1/myuser", PermArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/myvhost1/guest", PermArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/myvhost2/guest", PermArgs, [?CREATED, ?NO_CONTENT]),
    assert_list([[{name, <<"/">>}],
                 [{name, <<"myvhost1">>}],
                 [{name, <<"myvhost2">>}]], http_get("/vhosts", ?OK)),
    assert_list([[{name, <<"myvhost1">>}]],
                http_get("/vhosts", "myuser", "myuser", ?OK)),
    http_put("/queues/myvhost1/myqueue", QArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/queues/myvhost2/myqueue", QArgs, [?CREATED, ?NO_CONTENT]),
    Test1 =
        fun(Path) ->
                Results = http_get(Path, "myuser", "myuser", ?OK),
                [case pget(vhost, Result) of
                     <<"myvhost2">> ->
                         throw({got_result_from_vhost2_in, Path, Result});
                     _ ->
                         ok
                 end || Result <- Results]
        end,
    Test2 =
        fun(Path1, Path2) ->
                http_get(Path1 ++ "/myvhost1/" ++ Path2, "myuser", "myuser",
                         ?OK),
                http_get(Path1 ++ "/myvhost2/" ++ Path2, "myuser", "myuser",
                         ?NOT_AUTHORISED)
        end,
    Test1("/exchanges"),
    Test2("/exchanges", ""),
    Test2("/exchanges", "amq.direct"),
    Test1("/queues"),
    Test2("/queues", ""),
    Test2("/queues", "myqueue"),
    Test1("/bindings"),
    Test2("/bindings", ""),
    Test2("/queues", "myqueue/bindings"),
    Test2("/exchanges", "amq.default/bindings/source"),
    Test2("/exchanges", "amq.default/bindings/destination"),
    Test2("/bindings", "e/amq.default/q/myqueue"),
    Test2("/bindings", "e/amq.default/q/myqueue/myqueue"),
    http_delete("/vhosts/myvhost1", ?NO_CONTENT),
    http_delete("/vhosts/myvhost2", ?NO_CONTENT),
    http_delete("/users/myuser", ?NO_CONTENT),
    ok.

permissions_amqp_test() ->
    %% Just test that it works at all, not that it works in all possible cases.
    QArgs = [],
    PermArgs = [{configure, <<"foo.*">>}, {write, <<"foo.*">>},
                {read,      <<"foo.*">>}],
    http_put("/users/myuser", [{password, <<"myuser">>},
                               {tags, <<"management">>}], [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/%2f/myuser", PermArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/queues/%2f/bar-queue", QArgs, "myuser", "myuser",
             ?NOT_AUTHORISED),
    http_put("/queues/%2f/bar-queue", QArgs, "nonexistent", "nonexistent",
             ?NOT_AUTHORISED),
    http_delete("/users/myuser", ?NO_CONTENT),
    ok.

get_conn(Username, Password) ->
    {ok, Conn} = amqp_connection:start(#amqp_params_network{
					  username = list_to_binary(Username),
					  password = list_to_binary(Password)}),
    LocalPort = local_port(Conn),
    ConnPath = rabbit_misc:format(
                 "/connections/127.0.0.1%3A~w%20->%20127.0.0.1%3A5672",
                 [LocalPort]),
    ChPath = rabbit_misc:format(
               "/channels/127.0.0.1%3A~w%20->%20127.0.0.1%3A5672%20(1)",
               [LocalPort]),
    ConnChPath = rabbit_misc:format(
                   "/connections/127.0.0.1%3A~w%20->%20127.0.0.1%3A5672/channels",
                   [LocalPort]),
    {Conn, ConnPath, ChPath, ConnChPath}.

permissions_connection_channel_consumer_test() ->
    PermArgs = [{configure, <<".*">>}, {write, <<".*">>}, {read, <<".*">>}],
    http_put("/users/user", [{password, <<"user">>},
                             {tags, <<"management">>}], [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/%2f/user", PermArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/users/monitor", [{password, <<"monitor">>},
                                {tags, <<"monitoring">>}], [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/%2f/monitor", PermArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/queues/%2f/test", [], [?CREATED, ?NO_CONTENT]),

    {Conn1, UserConn, UserCh, UserConnCh} = get_conn("user", "user"),
    {Conn2, MonConn, MonCh, MonConnCh} = get_conn("monitor", "monitor"),
    {Conn3, AdmConn, AdmCh, AdmConnCh} = get_conn("guest", "guest"),
    {ok, Ch1} = amqp_connection:open_channel(Conn1),
    {ok, Ch2} = amqp_connection:open_channel(Conn2),
    {ok, Ch3} = amqp_connection:open_channel(Conn3),
    [amqp_channel:subscribe(
       Ch, #'basic.consume'{queue = <<"test">>}, self()) ||
        Ch <- [Ch1, Ch2, Ch3]],
    AssertLength = fun (Path, User, Len) ->
                           ?assertEqual(Len,
                                        length(http_get(Path, User, User, ?OK)))
                   end,
    [begin
         AssertLength(P, "user", 1),
         AssertLength(P, "monitor", 3),
         AssertLength(P, "guest", 3)
     end || P <- ["/connections", "/channels", "/consumers", "/consumers/%2f"]],

    AssertRead = fun(Path, UserStatus) ->
                         http_get(Path, "user", "user", UserStatus),
                         http_get(Path, "monitor", "monitor", ?OK),
                         http_get(Path, ?OK)
                 end,
    AssertRead(UserConn, ?OK),
    AssertRead(MonConn, ?NOT_AUTHORISED),
    AssertRead(AdmConn, ?NOT_AUTHORISED),
    AssertRead(UserCh, ?OK),
    AssertRead(MonCh, ?NOT_AUTHORISED),
    AssertRead(AdmCh, ?NOT_AUTHORISED),
    AssertRead(UserConnCh, ?OK),
    AssertRead(MonConnCh, ?NOT_AUTHORISED),
    AssertRead(AdmConnCh, ?NOT_AUTHORISED),

    AssertClose = fun(Path, User, Status) ->
                          http_delete(Path, User, User, Status)
                  end,
    AssertClose(UserConn, "monitor", ?NOT_AUTHORISED),
    AssertClose(MonConn, "user", ?NOT_AUTHORISED),
    AssertClose(AdmConn, "guest", ?NO_CONTENT),
    AssertClose(MonConn, "guest", ?NO_CONTENT),
    AssertClose(UserConn, "user", ?NO_CONTENT),

    http_delete("/users/user", ?NO_CONTENT),
    http_delete("/users/monitor", ?NO_CONTENT),
    http_get("/connections/foo", ?NOT_FOUND),
    http_get("/channels/foo", ?NOT_FOUND),
    http_delete("/queues/%2f/test", ?NO_CONTENT),
    ok.




consumers_test() ->
    http_put("/queues/%2f/test", [], [?CREATED, ?NO_CONTENT]),
    {Conn, _ConnPath, _ChPath, _ConnChPath} = get_conn("guest", "guest"),
    {ok, Ch} = amqp_connection:open_channel(Conn),
    amqp_channel:subscribe(
      Ch, #'basic.consume'{queue        = <<"test">>,
                           no_ack       = false,
                           consumer_tag = <<"my-ctag">> }, self()),
    assert_list([[{exclusive,    false},
                  {ack_required, true},
                  {consumer_tag, <<"my-ctag">>}]], http_get("/consumers")),
    amqp_connection:close(Conn),
    http_delete("/queues/%2f/test", ?NO_CONTENT),
    ok.

defs(Key, URI, CreateMethod, Args) ->
    defs(Key, URI, CreateMethod, Args,
         fun(URI2) -> http_delete(URI2, ?NO_CONTENT) end).

defs_v(Key, URI, CreateMethod, Args) ->
    Rep1 = fun (S, S2) -> re:replace(S, "<vhost>", S2, [{return, list}]) end,
    Rep2 = fun (L, V2) -> lists:keymap(fun (vhost) -> V2;
                                           (V)     -> V end, 2, L) end,
    %% Test against default vhost
    defs(Key, Rep1(URI, "%2f"), CreateMethod, Rep2(Args, <<"/">>)),

    %% Test against new vhost
    http_put("/vhosts/test", none, [?CREATED, ?NO_CONTENT]),
    PermArgs = [{configure, <<".*">>}, {write, <<".*">>}, {read, <<".*">>}],
    http_put("/permissions/test/guest", PermArgs, [?CREATED, ?NO_CONTENT]),
    defs(Key, Rep1(URI, "test"), CreateMethod, Rep2(Args, <<"test">>),
         fun(URI2) -> http_delete(URI2, ?NO_CONTENT),
                      http_delete("/vhosts/test", ?NO_CONTENT) end).

create(CreateMethod, URI, Args) ->
    case CreateMethod of
        put        -> http_put(URI, Args, [?CREATED, ?NO_CONTENT]),
                      URI;
        put_update -> http_put(URI, Args, ?NO_CONTENT),
                      URI;
        post       -> Headers = http_post(URI, Args, [?CREATED, ?NO_CONTENT]),
                      rabbit_web_dispatch_util:unrelativise(
                        URI, pget("location", Headers))
    end.

defs(Key, URI, CreateMethod, Args, DeleteFun) ->
    %% Create the item
    URI2 = create(CreateMethod, URI, Args),
    %% Make sure it ends up in definitions
    Definitions = http_get("/definitions", ?OK),
    true = lists:any(fun(I) -> test_item(Args, I) end, pget(Key, Definitions)),

    %% Delete it
    DeleteFun(URI2),

    %% Post the definitions back, it should get recreated in correct form
    http_post("/definitions", Definitions, ?NO_CONTENT),
    assert_item(Args, http_get(URI2, ?OK)),

    %% And delete it again
    DeleteFun(URI2),

    ok.

definitions_test() ->
    rabbit_runtime_parameters_test:register(),
    rabbit_runtime_parameters_test:register_policy_validator(),

    defs_v(queues, "/queues/<vhost>/my-queue", put,
           [{name,    <<"my-queue">>},
            {durable, true}]),
    defs_v(exchanges, "/exchanges/<vhost>/my-exchange", put,
           [{name, <<"my-exchange">>},
            {type, <<"direct">>}]),
    defs_v(bindings, "/bindings/<vhost>/e/amq.direct/e/amq.fanout", post,
           [{routing_key, <<"routing">>}, {arguments, []}]),
    defs_v(policies, "/policies/<vhost>/my-policy", put,
           [{vhost,      vhost},
            {name,       <<"my-policy">>},
            {pattern,    <<".*">>},
            {definition, [{testpos, [1, 2, 3]}]},
            {priority,   1}]),
    defs_v(parameters, "/parameters/test/<vhost>/good", put,
           [{vhost,     vhost},
            {component, <<"test">>},
            {name,      <<"good">>},
            {value,     <<"ignore">>}]),
    defs(users, "/users/myuser", put,
         [{name,          <<"myuser">>},
          {password_hash, <<"WAbU0ZIcvjTpxM3Q3SbJhEAM2tQ=">>},
          {hashing_algorithm, <<"rabbit_password_hashing_sha256">>},
          {tags,          <<"management">>}]),
    defs(vhosts, "/vhosts/myvhost", put,
         [{name, <<"myvhost">>}]),

    %% The guest permissions exist by default.
    defs(permissions, "/permissions/%2f/guest", put_update,
         [{user,      <<"guest">>},
          {vhost,     <<"/">>},
          {configure, <<"c">>},
          {write,     <<"w">>},
          {read,      <<"r">>}]),

    %% Set the guest's permissions back to normal.
    http_put("/permissions/%2f/guest",
             [{configure, <<".*">>},
              {write,     <<".*">>},
              {read,      <<".*">>}], [?CREATED, ?NO_CONTENT]),
    %% POST using multipart/form-data.
    Definitions = http_get("/definitions", ?OK),
    http_post_multipart("/definitions", data, Definitions, ?SEE_OTHER),

    %% POST using a file.
    Definitions = http_get("/definitions", ?OK),
    http_post_multipart("/definitions", file, Definitions, ?SEE_OTHER),

    BrokenConfig =
        [{users,       []},
         {vhosts,      []},
         {permissions, []},
         {queues,      []},
         {exchanges,   [[{name,        <<"amq.direct">>},
                         {vhost,       <<"/">>},
                         {type,        <<"definitely not direct">>},
                         {durable,     true},
                         {auto_delete, false},
                         {arguments,   []}
                        ]]},
         {bindings,    []}],
    http_post("/definitions", BrokenConfig, ?BAD_REQUEST),

    rabbit_runtime_parameters_test:unregister_policy_validator(),
    rabbit_runtime_parameters_test:unregister(),
    ok.

defs_vhost(Key, URI, CreateMethod, Args) ->
    Rep1 = fun (S, S2) -> re:replace(S, "<vhost>", S2, [{return, list}]) end,
    Rep2 = fun (L, V2) -> lists:keymap(fun (vhost) -> V2;
                                           (V)     -> V end, 2, L) end,

    %% Create test vhost
    http_put("/vhosts/test", none, [?CREATED, ?NO_CONTENT]),
    PermArgs = [{configure, <<".*">>}, {write, <<".*">>}, {read, <<".*">>}],
    http_put("/permissions/test/guest", PermArgs, [?CREATED, ?NO_CONTENT]),

    %% Test against default vhost
    defs_vhost(Key, URI, Rep1, "%2f", "test", CreateMethod,
               Rep2(Args, <<"/">>), Rep2(Args, <<"test">>),
               fun(URI2) -> http_delete(URI2, [?NO_CONTENT, ?CREATED]) end),

    %% Test against test vhost
    defs_vhost(Key, URI, Rep1, "test", "%2f", CreateMethod,
               Rep2(Args, <<"test">>), Rep2(Args, <<"/">>),
               fun(URI2) -> http_delete(URI2, [?NO_CONTENT, ?CREATED]) end),

    %% Remove test vhost
    http_delete("/vhosts/test", [?NO_CONTENT, ?CREATED]).


defs_vhost(Key, URI0, Rep1, VHost1, VHost2, CreateMethod, Args1, Args2,
           DeleteFun) ->
    %% Create the item
    URI2 = create(CreateMethod, Rep1(URI0, VHost1), Args1),
    %% Make sure it ends up in definitions
    Definitions = http_get("/definitions/" ++ VHost1, ?OK),
    true = lists:any(fun(I) -> test_item(Args1, I) end, pget(Key, Definitions)),

    %% Make sure it is not in the other vhost
    Definitions0 = http_get("/definitions/" ++ VHost2, ?OK),
    false = lists:any(fun(I) -> test_item(Args2, I) end, pget(Key, Definitions0)),

    %% Post the definitions back
    http_post("/definitions/" ++ VHost2, Definitions, [?NO_CONTENT, ?CREATED]),

    %% Make sure it is now in the other vhost
    Definitions1 = http_get("/definitions/" ++ VHost2, ?OK),
    true = lists:any(fun(I) -> test_item(Args2, I) end, pget(Key, Definitions1)),

    %% Delete it
    DeleteFun(URI2),
    URI3 = create(CreateMethod, Rep1(URI0, VHost2), Args2),
    DeleteFun(URI3),
    ok.

definitions_vhost_test() ->
    %% Ensures that definitions can be exported/imported from a single virtual
    %% host to another

    rabbit_runtime_parameters_test:register(),
    rabbit_runtime_parameters_test:register_policy_validator(),

    defs_vhost(queues, "/queues/<vhost>/my-queue", put,
               [{name,    <<"my-queue">>},
                {durable, true}]),
    defs_vhost(exchanges, "/exchanges/<vhost>/my-exchange", put,
               [{name, <<"my-exchange">>},
                {type, <<"direct">>}]),
    defs_vhost(bindings, "/bindings/<vhost>/e/amq.direct/e/amq.fanout", post,
               [{routing_key, <<"routing">>}, {arguments, []}]),
    defs_vhost(policies, "/policies/<vhost>/my-policy", put,
               [{vhost,      vhost},
                {name,       <<"my-policy">>},
                {pattern,    <<".*">>},
                {definition, [{testpos, [1, 2, 3]}]},
                {priority,   1}]),

    Config =
        [{queues,      []},
         {exchanges,   []},
         {policies,    []},
         {bindings,    []}],
    http_post("/definitions/othervhost", Config, ?BAD_REQUEST),

    rabbit_runtime_parameters_test:unregister_policy_validator(),
    rabbit_runtime_parameters_test:unregister(),
    ok.

definitions_password_test() ->
    % Import definitions from 3.5.x
    Config35 = [{rabbit_version, <<"3.5.4">>}, 
                {users, [[{name,          <<"myuser">>},
                          {password_hash, <<"WAbU0ZIcvjTpxM3Q3SbJhEAM2tQ=">>},
                          {tags,          <<"management">>}]
                        ]}],
    Expected35 = [{name,          <<"myuser">>},
                  {password_hash, <<"WAbU0ZIcvjTpxM3Q3SbJhEAM2tQ=">>},
                  {hashing_algorithm, <<"rabbit_password_hashing_md5">>},
                  {tags,          <<"management">>}],
    http_post("/definitions", Config35, ?NO_CONTENT),
    Definitions35 = http_get("/definitions", ?OK),

    Users35 = pget(users, Definitions35),

    io:format("Defs: ~p ~n Exp: ~p~n", [Users35, Expected35]),

    true = lists:any(fun(I) -> test_item(Expected35, I) end, Users35),

    %% Import definitions from from 3.6.0
    Config36 = [{rabbit_version, <<"3.6.0">>}, 
                {users, [[{name,          <<"myuser">>},
                          {password_hash, <<"WAbU0ZIcvjTpxM3Q3SbJhEAM2tQ=">>},
                          {tags,          <<"management">>}]
                        ]}],
    Expected36 = [{name,          <<"myuser">>},
                  {password_hash, <<"WAbU0ZIcvjTpxM3Q3SbJhEAM2tQ=">>},
                  {hashing_algorithm, <<"rabbit_password_hashing_sha256">>},
                  {tags,          <<"management">>}],
    http_post("/definitions", Config36, ?NO_CONTENT),

    Definitions36 = http_get("/definitions", ?OK),
    Users36 = pget(users, Definitions36),

    true = lists:any(fun(I) -> test_item(Expected36, I) end, Users36),

    %% No hashing_algorithm provided
    ConfigDefault = [{rabbit_version, <<"3.6.1">>}, 
                     {users, [[{name,          <<"myuser">>},
                               {password_hash, <<"WAbU0ZIcvjTpxM3Q3SbJhEAM2tQ=">>},
                               {tags,          <<"management">>}]
                             ]}],
    application:set_env(rabbit, 
                        password_hashing_module, 
                        rabbit_password_hashing_sha512),

    ExpectedDefault = [{name,          <<"myuser">>},
                       {password_hash, <<"WAbU0ZIcvjTpxM3Q3SbJhEAM2tQ=">>},
                       {hashing_algorithm, <<"rabbit_password_hashing_sha512">>},
                       {tags,          <<"management">>}],
    http_post("/definitions", ConfigDefault, ?NO_CONTENT),

    DefinitionsDefault = http_get("/definitions", ?OK),
    UsersDefault = pget(users, DefinitionsDefault),

    true = lists:any(fun(I) -> test_item(ExpectedDefault, I) end, UsersDefault),
    ok.

definitions_remove_things_test() ->
    {ok, Conn} = amqp_connection:start(#amqp_params_network{}),
    {ok, Ch} = amqp_connection:open_channel(Conn),
    amqp_channel:call(Ch, #'queue.declare'{ queue = <<"my-exclusive">>,
                                            exclusive = true }),
    http_get("/queues/%2f/my-exclusive", ?OK),
    Definitions = http_get("/definitions", ?OK),
    [] = pget(queues, Definitions),
    [] = pget(exchanges, Definitions),
    [] = pget(bindings, Definitions),
    amqp_channel:close(Ch),
    amqp_connection:close(Conn),
    ok.

definitions_server_named_queue_test() ->
    {ok, Conn} = amqp_connection:start(#amqp_params_network{}),
    {ok, Ch} = amqp_connection:open_channel(Conn),
    #'queue.declare_ok'{ queue = QName } =
        amqp_channel:call(Ch, #'queue.declare'{}),
    amqp_channel:close(Ch),
    amqp_connection:close(Conn),
    Path = "/queues/%2f/" ++ mochiweb_util:quote_plus(QName),
    http_get(Path, ?OK),
    Definitions = http_get("/definitions", ?OK),
    http_delete(Path, ?NO_CONTENT),
    http_get(Path, ?NOT_FOUND),
    http_post("/definitions", Definitions, [?CREATED, ?NO_CONTENT]),
    http_get(Path, ?OK),
    http_delete(Path, ?NO_CONTENT),
    ok.

aliveness_test() ->
    [{status, <<"ok">>}] = http_get("/aliveness-test/%2f", ?OK),
    http_get("/aliveness-test/foo", ?NOT_FOUND),
    http_delete("/queues/%2f/aliveness-test", ?NO_CONTENT),
    ok.

healthchecks_test() ->
    [{status, <<"ok">>}] = http_get("/healthchecks/node", ?OK),
    http_get("/healthchecks/node/foo", ?NOT_FOUND),
    ok.

arguments_test() ->
    XArgs = [{type, <<"headers">>},
             {arguments, [{'alternate-exchange', <<"amq.direct">>}]}],
    QArgs = [{arguments, [{'x-expires', 1800000}]}],
    BArgs = [{routing_key, <<"">>},
             {arguments, [{'x-match', <<"all">>},
                          {foo, <<"bar">>}]}],
    http_put("/exchanges/%2f/myexchange", XArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/queues/%2f/myqueue", QArgs, [?CREATED, ?NO_CONTENT]),
    http_post("/bindings/%2f/e/myexchange/q/myqueue", BArgs, [?CREATED, ?NO_CONTENT]),
    Definitions = http_get("/definitions", ?OK),
    http_delete("/exchanges/%2f/myexchange", ?NO_CONTENT),
    http_delete("/queues/%2f/myqueue", ?NO_CONTENT),
    http_post("/definitions", Definitions, ?NO_CONTENT),
    [{'alternate-exchange', <<"amq.direct">>}] =
        pget(arguments, http_get("/exchanges/%2f/myexchange", ?OK)),
    [{'x-expires', 1800000}] =
        pget(arguments, http_get("/queues/%2f/myqueue", ?OK)),
    true = lists:sort([{'x-match', <<"all">>}, {foo, <<"bar">>}]) =:=
	lists:sort(pget(arguments,
			http_get("/bindings/%2f/e/myexchange/q/myqueue/" ++
				     "~nXOkVwqZzUOdS9_HcBWheg", ?OK))),
    http_delete("/exchanges/%2f/myexchange", ?NO_CONTENT),
    http_delete("/queues/%2f/myqueue", ?NO_CONTENT),
    ok.

arguments_table_test() ->
    Args = [{'upstreams', [<<"amqp://localhost/%2f/upstream1">>,
                           <<"amqp://localhost/%2f/upstream2">>]}],
    XArgs = [{type, <<"headers">>},
             {arguments, Args}],
    http_put("/exchanges/%2f/myexchange", XArgs, [?CREATED, ?NO_CONTENT]),
    Definitions = http_get("/definitions", ?OK),
    http_delete("/exchanges/%2f/myexchange", ?NO_CONTENT),
    http_post("/definitions", Definitions, ?NO_CONTENT),
    Args = pget(arguments, http_get("/exchanges/%2f/myexchange", ?OK)),
    http_delete("/exchanges/%2f/myexchange", ?NO_CONTENT),
    ok.

queue_purge_test() ->
    QArgs = [],
    http_put("/queues/%2f/myqueue", QArgs, [?CREATED, ?NO_CONTENT]),
    {ok, Conn} = amqp_connection:start(#amqp_params_network{}),
    {ok, Ch} = amqp_connection:open_channel(Conn),
    Publish = fun() ->
                      amqp_channel:call(
                        Ch, #'basic.publish'{exchange = <<"">>,
                                             routing_key = <<"myqueue">>},
                        #amqp_msg{payload = <<"message">>})
              end,
    Publish(),
    Publish(),
    amqp_channel:call(
      Ch, #'queue.declare'{queue = <<"exclusive">>, exclusive = true}),
    {#'basic.get_ok'{}, _} =
        amqp_channel:call(Ch, #'basic.get'{queue = <<"myqueue">>}),
    http_delete("/queues/%2f/myqueue/contents", ?NO_CONTENT),
    http_delete("/queues/%2f/badqueue/contents", ?NOT_FOUND),
    http_delete("/queues/%2f/exclusive/contents", ?BAD_REQUEST),
    http_delete("/queues/%2f/exclusive", ?BAD_REQUEST),
    #'basic.get_empty'{} =
        amqp_channel:call(Ch, #'basic.get'{queue = <<"myqueue">>}),
    amqp_channel:close(Ch),
    amqp_connection:close(Conn),
    http_delete("/queues/%2f/myqueue", ?NO_CONTENT),
    ok.

queue_actions_test() ->
    http_put("/queues/%2f/q", [], [?CREATED, ?NO_CONTENT]),
    http_post("/queues/%2f/q/actions", [{action, sync}], ?NO_CONTENT),
    http_post("/queues/%2f/q/actions", [{action, cancel_sync}], ?NO_CONTENT),
    http_post("/queues/%2f/q/actions", [{action, change_colour}], ?BAD_REQUEST),
    http_delete("/queues/%2f/q", ?NO_CONTENT),
    ok.

exclusive_consumer_test() ->
    {ok, Conn} = amqp_connection:start(#amqp_params_network{}),
    {ok, Ch} = amqp_connection:open_channel(Conn),
    #'queue.declare_ok'{ queue = QName } =
        amqp_channel:call(Ch, #'queue.declare'{exclusive = true}),
    amqp_channel:subscribe(Ch, #'basic.consume'{queue     = QName,
                                                exclusive = true}, self()),
    timer:sleep(1000), %% Sadly we need to sleep to let the stats update
    http_get("/queues/%2f/"), %% Just check we don't blow up
    amqp_channel:close(Ch),
    amqp_connection:close(Conn),
    ok.


exclusive_queue_test() ->
    {ok, Conn} = amqp_connection:start(#amqp_params_network{}),
    {ok, Ch} = amqp_connection:open_channel(Conn),
    #'queue.declare_ok'{ queue = QName } =
	amqp_channel:call(Ch, #'queue.declare'{exclusive = true}),
    timer:sleep(1000), %% Sadly we need to sleep to let the stats update
    Path = "/queues/%2f/" ++ mochiweb_util:quote_plus(QName),
    Queue = http_get(Path),
    assert_item([{name,         QName},
		 {vhost,       <<"/">>},
		 {durable,     false},
		 {auto_delete, false},
		 {exclusive,   true},
		 {arguments,   []}], Queue),
    amqp_channel:close(Ch),
    amqp_connection:close(Conn),
    ok.

connections_channels_pagination_test() ->
    {ok, Conn} = amqp_connection:start(#amqp_params_network{}),
    {ok, Ch} = amqp_connection:open_channel(Conn),
    {ok, Conn1} = amqp_connection:start(#amqp_params_network{}),
    {ok, Ch1} = amqp_connection:open_channel(Conn1),
    {ok, Conn2} = amqp_connection:start(#amqp_params_network{}),
    {ok, Ch2} = amqp_connection:open_channel(Conn2),

    timer:sleep(1000), %% Sadly we need to sleep to let the stats update
    PageOfTwo = http_get("/connections?page=1&page_size=2", ?OK),
    ?assertEqual(3, proplists:get_value(total_count, PageOfTwo)),
    ?assertEqual(3, proplists:get_value(filtered_count, PageOfTwo)),
    ?assertEqual(2, proplists:get_value(item_count, PageOfTwo)),
    ?assertEqual(1, proplists:get_value(page, PageOfTwo)),
    ?assertEqual(2, proplists:get_value(page_size, PageOfTwo)),
    ?assertEqual(2, proplists:get_value(page_count, PageOfTwo)),


    TwoOfTwo = http_get("/channels?page=2&page_size=2", ?OK),
    ?assertEqual(3, proplists:get_value(total_count, TwoOfTwo)),
    ?assertEqual(3, proplists:get_value(filtered_count, TwoOfTwo)),
    ?assertEqual(1, proplists:get_value(item_count, TwoOfTwo)),
    ?assertEqual(2, proplists:get_value(page, TwoOfTwo)),
    ?assertEqual(2, proplists:get_value(page_size, TwoOfTwo)),
    ?assertEqual(2, proplists:get_value(page_count, TwoOfTwo)),

    amqp_channel:close(Ch),
    amqp_connection:close(Conn),
    amqp_channel:close(Ch1),
    amqp_connection:close(Conn1),
    amqp_channel:close(Ch2),
    amqp_connection:close(Conn2),
    ok.

exchanges_pagination_test() ->
    QArgs = [],
    PermArgs = [{configure, <<".*">>}, {write, <<".*">>}, {read, <<".*">>}],
    http_put("/vhosts/vh1", none, [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/vh1/guest", PermArgs, [?CREATED, ?NO_CONTENT]),
    http_get("/exchanges/vh1?page=1&page_size=2", ?OK),
    http_put("/exchanges/%2f/test0", QArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/exchanges/vh1/test1", QArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/exchanges/%2f/test2_reg", QArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/exchanges/vh1/reg_test3", QArgs, [?CREATED, ?NO_CONTENT]),
    PageOfTwo = http_get("/exchanges?page=1&page_size=2", ?OK),
    ?assertEqual(19, proplists:get_value(total_count, PageOfTwo)),
    ?assertEqual(19, proplists:get_value(filtered_count, PageOfTwo)),
    ?assertEqual(2, proplists:get_value(item_count, PageOfTwo)),
    ?assertEqual(1, proplists:get_value(page, PageOfTwo)),
    ?assertEqual(2, proplists:get_value(page_size, PageOfTwo)),
    ?assertEqual(10, proplists:get_value(page_count, PageOfTwo)),
    assert_list([[{name, <<"">>}, {vhost, <<"/">>}],
		 [{name, <<"amq.direct">>}, {vhost, <<"/">>}]
		], proplists:get_value(items, PageOfTwo)),

    ByName = http_get("/exchanges?page=1&page_size=2&name=reg", ?OK),
    ?assertEqual(19, proplists:get_value(total_count, ByName)),
    ?assertEqual(2, proplists:get_value(filtered_count, ByName)),
    ?assertEqual(2, proplists:get_value(item_count, ByName)),
    ?assertEqual(1, proplists:get_value(page, ByName)),
    ?assertEqual(2, proplists:get_value(page_size, ByName)),
    ?assertEqual(1, proplists:get_value(page_count, ByName)),
    assert_list([[{name, <<"test2_reg">>}, {vhost, <<"/">>}],
		 [{name, <<"reg_test3">>}, {vhost, <<"vh1">>}]
		], proplists:get_value(items, ByName)),


    RegExByName = http_get(
		    "/exchanges?page=1&page_size=2&name=^(?=^reg)&use_regex=true",
		    ?OK),
    ?assertEqual(19, proplists:get_value(total_count, RegExByName)),
    ?assertEqual(1, proplists:get_value(filtered_count, RegExByName)),
    ?assertEqual(1, proplists:get_value(item_count, RegExByName)),
    ?assertEqual(1, proplists:get_value(page, RegExByName)),
    ?assertEqual(2, proplists:get_value(page_size, RegExByName)),
    ?assertEqual(1, proplists:get_value(page_count, RegExByName)),
    assert_list([[{name, <<"reg_test3">>}, {vhost, <<"vh1">>}]
		], proplists:get_value(items, RegExByName)),


    http_get("/exchanges?page=1000", ?BAD_REQUEST),
    http_get("/exchanges?page=-1", ?BAD_REQUEST),
    http_get("/exchanges?page=not_an_integer_value", ?BAD_REQUEST),
    http_get("/exchanges?page=1&page_size=not_an_intger_value", ?BAD_REQUEST),
    http_get("/exchanges?page=1&page_size=501", ?BAD_REQUEST), %% max 500 allowed
    http_get("/exchanges?page=-1&page_size=-2", ?BAD_REQUEST),
    http_delete("/exchanges/%2f/test0", ?NO_CONTENT),
    http_delete("/exchanges/vh1/test1", ?NO_CONTENT),
    http_delete("/exchanges/%2f/test2_reg", ?NO_CONTENT),
    http_delete("/exchanges/vh1/reg_test3", ?NO_CONTENT),
    http_delete("/vhosts/vh1", ?NO_CONTENT),
    ok.

exchanges_pagination_permissions_test() ->
    http_put("/users/admin",   [{password, <<"admin">>},
				{tags, <<"administrator">>}], [?CREATED, ?NO_CONTENT]),
    Perms = [{configure, <<".*">>},
	     {write,     <<".*">>},
	     {read,      <<".*">>}],
    http_put("/vhosts/vh1", none, [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/vh1/admin",   Perms, [?CREATED, ?NO_CONTENT]),
    QArgs = [],
    http_put("/exchanges/%2f/test0", QArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/exchanges/vh1/test1", QArgs, "admin","admin", [?CREATED, ?NO_CONTENT]),
    FirstPage = http_get("/exchanges?page=1&name=test1","admin","admin", ?OK),
    ?assertEqual(8, proplists:get_value(total_count, FirstPage)),
    ?assertEqual(1, proplists:get_value(item_count, FirstPage)),
    ?assertEqual(1, proplists:get_value(page, FirstPage)),
    ?assertEqual(100, proplists:get_value(page_size, FirstPage)),
    ?assertEqual(1, proplists:get_value(page_count, FirstPage)),
    assert_list([[{name, <<"test1">>}, {vhost, <<"vh1">>}]
		], proplists:get_value(items, FirstPage)),
    http_delete("/exchanges/%2f/test0", ?NO_CONTENT),
    http_delete("/exchanges/vh1/test1","admin","admin", ?NO_CONTENT),
    http_delete("/vhosts/vh1", ?NO_CONTENT),
    http_delete("/users/admin", ?NO_CONTENT),
    ok.



queue_pagination_test() ->
    QArgs = [],
    PermArgs = [{configure, <<".*">>}, {write, <<".*">>}, {read, <<".*">>}],
    http_put("/vhosts/vh1", none, [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/vh1/guest", PermArgs, [?CREATED, ?NO_CONTENT]),

    http_get("/queues/vh1?page=1&page_size=2", ?OK),

    http_put("/queues/%2f/test0", QArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/queues/vh1/test1", QArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/queues/%2f/test2_reg", QArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/queues/vh1/reg_test3", QArgs, [?CREATED, ?NO_CONTENT]),
    PageOfTwo = http_get("/queues?page=1&page_size=2", ?OK),
    ?assertEqual(4, proplists:get_value(total_count, PageOfTwo)),
    ?assertEqual(4, proplists:get_value(filtered_count, PageOfTwo)),
    ?assertEqual(2, proplists:get_value(item_count, PageOfTwo)),
    ?assertEqual(1, proplists:get_value(page, PageOfTwo)),
    ?assertEqual(2, proplists:get_value(page_size, PageOfTwo)),
    ?assertEqual(2, proplists:get_value(page_count, PageOfTwo)),
    assert_list([[{name, <<"test0">>}, {vhost, <<"/">>}],
		 [{name, <<"test2_reg">>}, {vhost, <<"/">>}]
		], proplists:get_value(items, PageOfTwo)),

    SortedByName = http_get("/queues?sort=name&page=1&page_size=2", ?OK),
    ?assertEqual(4, proplists:get_value(total_count, SortedByName)),
    ?assertEqual(4, proplists:get_value(filtered_count, SortedByName)),
    ?assertEqual(2, proplists:get_value(item_count, SortedByName)),
    ?assertEqual(1, proplists:get_value(page, SortedByName)),
    ?assertEqual(2, proplists:get_value(page_size, SortedByName)),
    ?assertEqual(2, proplists:get_value(page_count, SortedByName)),
    assert_list([[{name, <<"reg_test3">>}, {vhost, <<"vh1">>}],
		 [{name, <<"test0">>}, {vhost, <<"/">>}]
		], proplists:get_value(items, SortedByName)),


    FirstPage = http_get("/queues?page=1", ?OK),
    ?assertEqual(4, proplists:get_value(total_count, FirstPage)),
    ?assertEqual(4, proplists:get_value(filtered_count, FirstPage)),
    ?assertEqual(4, proplists:get_value(item_count, FirstPage)),
    ?assertEqual(1, proplists:get_value(page, FirstPage)),
    ?assertEqual(100, proplists:get_value(page_size, FirstPage)),
    ?assertEqual(1, proplists:get_value(page_count, FirstPage)),
    assert_list([[{name, <<"test0">>}, {vhost, <<"/">>}],
		 [{name, <<"test1">>}, {vhost, <<"vh1">>}],
		 [{name, <<"test2_reg">>}, {vhost, <<"/">>}],
		 [{name, <<"reg_test3">>}, {vhost, <<"vh1">>}]
		], proplists:get_value(items, FirstPage)),


    ReverseSortedByName = http_get(
		    "/queues?page=2&page_size=2&sort=name&sort_reverse=true", 
		    ?OK),
    ?assertEqual(4, proplists:get_value(total_count, ReverseSortedByName)),
    ?assertEqual(4, proplists:get_value(filtered_count, ReverseSortedByName)),
    ?assertEqual(2, proplists:get_value(item_count, ReverseSortedByName)),
    ?assertEqual(2, proplists:get_value(page, ReverseSortedByName)),
    ?assertEqual(2, proplists:get_value(page_size, ReverseSortedByName)),
    ?assertEqual(2, proplists:get_value(page_count, ReverseSortedByName)),
    assert_list([[{name, <<"test0">>}, {vhost, <<"/">>}],
		 [{name, <<"reg_test3">>}, {vhost, <<"vh1">>}]
		], proplists:get_value(items, ReverseSortedByName)),

						
    ByName = http_get("/queues?page=1&page_size=2&name=reg", ?OK),
    ?assertEqual(4, proplists:get_value(total_count, ByName)),
    ?assertEqual(2, proplists:get_value(filtered_count, ByName)),
    ?assertEqual(2, proplists:get_value(item_count, ByName)),
    ?assertEqual(1, proplists:get_value(page, ByName)),
    ?assertEqual(2, proplists:get_value(page_size, ByName)),
    ?assertEqual(1, proplists:get_value(page_count, ByName)),
    assert_list([[{name, <<"test2_reg">>}, {vhost, <<"/">>}],
		 [{name, <<"reg_test3">>}, {vhost, <<"vh1">>}]
		], proplists:get_value(items, ByName)),

    RegExByName = http_get(
		    "/queues?page=1&page_size=2&name=^(?=^reg)&use_regex=true",
		    ?OK),
    ?assertEqual(4, proplists:get_value(total_count, RegExByName)),
    ?assertEqual(1, proplists:get_value(filtered_count, RegExByName)),
    ?assertEqual(1, proplists:get_value(item_count, RegExByName)),
    ?assertEqual(1, proplists:get_value(page, RegExByName)),
    ?assertEqual(2, proplists:get_value(page_size, RegExByName)),
    ?assertEqual(1, proplists:get_value(page_count, RegExByName)),
    assert_list([[{name, <<"reg_test3">>}, {vhost, <<"vh1">>}]
		], proplists:get_value(items, RegExByName)),


    http_get("/queues?page=1000", ?BAD_REQUEST),
    http_get("/queues?page=-1", ?BAD_REQUEST),
    http_get("/queues?page=not_an_integer_value", ?BAD_REQUEST),
    http_get("/queues?page=1&page_size=not_an_intger_value", ?BAD_REQUEST),
    http_get("/queues?page=1&page_size=501", ?BAD_REQUEST), %% max 500 allowed
    http_get("/queues?page=-1&page_size=-2", ?BAD_REQUEST),
    http_delete("/queues/%2f/test0", ?NO_CONTENT),
    http_delete("/queues/vh1/test1", ?NO_CONTENT),
    http_delete("/queues/%2f/test2_reg", ?NO_CONTENT),
    http_delete("/queues/vh1/reg_test3", ?NO_CONTENT),
    http_delete("/vhosts/vh1", ?NO_CONTENT),
    ok.

queues_pagination_permissions_test() ->
    http_put("/users/admin",   [{password, <<"admin">>},
				{tags, <<"administrator">>}], [?CREATED, ?NO_CONTENT]),
    Perms = [{configure, <<".*">>},
	     {write,     <<".*">>},
	     {read,      <<".*">>}],
    http_put("/vhosts/vh1", none, [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/vh1/admin",   Perms, [?CREATED, ?NO_CONTENT]),
    QArgs = [],
    http_put("/queues/%2f/test0", QArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/queues/vh1/test1", QArgs, "admin","admin", [?CREATED, ?NO_CONTENT]),
    FirstPage = http_get("/queues?page=1","admin","admin", ?OK),
    ?assertEqual(1, proplists:get_value(total_count, FirstPage)),
    ?assertEqual(1, proplists:get_value(item_count, FirstPage)),
    ?assertEqual(1, proplists:get_value(page, FirstPage)),
    ?assertEqual(100, proplists:get_value(page_size, FirstPage)),
    ?assertEqual(1, proplists:get_value(page_count, FirstPage)),
    assert_list([[{name, <<"test1">>}, {vhost, <<"vh1">>}]
		], proplists:get_value(items, FirstPage)),
    http_delete("/queues/%2f/test0", ?NO_CONTENT),
    http_delete("/queues/vh1/test1","admin","admin", ?NO_CONTENT),
    http_delete("/vhosts/vh1", ?NO_CONTENT),
    http_delete("/users/admin", ?NO_CONTENT),
    ok.

samples_range_test() ->
    {ok, Conn} = amqp_connection:start(#amqp_params_network{}),
    {ok, Ch} = amqp_connection:open_channel(Conn),

    %% Channels.

    [ConnInfo] = http_get("/channels?lengths_age=60&lengths_incr=1", ?OK),
    http_get("/channels?lengths_age=6000&lengths_incr=1", ?BAD_REQUEST),

    {_, ConnDetails} = lists:keyfind(connection_details, 1, ConnInfo),
    {_, ConnName0} = lists:keyfind(name, 1, ConnDetails),
    ConnName = http_uri:encode(binary_to_list(ConnName0)),
    ChanName = ConnName ++ http_uri:encode(" (1)"),

    http_get("/channels/" ++ ChanName ++ "?lengths_age=60&lengths_incr=1", ?OK),
    http_get("/channels/" ++ ChanName ++ "?lengths_age=6000&lengths_incr=1", ?BAD_REQUEST),

    http_get("/vhosts/%2f/channels?lengths_age=60&lengths_incr=1", ?OK),
    http_get("/vhosts/%2f/channels?lengths_age=6000&lengths_incr=1", ?BAD_REQUEST),

    %% Connections.

    http_get("/connections?lengths_age=60&lengths_incr=1", ?OK),
    http_get("/connections?lengths_age=6000&lengths_incr=1", ?BAD_REQUEST),

    http_get("/connections/" ++ ConnName ++ "?lengths_age=60&lengths_incr=1", ?OK),
    http_get("/connections/" ++ ConnName ++ "?lengths_age=6000&lengths_incr=1", ?BAD_REQUEST),

    http_get("/connections/" ++ ConnName ++ "/channels?lengths_age=60&lengths_incr=1", ?OK),
    http_get("/connections/" ++ ConnName ++ "/channels?lengths_age=6000&lengths_incr=1", ?BAD_REQUEST),

    http_get("/vhosts/%2f/connections?lengths_age=60&lengths_incr=1", ?OK),
    http_get("/vhosts/%2f/connections?lengths_age=6000&lengths_incr=1", ?BAD_REQUEST),

    amqp_channel:close(Ch),
    amqp_connection:close(Conn),

    %% Exchanges.

    http_get("/exchanges?lengths_age=60&lengths_incr=1", ?OK),
    http_get("/exchanges?lengths_age=6000&lengths_incr=1", ?BAD_REQUEST),

    http_get("/exchanges/%2f/amq.direct?lengths_age=60&lengths_incr=1", ?OK),
    http_get("/exchanges/%2f/amq.direct?lengths_age=6000&lengths_incr=1", ?BAD_REQUEST),

    %% Nodes.

    http_get("/nodes?lengths_age=60&lengths_incr=1", ?OK),
    http_get("/nodes?lengths_age=6000&lengths_incr=1", ?BAD_REQUEST),

    %% Overview.

    http_get("/overview?lengths_age=60&lengths_incr=1", ?OK),
    http_get("/overview?lengths_age=6000&lengths_incr=1", ?BAD_REQUEST),

    %% Queues.

    http_put("/queues/%2f/test0", [], [?CREATED, ?NO_CONTENT]),

    http_get("/queues/%2f?lengths_age=60&lengths_incr=1", ?OK),
    http_get("/queues/%2f?lengths_age=6000&lengths_incr=1", ?BAD_REQUEST),
    http_get("/queues/%2f/test0?lengths_age=60&lengths_incr=1", ?OK),
    http_get("/queues/%2f/test0?lengths_age=6000&lengths_incr=1", ?BAD_REQUEST),

    http_delete("/queues/%2f/test0", ?NO_CONTENT),

    %% Vhosts.

    http_put("/vhosts/vh1", none, [?CREATED, ?NO_CONTENT]),

    http_get("/vhosts?lengths_age=60&lengths_incr=1", ?OK),
    http_get("/vhosts?lengths_age=6000&lengths_incr=1", ?BAD_REQUEST),
    http_get("/vhosts/vh1?lengths_age=60&lengths_incr=1", ?OK),
    http_get("/vhosts/vh1?lengths_age=6000&lengths_incr=1", ?BAD_REQUEST),

    http_delete("/vhosts/vh1", ?NO_CONTENT),

    ok.

sorting_test() ->
    QArgs = [],
    PermArgs = [{configure, <<".*">>}, {write, <<".*">>}, {read, <<".*">>}],
    http_put("/vhosts/vh1", none, [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/vh1/guest", PermArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/queues/%2f/test0", QArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/queues/vh1/test1", QArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/queues/%2f/test2", QArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/queues/vh1/test3", QArgs, [?CREATED, ?NO_CONTENT]),
    assert_list([[{name, <<"test0">>}],
                 [{name, <<"test2">>}],
                 [{name, <<"test1">>}],
                 [{name, <<"test3">>}]], http_get("/queues", ?OK)),
    assert_list([[{name, <<"test0">>}],
                 [{name, <<"test1">>}],
                 [{name, <<"test2">>}],
                 [{name, <<"test3">>}]], http_get("/queues?sort=name", ?OK)),
    assert_list([[{name, <<"test0">>}],
                 [{name, <<"test2">>}],
                 [{name, <<"test1">>}],
                 [{name, <<"test3">>}]], http_get("/queues?sort=vhost", ?OK)),
    assert_list([[{name, <<"test3">>}],
                 [{name, <<"test1">>}],
                 [{name, <<"test2">>}],
                 [{name, <<"test0">>}]], http_get("/queues?sort_reverse=true", ?OK)),
    assert_list([[{name, <<"test3">>}],
                 [{name, <<"test2">>}],
                 [{name, <<"test1">>}],
                 [{name, <<"test0">>}]], http_get("/queues?sort=name&sort_reverse=true", ?OK)),
    assert_list([[{name, <<"test3">>}],
                 [{name, <<"test1">>}],
                 [{name, <<"test2">>}],
                 [{name, <<"test0">>}]], http_get("/queues?sort=vhost&sort_reverse=true", ?OK)),
    %% Rather poor but at least test it doesn't blow up with dots
    http_get("/queues?sort=owner_pid_details.name", ?OK),
    http_delete("/queues/%2f/test0", ?NO_CONTENT),
    http_delete("/queues/vh1/test1", ?NO_CONTENT),
    http_delete("/queues/%2f/test2", ?NO_CONTENT),
    http_delete("/queues/vh1/test3", ?NO_CONTENT),
    http_delete("/vhosts/vh1", ?NO_CONTENT),
    ok.

format_output_test() ->
    QArgs = [],
    PermArgs = [{configure, <<".*">>}, {write, <<".*">>}, {read, <<".*">>}],
    http_put("/vhosts/vh1", none, [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/vh1/guest", PermArgs, [?CREATED, ?NO_CONTENT]),
    http_put("/queues/%2f/test0", QArgs, [?CREATED, ?NO_CONTENT]),
    assert_list([[{name, <<"test0">>},
		  {consumer_utilisation, null},
		  {exclusive_consumer_tag, null},
		  {recoverable_slaves, null}]], http_get("/queues", ?OK)),
    http_delete("/queues/%2f/test0", ?NO_CONTENT),
    http_delete("/vhosts/vh1", ?NO_CONTENT),
    ok.

columns_test() ->
    http_put("/queues/%2f/test", [{arguments, [{<<"foo">>, <<"bar">>}]}],
             [?CREATED, ?NO_CONTENT]),
    [List] = http_get("/queues?columns=arguments.foo,name", ?OK),
    [{arguments, [{foo, <<"bar">>}]}, {name, <<"test">>}] = lists:sort(List),
    [{arguments, [{foo, <<"bar">>}]}, {name, <<"test">>}] =
        lists:sort(http_get("/queues/%2f/test?columns=arguments.foo,name", ?OK)),
    http_delete("/queues/%2f/test", ?NO_CONTENT),
    ok.

get_test() ->
    %% Real world example...
    Headers = [{<<"x-forwarding">>, array,
                [{table,
                  [{<<"uri">>, longstr,
                    <<"amqp://localhost/%2f/upstream">>}]}]}],
    http_put("/queues/%2f/myqueue", [], [?CREATED, ?NO_CONTENT]),
    {ok, Conn} = amqp_connection:start(#amqp_params_network{}),
    {ok, Ch} = amqp_connection:open_channel(Conn),
    Publish = fun (Payload) ->
                      amqp_channel:cast(
                        Ch, #'basic.publish'{exchange = <<>>,
                                             routing_key = <<"myqueue">>},
                        #amqp_msg{props = #'P_basic'{headers = Headers},
                                  payload = Payload})
              end,
    Publish(<<"1aaa">>),
    Publish(<<"2aaa">>),
    Publish(<<"3aaa">>),
    amqp_connection:close(Conn),
    [Msg] = http_post("/queues/%2f/myqueue/get", [{requeue,  false},
                                                  {count,    1},
                                                  {encoding, auto},
                                                  {truncate, 1}], ?OK),
    false         = pget(redelivered, Msg),
    <<>>          = pget(exchange,    Msg),
    <<"myqueue">> = pget(routing_key, Msg),
    <<"1">>       = pget(payload,     Msg),
    [{'x-forwarding',
      [[{uri,<<"amqp://localhost/%2f/upstream">>}]]}] =
        pget(headers, pget(properties, Msg)),

    [M2, M3] = http_post("/queues/%2f/myqueue/get", [{requeue,  true},
                                                     {count,    5},
                                                     {encoding, auto}], ?OK),
    <<"2aaa">> = pget(payload, M2),
    <<"3aaa">> = pget(payload, M3),
    2 = length(http_post("/queues/%2f/myqueue/get", [{requeue,  false},
                                                     {count,    5},
                                                     {encoding, auto}], ?OK)),
    [] = http_post("/queues/%2f/myqueue/get", [{requeue,  false},
                                               {count,    5},
                                               {encoding, auto}], ?OK),
    http_delete("/queues/%2f/myqueue", ?NO_CONTENT),
    ok.

get_fail_test() ->
    http_put("/users/myuser", [{password, <<"password">>},
                               {tags, <<"management">>}], ?NO_CONTENT),
    http_put("/queues/%2f/myqueue", [], [?CREATED, ?NO_CONTENT]),
    http_post("/queues/%2f/myqueue/get",
              [{requeue,  false},
               {count,    1},
               {encoding, auto}], "myuser", "password", ?NOT_AUTHORISED),
    http_delete("/queues/%2f/myqueue", ?NO_CONTENT),
    http_delete("/users/myuser", ?NO_CONTENT),
    ok.

publish_test() ->
    Headers = [{'x-forwarding', [[{uri,<<"amqp://localhost/%2f/upstream">>}]]}],
    Msg = msg(<<"myqueue">>, Headers, <<"Hello world">>),
    http_put("/queues/%2f/myqueue", [], [?CREATED, ?NO_CONTENT]),
    ?assertEqual([{routed, true}],
                 http_post("/exchanges/%2f/amq.default/publish", Msg, ?OK)),
    [Msg2] = http_post("/queues/%2f/myqueue/get", [{requeue,  false},
                                                   {count,    1},
                                                   {encoding, auto}], ?OK),
    assert_item(Msg, Msg2),
    http_post("/exchanges/%2f/amq.default/publish", Msg2, ?OK),
    [Msg3] = http_post("/queues/%2f/myqueue/get", [{requeue,  false},
                                                   {count,    1},
                                                   {encoding, auto}], ?OK),
    assert_item(Msg, Msg3),
    http_delete("/queues/%2f/myqueue", ?NO_CONTENT),
    ok.

publish_accept_json_test() ->
    Headers = [{'x-forwarding', [[{uri, <<"amqp://localhost/%2f/upstream">>}]]}],
    Msg = msg(<<"myqueue">>, Headers, <<"Hello world">>),
    http_put("/queues/%2f/myqueue", [], [?CREATED, ?NO_CONTENT]),
    ?assertEqual([{routed, true}],
		 http_post_accept_json("/exchanges/%2f/amq.default/publish", 
				       Msg, ?OK)),

    [Msg2] = http_post_accept_json("/queues/%2f/myqueue/get", 
				   [{requeue, false},
				    {count, 1},
				    {encoding, auto}], ?OK),
    assert_item(Msg, Msg2),
    http_post_accept_json("/exchanges/%2f/amq.default/publish", Msg2, ?OK),
    [Msg3] = http_post_accept_json("/queues/%2f/myqueue/get", 
				   [{requeue, false},
				    {count, 1},
				    {encoding, auto}], ?OK),
    assert_item(Msg, Msg3),
    http_delete("/queues/%2f/myqueue", ?NO_CONTENT),
    ok.

publish_fail_test() ->
    Msg = msg(<<"myqueue">>, [], <<"Hello world">>),
    http_put("/queues/%2f/myqueue", [], [?CREATED, ?NO_CONTENT]),
    http_put("/users/myuser", [{password, <<"password">>},
                               {tags, <<"management">>}], [?CREATED, ?NO_CONTENT]),
    http_post("/exchanges/%2f/amq.default/publish", Msg, "myuser", "password",
              ?NOT_AUTHORISED),
    Msg2 = [{exchange,         <<"">>},
            {routing_key,      <<"myqueue">>},
            {properties,       [{user_id, <<"foo">>}]},
            {payload,          <<"Hello world">>},
            {payload_encoding, <<"string">>}],
    http_post("/exchanges/%2f/amq.default/publish", Msg2, ?BAD_REQUEST),
    Msg3 = [{exchange,         <<"">>},
            {routing_key,      <<"myqueue">>},
            {properties,       []},
            {payload,          [<<"not a string">>]},
            {payload_encoding, <<"string">>}],
    http_post("/exchanges/%2f/amq.default/publish", Msg3, ?BAD_REQUEST),
    MsgTemplate = [{exchange,         <<"">>},
                   {routing_key,      <<"myqueue">>},
                   {payload,          <<"Hello world">>},
                   {payload_encoding, <<"string">>}],
    [http_post("/exchanges/%2f/amq.default/publish",
               [{properties, [BadProp]} | MsgTemplate], ?BAD_REQUEST)
     || BadProp <- [{priority,   <<"really high">>},
                    {timestamp,  <<"recently">>},
                    {expiration, 1234}]],
    http_delete("/queues/%2f/myqueue", ?NO_CONTENT),
    http_delete("/users/myuser", ?NO_CONTENT),
    ok.

publish_base64_test() ->
    Msg     = msg(<<"myqueue">>, [], <<"YWJjZA==">>, <<"base64">>),
    BadMsg1 = msg(<<"myqueue">>, [], <<"flibble">>,  <<"base64">>),
    BadMsg2 = msg(<<"myqueue">>, [], <<"YWJjZA==">>, <<"base99">>),
    http_put("/queues/%2f/myqueue", [], [?CREATED, ?NO_CONTENT]),
    http_post("/exchanges/%2f/amq.default/publish", Msg, ?OK),
    http_post("/exchanges/%2f/amq.default/publish", BadMsg1, ?BAD_REQUEST),
    http_post("/exchanges/%2f/amq.default/publish", BadMsg2, ?BAD_REQUEST),
    [Msg2] = http_post("/queues/%2f/myqueue/get", [{requeue,  false},
                                                   {count,    1},
                                                   {encoding, auto}], ?OK),
    ?assertEqual(<<"abcd">>, pget(payload, Msg2)),
    http_delete("/queues/%2f/myqueue", ?NO_CONTENT),
    ok.

publish_unrouted_test() ->
    Msg = msg(<<"hmmm">>, [], <<"Hello world">>),
    ?assertEqual([{routed, false}],
                 http_post("/exchanges/%2f/amq.default/publish", Msg, ?OK)).

if_empty_unused_test() ->
    http_put("/exchanges/%2f/test", [], [?CREATED, ?NO_CONTENT]),
    http_put("/queues/%2f/test", [], [?CREATED, ?NO_CONTENT]),
    http_post("/bindings/%2f/e/test/q/test", [], [?CREATED, ?NO_CONTENT]),
    http_post("/exchanges/%2f/amq.default/publish",
              msg(<<"test">>, [], <<"Hello world">>), ?OK),
    http_delete("/queues/%2f/test?if-empty=true", ?BAD_REQUEST),
    http_delete("/exchanges/%2f/test?if-unused=true", ?BAD_REQUEST),
    http_delete("/queues/%2f/test/contents", ?NO_CONTENT),

    {Conn, _ConnPath, _ChPath, _ConnChPath} = get_conn("guest", "guest"),
    {ok, Ch} = amqp_connection:open_channel(Conn),
    amqp_channel:subscribe(Ch, #'basic.consume'{queue = <<"test">> }, self()),
    http_delete("/queues/%2f/test?if-unused=true", ?BAD_REQUEST),
    amqp_connection:close(Conn),

    http_delete("/queues/%2f/test?if-empty=true", ?NO_CONTENT),
    http_delete("/exchanges/%2f/test?if-unused=true", ?NO_CONTENT),
    passed.

parameters_test() ->
    rabbit_runtime_parameters_test:register(),

    http_put("/parameters/test/%2f/good", [{value, <<"ignore">>}], [?CREATED, ?NO_CONTENT]),
    http_put("/parameters/test/%2f/maybe", [{value, <<"good">>}], [?CREATED, ?NO_CONTENT]),
    http_put("/parameters/test/%2f/maybe", [{value, <<"bad">>}], ?BAD_REQUEST),
    http_put("/parameters/test/%2f/bad", [{value, <<"good">>}], ?BAD_REQUEST),
    http_put("/parameters/test/um/good", [{value, <<"ignore">>}], ?NOT_FOUND),

    Good = [{vhost,     <<"/">>},
            {component, <<"test">>},
            {name,      <<"good">>},
            {value,     <<"ignore">>}],
    Maybe = [{vhost,     <<"/">>},
             {component, <<"test">>},
             {name,      <<"maybe">>},
             {value,     <<"good">>}],
    List = [Good, Maybe],

    assert_list(List, http_get("/parameters")),
    assert_list(List, http_get("/parameters/test")),
    assert_list(List, http_get("/parameters/test/%2f")),
    assert_list([],   http_get("/parameters/oops")),
    http_get("/parameters/test/oops", ?NOT_FOUND),

    assert_item(Good,  http_get("/parameters/test/%2f/good", ?OK)),
    assert_item(Maybe, http_get("/parameters/test/%2f/maybe", ?OK)),

    http_delete("/parameters/test/%2f/good", ?NO_CONTENT),
    http_delete("/parameters/test/%2f/maybe", ?NO_CONTENT),
    http_delete("/parameters/test/%2f/bad", ?NOT_FOUND),

    0 = length(http_get("/parameters")),
    0 = length(http_get("/parameters/test")),
    0 = length(http_get("/parameters/test/%2f")),
    rabbit_runtime_parameters_test:unregister(),
    ok.

policy_test() ->
    rabbit_runtime_parameters_test:register_policy_validator(),
    PolicyPos  = [{vhost,      <<"/">>},
                  {name,       <<"policy_pos">>},
                  {pattern,    <<".*">>},
                  {definition, [{testpos,[1,2,3]}]},
                  {priority,   10}],
    PolicyEven = [{vhost,      <<"/">>},
                  {name,       <<"policy_even">>},
                  {pattern,    <<".*">>},
                  {definition, [{testeven,[1,2,3,4]}]},
                  {priority,   10}],
    http_put(
      "/policies/%2f/policy_pos",
      lists:keydelete(key, 1, PolicyPos),
      [?CREATED, ?NO_CONTENT]),
    http_put(
      "/policies/%2f/policy_even",
      lists:keydelete(key, 1, PolicyEven),
      [?CREATED, ?NO_CONTENT]),
    assert_item(PolicyPos,  http_get("/policies/%2f/policy_pos",  ?OK)),
    assert_item(PolicyEven, http_get("/policies/%2f/policy_even", ?OK)),
    List = [PolicyPos, PolicyEven],
    assert_list(List, http_get("/policies",     ?OK)),
    assert_list(List, http_get("/policies/%2f", ?OK)),

    http_delete("/policies/%2f/policy_pos", ?NO_CONTENT),
    http_delete("/policies/%2f/policy_even", ?NO_CONTENT),
    0 = length(http_get("/policies")),
    0 = length(http_get("/policies/%2f")),
    rabbit_runtime_parameters_test:unregister_policy_validator(),
    ok.

policy_permissions_test() ->
    rabbit_runtime_parameters_test:register(),

    http_put("/users/admin",  [{password, <<"admin">>},
                               {tags, <<"administrator">>}], [?CREATED, ?NO_CONTENT]),
    http_put("/users/mon",    [{password, <<"mon">>},
                               {tags, <<"monitoring">>}], [?CREATED, ?NO_CONTENT]),
    http_put("/users/policy", [{password, <<"policy">>},
                               {tags, <<"policymaker">>}], [?CREATED, ?NO_CONTENT]),
    http_put("/users/mgmt",   [{password, <<"mgmt">>},
                               {tags, <<"management">>}], [?CREATED, ?NO_CONTENT]),
    Perms = [{configure, <<".*">>},
             {write,     <<".*">>},
             {read,      <<".*">>}],
    http_put("/vhosts/v", none, [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/v/admin",  Perms, [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/v/mon",    Perms, [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/v/policy", Perms, [?CREATED, ?NO_CONTENT]),
    http_put("/permissions/v/mgmt",   Perms, [?CREATED, ?NO_CONTENT]),

    Policy = [{pattern,    <<".*">>},
              {definition, [{<<"ha-mode">>, <<"all">>}]}],
    Param = [{value, <<"">>}],

    http_put("/policies/%2f/HA", Policy, [?CREATED, ?NO_CONTENT]),
    http_put("/parameters/test/%2f/good", Param, [?CREATED, ?NO_CONTENT]),

    Pos = fun (U) ->
                  Expected = case U of "admin" -> [?CREATED, ?NO_CONTENT]; _ -> ?NO_CONTENT end,
                  http_put("/policies/v/HA",        Policy, U, U, Expected),
                  http_put(
                    "/parameters/test/v/good",       Param, U, U, Expected),
                  1 = length(http_get("/policies",          U, U, ?OK)),
                  1 = length(http_get("/parameters/test",   U, U, ?OK)),
                  1 = length(http_get("/parameters",        U, U, ?OK)),
                  1 = length(http_get("/policies/v",        U, U, ?OK)),
                  1 = length(http_get("/parameters/test/v", U, U, ?OK)),
                  http_get("/policies/v/HA",                U, U, ?OK),
                  http_get("/parameters/test/v/good",       U, U, ?OK)
          end,
    Neg = fun (U) ->
                  http_put("/policies/v/HA",    Policy, U, U, ?NOT_AUTHORISED),
                  http_put(
                    "/parameters/test/v/good",   Param, U, U, ?NOT_AUTHORISED),
                  http_put(
                    "/parameters/test/v/admin",  Param, U, U, ?NOT_AUTHORISED),
                  %% Policies are read-only for management and monitoring.
                  http_get("/policies",                 U, U, ?OK),
                  http_get("/policies/v",               U, U, ?OK),
                  http_get("/parameters",               U, U, ?NOT_AUTHORISED),
                  http_get("/parameters/test",          U, U, ?NOT_AUTHORISED),
                  http_get("/parameters/test/v",        U, U, ?NOT_AUTHORISED),
                  http_get("/policies/v/HA",            U, U, ?NOT_AUTHORISED),
                  http_get("/parameters/test/v/good",   U, U, ?NOT_AUTHORISED)
          end,
    AlwaysNeg =
        fun (U) ->
                http_put("/policies/%2f/HA",  Policy, U, U, ?NOT_AUTHORISED),
                http_put(
                  "/parameters/test/%2f/good", Param, U, U, ?NOT_AUTHORISED),
                http_get("/policies/%2f/HA",          U, U, ?NOT_AUTHORISED),
                http_get("/parameters/test/%2f/good", U, U, ?NOT_AUTHORISED)
        end,

    [Neg(U) || U <- ["mon", "mgmt"]],
    [Pos(U) || U <- ["admin", "policy"]],
    [AlwaysNeg(U) || U <- ["mon", "mgmt", "admin", "policy"]],

    %% This one is deliberately different between admin and policymaker.
    http_put("/parameters/test/v/admin", Param, "admin", "admin", [?CREATED, ?NO_CONTENT]),
    http_put("/parameters/test/v/admin", Param, "policy", "policy",
             ?BAD_REQUEST),

    http_delete("/vhosts/v", ?NO_CONTENT),
    http_delete("/users/admin", ?NO_CONTENT),
    http_delete("/users/mon", ?NO_CONTENT),
    http_delete("/users/policy", ?NO_CONTENT),
    http_delete("/users/mgmt", ?NO_CONTENT),
    http_delete("/policies/%2f/HA", ?NO_CONTENT),

    rabbit_runtime_parameters_test:unregister(),
    ok.

issue67_test()->
    {ok, {{_, 401, _}, Headers, _}} = req(get, "/queues",
                        [auth_header("user_no_access", "password_no_access")]),
    ?assertEqual("application/json",
      proplists:get_value("content-type",Headers)),
    ok.

extensions_test() ->
    [[{javascript,<<"dispatcher.js">>}]] = http_get("/extensions", ?OK),
    ok.

%%---------------------------------------------------------------------------

msg(Key, Headers, Body) ->
    msg(Key, Headers, Body, <<"string">>).

msg(Key, Headers, Body, Enc) ->
    [{exchange,         <<"">>},
     {routing_key,      Key},
     {properties,       [{delivery_mode, 2},
                         {headers,       Headers}]},
     {payload,          Body},
     {payload_encoding, Enc}].

local_port(Conn) ->
    [{sock, Sock}] = amqp_connection:info(Conn, [sock]),
    {ok, Port} = inet:port(Sock),
    Port.

%%---------------------------------------------------------------------------
http_get(Path) ->
    http_get(Path, ?OK).

http_get(Path, CodeExp) ->
    http_get(Path, "guest", "guest", CodeExp).

http_get(Path, User, Pass, CodeExp) ->
    {ok, {{_HTTP, CodeAct, _}, Headers, ResBody}} =
        req(get, Path, [auth_header(User, Pass)]),
    assert_code(CodeExp, CodeAct, "GET", Path, ResBody),
    decode(CodeExp, Headers, ResBody).

http_put(Path, List, CodeExp) ->
    http_put_raw(Path, format_for_upload(List), CodeExp).

http_put(Path, List, User, Pass, CodeExp) ->
    http_put_raw(Path, format_for_upload(List), User, Pass, CodeExp).

http_post(Path, List, CodeExp) ->
    http_post_raw(Path, format_for_upload(List), CodeExp).

http_post(Path, List, User, Pass, CodeExp) ->
    http_post_raw(Path, format_for_upload(List), User, Pass, CodeExp).

http_post_accept_json(Path, List, CodeExp) ->
    http_post_accept_json(Path, List, "guest", "guest", CodeExp).

http_post_accept_json(Path, List, User, Pass, CodeExp) ->
    http_post_raw(Path, format_for_upload(List), User, Pass, CodeExp, 
		  [{"Accept", "application/json"}]).

http_post_multipart(Path, Type, List, CodeExp) ->
    %% Hardcoded boundary to avoid an issue in cow_multipart:boundary().
    Boundary = "rabbitmrabbitmrabbitmrabbitmrabbitmqqqqq",
    Body = iolist_to_binary([
        cow_multipart:first_part(Boundary,
            [{"content-disposition", ["form-data;name=\"redirect\""]}]),
        "/",
        http_post_multipart_file(Type, Boundary),
        format_for_upload(List),
        cow_multipart:close(Boundary)]),
    {ok, {{_HTTP, CodeAct, _}, Headers, ResBody}} =
        httpc:request(post, {?PREFIX ++ Path, [auth_header("guest", "guest")],
            "multipart/form-data;boundary=" ++ Boundary, Body},
            ?HTTPC_OPTS, []),
    assert_code(CodeExp, CodeAct, post, Path, ResBody),
    decode(CodeExp, Headers, ResBody).

http_post_multipart_file(data, Boundary) ->
    cow_multipart:part(Boundary,
        [{"content-disposition", ["form-data;name=\"file\""]},
         {"content-type", "application/json"}]);
http_post_multipart_file(file, Boundary) ->
    cow_multipart:part(Boundary,
        [{"content-disposition", ["form-data;name=\"file\";filename=\"file1.json\""]},
         {"content-type", "application/octet-stream"}]).

format_for_upload(none) ->
    <<"">>;
format_for_upload(List) ->
    iolist_to_binary(mochijson2:encode({struct, List})).

http_put_raw(Path, Body, CodeExp) ->
    http_upload_raw(put, Path, Body, "guest", "guest", CodeExp, []).

http_put_raw(Path, Body, User, Pass, CodeExp) ->
    http_upload_raw(put, Path, Body, User, Pass, CodeExp, []).


http_post_raw(Path, Body, CodeExp) ->
    http_upload_raw(post, Path, Body, "guest", "guest", CodeExp, []).

http_post_raw(Path, Body, User, Pass, CodeExp) ->
    http_upload_raw(post, Path, Body, User, Pass, CodeExp, []).

http_post_raw(Path, Body, User, Pass, CodeExp, MoreHeaders) ->
    http_upload_raw(post, Path, Body, User, Pass, CodeExp, MoreHeaders).


http_upload_raw(Type, Path, Body, User, Pass, CodeExp, MoreHeaders) ->
    {ok, {{_HTTP, CodeAct, _}, Headers, ResBody}} =
	req(Type, Path, [auth_header(User, Pass)] ++ MoreHeaders, Body),
    assert_code(CodeExp, CodeAct, Type, Path, ResBody),
    decode(CodeExp, Headers, ResBody).

http_delete(Path, CodeExp) ->
    http_delete(Path, "guest", "guest", CodeExp).

http_delete(Path, User, Pass, CodeExp) ->
    {ok, {{_HTTP, CodeAct, _}, Headers, ResBody}} =
        req(delete, Path, [auth_header(User, Pass)]),
    assert_code(CodeExp, CodeAct, "DELETE", Path, ResBody),
    decode(CodeExp, Headers, ResBody).

assert_code(CodesExpected, CodeAct, Type, Path, Body) when is_list(CodesExpected) ->
    case lists:member(CodeAct, CodesExpected) of
        true ->
            ok;
        false ->
            throw({expected, CodesExpected, got, CodeAct, type, Type,
                   path, Path, body, Body})
    end;
assert_code(CodeExp, CodeAct, Type, Path, Body) ->
    case CodeExp of
        CodeAct -> ok;
        _       -> throw({expected, CodeExp, got, CodeAct, type, Type,
                          path, Path, body, Body})
    end.

req(Type, Path, Headers) ->
    httpc:request(Type, {?PREFIX ++ Path, Headers}, ?HTTPC_OPTS, []).

req(Type, Path, Headers, Body) ->
    httpc:request(Type, {?PREFIX ++ Path, Headers, "application/json", Body},
                  ?HTTPC_OPTS, []).

decode(?OK, _Headers,  ResBody) -> cleanup(mochijson2:decode(ResBody));
decode(_,    Headers, _ResBody) -> Headers.

cleanup(L) when is_list(L) ->
    [cleanup(I) || I <- L];
cleanup({struct, I}) ->
    cleanup(I);
cleanup({K, V}) when is_binary(K) ->
    {list_to_atom(binary_to_list(K)), cleanup(V)};
cleanup(I) ->
    I.

auth_header(Username, Password) ->
    {"Authorization",
     "Basic " ++ binary_to_list(base64:encode(Username ++ ":" ++ Password))}.

