-module(glua_ffi).
-import(luerl_lib, [lua_error/2]).

-export([get_stacktrace/1, coerce/1, coerce_nil/0, coerce_userdata/1, wrap_fun/1, sandbox_fun/1, get_table_keys/2, get_table_keys_dec/2,
         get_private/2, set_table_keys/3, load/2, load_file/2, eval/2, eval_dec/2, eval_file/2,
         eval_file_dec/2, eval_chunk/2, eval_chunk_dec/2, call_function/3, call_function_dec/3]).

%% turn `{userdata, Data}` into `Data` to make it more easy to decode it in Gleam
maybe_process_userdata(Lst) when is_list(Lst) ->
    lists:map(fun maybe_process_userdata/1, Lst);
maybe_process_userdata({userdata, Data}) ->
    Data;
maybe_process_userdata(Other) ->
    Other.

%% helper to convert luerl return values to a format
%% that is more suitable for use in Gleam code
to_gleam(Value) ->
    case Value of
        {ok, Result, LuaState} ->
            Values = maybe_process_userdata(Result),
            {ok, {LuaState, Values}};
        {ok, _} = Result ->
            maybe_process_userdata(Result);
        {lua_error, _, _} = Error ->
            {error, map_error(Error)};
        {error, _, _} = Error ->
            {error, map_error(Error)};
        error ->
            {error, {unknown_error, nil}}
    end.

%% helper to determine if a value is encoded or not
%% borrowed from https://github.com/tv-labs/lua/blob/main/lib/lua/util.ex#L19-L35
is_encoded(nil) ->
    true;
is_encoded(true) ->
    true;
is_encoded(false) ->
    true;
is_encoded(Binary) when is_binary(Binary) ->
    true;
is_encoded(N) when is_number(N) ->
    true;
is_encoded({tref,_}) ->
    true;
is_encoded({usrdef,_}) ->
    true;
is_encoded({eref,_}) ->
    true;
is_encoded({funref,_,_}) ->
    true;
is_encoded({erl_func,_}) ->
    true;
is_encoded({erl_mfa,_,_,_}) ->
    true;
is_encoded(_) ->
    false.

map_error({error, Errors, _}) ->
    {lua_compile_failure, lists:map(fun map_compile_error/1, Errors)};
map_error({lua_error, {illegal_index, Value, Index}, State}) ->
    FormattedIndex = unicode:characters_to_binary(Index),
    FormattedValue = unicode:characters_to_binary(io_lib:format("~p",[luerl:decode(Value, State)])),
    {lua_runtime_exception, {illegal_index, FormattedIndex, FormattedValue}, State}; 
map_error({lua_error, {error_call, Args}, State}) ->
    case Args of
        [Msg, Level] when is_binary(Msg) andalso is_integer(Level) ->
            {lua_runtime_exception, {error_call, Msg, {some, Level}}, State};
        [Msg] when is_binary(Msg) ->
            {lua_runtime_exception, {error_call, Msg, none}, State};

        % error() was called with incorrect arguments
        _ ->
            {unknown_error, {error_call, Args}}
    end;
map_error({lua_error, {undefined_function, Value}, State}) ->
    {lua_runtime_exception,
     {undefined_function, unicode:characters_to_binary(io_lib:format("~p",[Value]))}, State};
map_error({lua_error, {undefined_method, Obj, Value}, State}) ->
    {lua_runtime_exception,
     {undefined_method, unicode:characters_to_binary(io_lib:format("~p", [Obj])), Value}, State};
map_error({lua_error, {badarith, Operator, Args}, State}) ->
    FormattedOperator = unicode:characters_to_binary(atom_to_list(Operator)),
    FormattedArgs =
        lists:map(fun(V) ->
                     unicode:characters_to_binary(
                         io_lib:format("~p", [V]))
                  end,
                  Args),
    {lua_runtime_exception, {bad_arith, FormattedOperator, FormattedArgs}, State};
map_error({lua_error, {assert_error, Msg} = Error, State}) ->
    case Msg of
        M when is_binary(M) ->
            {lua_runtime_exception, Error, State};

        % assert() was called with incorrect arguments
        _ ->
            {unknown_error, Error}
    end;
map_error({lua_error, {badarg, F, Args}, State}) ->
  {lua_runtime_exception, {badarg, atom_to_binary(F), Args}, State};
map_error({lua_error, _, State}) ->
    {lua_runtime_exception, unknown_exception, State};
map_error(Error) ->
   {unknown_error, Error}.

map_compile_error({Line, Type, {user, Messages}}) ->
    map_compile_error({Line, Type, Messages});
map_compile_error({Line, Type, {illegal, Token}}) ->
    map_compile_error({Line, Type, io_lib:format("~p ~p",["Illegal token",Token])});
map_compile_error({Line, Type, Messages}) ->
    Kind = case Type of
        luerl_parse -> parse;
        luerl_scan -> tokenize
    end,
    {lua_compile_error, Line, Kind, unicode:characters_to_binary(Messages)}.


