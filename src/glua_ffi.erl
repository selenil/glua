-module(glua_ffi).

-import(luerl_lib, [lua_error/2]).

-export([lua_nil/1, encode/2, sandbox_fun/1, get_table_keys/2, get_table_keys_dec/2,
         get_private/2, set_table_keys/3, load/2, load_file/2, eval/2, eval_dec/2, eval_file/2,
         eval_file_dec/2, eval_chunk/2, eval_chunk_dec/2, call_function/3, call_function_dec/3]).

%% helper to convert luerl return values to a format
%% that is more suitable for use in Gleam code
to_gleam(Value) ->
    case Value of
        {ok, Result, LuaState} ->
            {ok, {LuaState, Result}};
        {ok, _} = Result ->
            Result;
        {lua_error, _, _} = Error ->
            {error, map_error(Error)};
        {error, _, _} = Error ->
            {error, map_error(Error)};
        error ->
            {error, unknown_error}
    end.

%% TODO: Improve compiler errors handling and try to detect more errors
map_error({error, [{_, luerl_parse, Errors} | _], _}) ->
    FormattedErrors = lists:map(fun(E) -> list_to_binary(E) end, Errors),
    {lua_compiler_exception, FormattedErrors};
map_error({lua_error, {illegal_index, Tbl, Value}, State}) ->
    FormattedTbl = list_to_binary(io_lib:format("~p", [Tbl])),
    FormattedValue = unicode:characters_to_binary(Value),
    {lua_runtime_exception, {illegal_index, FormattedTbl, FormattedValue}, State};
map_error({lua_error, {error_call, _} = Error, State}) ->
    {lua_runtime_exception, Error, State};
map_error({lua_error, {undefined_function, Value}, State}) ->
    {lua_runtime_exception,
     {undefined_function, list_to_binary(io_lib:format("~p", [Value]))},
     State};
map_error({lua_error, {badarith, Operator, Args}, State}) ->
    FormattedOperator = unicode:characters_to_binary(atom_to_list(Operator)),
    FormattedArgs =
        lists:map(fun(V) ->
                     unicode:characters_to_binary(
                         io_lib:format("~p", [V]))
                  end,
                  Args),
    {lua_runtime_exception, {bad_arith, FormattedOperator, FormattedArgs}, State};
map_error({lua_error, {assert_error, _} = Error, State}) ->
    {lua_runtime_exception, Error, State};
map_error({lua_error, _, State}) ->
    {lua_runtime_exception, unknown_exception, State};
map_error(_) ->
    unknown_error.

lua_nil(Lua) ->
    encode(Lua, nil).

encode(Lua, Lst) when is_list(Lst) ->
    %% calling `luerl:encode/2` here will encode each element 
    %% inside the list and it can raise if there are elements already encoded
    %% since we know that all elements were previously encoded,
    %% we instead skip the encoding step and manually allocate the table
    {T, State} = luerl_heap:alloc_table(Lst, Lua),
    {State, T};
encode(Lua, Value) ->
    {Encoded, State} = luerl:encode(Value, Lua),
    {State, Encoded}.

sandbox_fun(Msg) ->
    fun(_, State) -> {error, map_error(lua_error({error_call, [Msg]}, State))} end.

get_table_keys(Lua, Keys) ->
    case luerl:get_table_keys(Keys, Lua) of
        {ok, nil, _} ->
            {error, key_not_found};
        {ok, Value, _} ->
            {ok, Value};
        Other ->
            to_gleam(Other)
    end.

get_table_keys_dec(Lua, Keys) ->
    case luerl:get_table_keys_dec(Keys, Lua) of
        {ok, nil, _} ->
            {error, key_not_found};
        {ok, Value, _} ->
            {ok, Value};
        Other ->
            to_gleam(Other)
    end.

set_table_keys(Lua, Keys, Value) ->
    to_gleam(luerl:set_table_keys(Keys, Value, Lua)).

load(Lua, Code) ->
    to_gleam(luerl:load(
                 unicode:characters_to_list(Code), Lua)).

load_file(Lua, Path) ->
    to_gleam(luerl:loadfile(
                 unicode:characters_to_list(Path), Lua)).

eval(Lua, Code) ->
    to_gleam(luerl:do(
                 unicode:characters_to_list(Code), Lua)).

eval_dec(Lua, Code) ->
    to_gleam(luerl:do_dec(
                 unicode:characters_to_list(Code), Lua)).

eval_chunk(Lua, Chunk) ->
    to_gleam(luerl:call_chunk(Chunk, Lua)).

eval_chunk_dec(Lua, Chunk) ->
    call_function_dec(Lua, Chunk, []).

eval_file(Lua, Path) ->
    to_gleam(luerl:dofile(
                 unicode:characters_to_list(Path), Lua)).

eval_file_dec(Lua, Path) ->
    to_gleam(luerl:dofile_dec(
                 unicode:characters_to_list(Path), Lua)).

call_function(Lua, Fun, Args) ->
    to_gleam(luerl:call(Fun, Args, Lua)).

call_function_dec(Lua, Fun, Args) ->
    case luerl:call(Fun, Args, Lua) of
        {ok, Ret, Lua} ->
            Values = luerl:decode_list(Ret, Lua),
            {ok, {Lua, Values}};
        Other ->
            to_gleam(Other)
    end.

get_private(Lua, Key) ->
    try
        {ok, luerl:get_private(Key, Lua)}
    catch
        error:{badkey, _} ->
            {error, key_not_found}
    end.
