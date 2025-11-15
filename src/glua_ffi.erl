-module(glua_ffi).
-export([lua_nil/1, encode/2, get_table_keys/2, set_table_keys/3, load/2, load_file/2, eval/2, eval_chunk/2, eval_file/2, call_function/3]).

%% helper to convert luerl return values to a format
%% that is more suitable for use in Gleam code
to_gleam(Value) ->
  case Value of
    {ok, Result, LuaState} -> {ok, {Result, LuaState}};
    {ok, _} = Result -> Result;
    {lua_error, Errors, _} -> {error, Errors};
    {error, L1, L2} -> {error, {L1, L2}};
    error -> {error, nil}
  end.

lua_nil(Lua) ->
  encode(Lua, nil).

encode(Lua, Value) ->
  {Value, Lua} = luerl:encode(Value, Lua),
  {Lua, Value}.

get_table_keys(Lua, Keys) ->
  case to_gleam(luerl:get_table_keys(Keys, Lua)) of
    {ok, {nil, _}} -> {error, nil};
    {ok, {Value, _}} -> {ok, Value};
    Other -> Other 
  end.

set_table_keys(Lua, Keys, Value) ->
  to_gleam(luerl:set_table_keys(Keys, Value, Lua)).

load(Lua, Code) ->
  to_gleam(luerl:load(unicode:characters_to_list(Code), Lua)).
  
load_file(Lua, Path) ->
  to_gleam(luerl:loadfile(unicode:characters_to_list(Path), Lua)).

eval(Lua, Code) ->
  to_gleam(luerl:do(unicode:characters_to_list(Code), Lua)).

eval_chunk(Lua, Chunk) ->
  to_gleam(luerl:call_chunk(Chunk, Lua)).

eval_file(Lua, Path) ->
  to_gleam(luerl:dofile(unicode:characters_to_list(Path), Lua)).

call_function(Lua, Fun, Args) ->
  to_gleam(luerl:call(Fun, Args, Lua)).