get_stacktrace(State) ->
    case luerl:get_stacktrace(State) of
        [] ->
            <<"">>;
        Stacktrace -> format_stacktrace(State, Stacktrace)
    end.

%% turns a Lua stacktrace into a string suitable for pretty-printing
%% borrowed from: https://github.com/tv-labs/lua
format_stacktrace(State, [_ | Rest] = Stacktrace) ->
    Zipped = gleam@list:zip(Stacktrace, Rest),
    Lines = lists:map(
        fun
            ({{Func, [{tref, _} = Tref | Args], _}, {_, _, Context}}) ->
                Keys = lists:map(
                    fun({K, _}) -> io_lib:format("~p", [K]) end,
                    luerl:decode(Tref, State)
                ),
                FormattedArgs = format_args(Args),
                io_lib:format(
                    "~p with arguments ~s\n"
                    "^--- self is incorrect for object with keys ~s\n\n\n"
                    "Line ~p",
                    [
                        Func,
                        FormattedArgs,
                        lists:join(", ", Keys),
                        proplists:get_value(line, Context)
                    ]
                );
            ({{Func, Args, _}, {_, _, Context}}) ->
                FormattedArgs = format_args(Args),
                Name =
                    case Func of
                        nil ->
                            "<unknown function>" ++ FormattedArgs;
                        "-no-name-" ->
                            "";
                        {luerl_lib_basic, basic_error} ->
                            "error" ++ FormattedArgs;
                        {luerl_lib_basic, basic_error, undefined} ->
                            "error" ++ FormattedArgs;
                        {luerl_lib_basic, error_call, undefined} ->
                            "error" ++ FormattedArgs;
                        {luerl_lib_basic, assert, undefined} ->
                            "assert" ++ FormattedArgs;
                        _ ->
                            N =
                                case Func of
                                    {tref, _} -> "<reference>";
                                    _ -> Func
                                end,
                            io_lib:format("~p~s", [N, FormattedArgs])
                    end,
                io_lib:format("Line ~p: ~s", [
                    proplists:get_value(line, Context),
                    Name
                ])
        end,
        Zipped
    ),
    unicode:characters_to_binary(lists:join("\n", Lines)).

%% borrowed from: https://github.com/tv-labs/lua
format_args(Args) ->
  ["(", lists:join(", ", lists:map(fun luerl_lib:format_value/1, Args)), ")"].

coerce(X) ->
    X.

coerce_nil() ->
    nil.

coerce_userdata(X) ->
    {userdata, X}.

wrap_fun(Fun) ->
    fun(Args, State) ->
            Decoded = luerl:decode_list(Args, State),
            {NewState, Ret} = Fun(State, Decoded),
            luerl:encode_list(Ret, NewState)
    end.

sandbox_fun(Msg) ->
    fun(_, State) -> {error, map_error(lua_error({error_call, [Msg]}, State))} end.

get_table_keys(Lua, Keys) ->
    case luerl:get_table_keys(Keys, Lua) of
        {ok, nil, _} ->
            {error, {key_not_found, Keys}};
        {ok, Value, _} ->
            {ok, Value};
        Other ->
            to_gleam(Other)
    end.

get_table_keys_dec(Lua, Keys) ->
    case luerl:get_table_keys_dec(Keys, Lua) of
        {ok, nil, _} ->
            {error, {key_not_found, Keys}};
        {ok, Value, _} ->
            {ok, Value};
        Other ->
            to_gleam(Other)
    end.

set_table_keys(Lua, Keys, Value) ->
    SetFun = case is_encoded(Value) of
                 true -> fun luerl:set_table_keys/3;
                 false -> fun luerl:set_table_keys_dec/3
             end,
    to_gleam(SetFun(Keys, Value, Lua)).

load(Lua, Code) ->
    to_gleam(luerl:load(
                 unicode:characters_to_list(Code), Lua)).

load_file(Lua, Path) ->
    case luerl:loadfile(unicode:characters_to_list(Path), Lua) of
      {error, [{none, file, enoent} | _], _} ->
        {error, {file_not_found, Path}};
      Other -> to_gleam(Other)
    end.

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
    {EncodedArgs, State} = luerl:encode_list(Args, Lua),
    to_gleam(luerl:call(Fun, EncodedArgs, State)).

call_function_dec(Lua, Fun, Args) ->
    {EncodedArgs, St1} = luerl:encode_list(Args, Lua),
    case luerl:call(Fun, EncodedArgs, St1) of
        {ok, Ret, St2} ->
            Values = luerl:decode_list(Ret, St2),
            {ok, {St2, Values}};
        Other ->
            to_gleam(Other)
    end.

get_private(Lua, Key) ->
    try
        {ok, luerl:get_private(Key, Lua)}
    catch
        error:{badkey, _} ->
            {error, {key_not_found, [Key]}}
    end.
