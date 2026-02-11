-module(glua_ffi).
-import(luerl_lib, [lua_error/2]).
-import(ttdict, [fold/3]).
-include_lib("luerl/include/luerl.hrl").

-export([get_stacktrace/1, dereference/2, coerce/1, coerce_nil/0, wrap_fun/1, sandbox_fun/1, get_table_keys/2,
         get_private/2, set_table_keys/3, load/2, load_file/2, eval/2, eval_file/2,
         eval_chunk/2, call_function/3]).

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
            {error, {unknown_error, nil}}
    end.

dereference_list(St, LuerlTerms) ->
    lists:map(fun (Lt) -> dereference(St, Lt) end, LuerlTerms).

%% transforms Lua values to their corresponding Erlang representation
%% this is similar to `luerl:decode/2`, but returns values that are more decode-friendly in Gleam
dereference(St, LT) ->
    dereference(LT, St, []).

dereference(nil, _, _) -> nil;
dereference(false, _, _) -> false;
dereference(true, _, _) -> true;
dereference(B, _, _) when is_binary(B) -> B;
dereference(N, _, _) when is_number(N) -> N;         %Integers and floats
dereference(#tref{}=T, St, In) ->
    dereference_table(T, St, In);
dereference(#usdref{}=U, St, _In) ->
    {#userdata{d=Data},_} = luerl_heap:get_userdata(U, St),
    Data;
dereference(#funref{}=Fun, _St, _In) ->
    dereference_fun(Fun);
dereference(#erl_func{code=Fun}, _St, _In) ->
    Fun;                                       %Just the bare fun
dereference(#erl_mfa{m=M, f=F}, _St, _In) ->
    dereference_fun(fun(Args, St0) -> M:F(nil, Args, St0) end);
dereference(Lua, _, _) -> error({badarg,Lua}).       %Shouldn't have anything else

dereference_table(#tref{i=N}=T, St, In0) ->
    case lists:member(N, In0) of
        true ->
            % Been here before
            error({recursive_table, T});
        false ->
            % We are in this as well
            In1 = [N | In0],
            case luerl_heap:get_table(T, St) of
                #table{a = Arr, d = Dict} ->
                    Fun = fun(K, V, Acc) ->
                        Acc#{
                            dereference(K, St, In1)
                            => dereference(V, St, In1)
                        }
                    end,
                    M0 = ttdict:fold(Fun, #{}, Dict),
                    array:sparse_foldr(Fun, M0, Arr);
                _Undefined ->
                    error(badarg)
            end
    end.

dereference_fun(F) when is_function(F, 2) ->
    {luafun, fun(St0, Args) ->
        try
            {Ret, St1} = F(Args, St0),
            {ok, {St1, Ret}}
        catch
            error:{lua_error, _, _} = Err -> {error, map_error(Err)}
        end
    end}.

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

wrap_fun(Fun) ->
    {erl_func, fun(Args, State) ->
            {NewState, Ret} = Fun(State, dereference_list(State, Args)),
            {Ret, NewState}
    end}.

sandbox_fun(Msg) ->
    {erl_func, fun(_, State) ->
        {error, map_error(lua_error({error_call, [Msg]}, State))}
    end}.

get_table_keys(Lua, Keys) ->
    case luerl:get_table_keys(Keys, Lua) of
        {ok, nil, _} ->
            {error, {key_not_found, Keys}};
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
    case luerl:loadfile(unicode:characters_to_list(Path), Lua) of
      {error, [{none, file, enoent} | _], _} ->
        {error, {file_not_found, Path}};
      Other -> to_gleam(Other)
    end.

eval(Lua, Code) ->
    to_gleam(luerl:do(
                 unicode:characters_to_list(Code), Lua)).

eval_chunk(Lua, Chunk) ->
    to_gleam(luerl:call_chunk(Chunk, Lua)).

eval_file(Lua, Path) ->
    to_gleam(luerl:dofile(
                 unicode:characters_to_list(Path), Lua)).

call_function(Lua, Fun, Args) ->
    to_gleam(luerl:call(Fun, Args, Lua)).

get_private(Lua, Key) ->
    try
        {ok, luerl:get_private(Key, Lua)}
    catch
        error:{badkey, _} ->
            {error, {key_not_found, [Key]}}
    end.
