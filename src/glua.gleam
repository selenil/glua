import gleam/dynamic.{type Dynamic}
import gleam/result

/// Represents an instance of the Lua VM.
pub type Lua

/// Represents the errors than can happend during the parsing and execution of Lua code
pub type LuaError {
  UnknownError
}

/// Represents a chunk of Lua code that is already loaded into the Lua VM
pub type Chunk

/// Represents a Lua table.
pub type Table

/// Represents a Lua function.
pub type Function

/// Creates a new Lua VM instance
@external(erlang, "luerl", "init")
pub fn new() -> Lua

/// Evaluates a string of Lua code.
///
/// ## Examples
///
/// ```gleam
/// eval(new(), "return 1 + 2")
/// // -> Ok(#([3], Lua))
/// ```
///
/// ```gleam
/// eval(new(), "return 'hello, world!', 10")
/// // -> Ok(#(["hello, world!", 10], Lua))
/// ```
///
/// ```gleam
/// eval(new(), "return 1 * ")
/// // -> Error(SyntaxError)
/// ```
pub fn eval(
  lua lua: Lua,
  code code: String,
) -> Result(#(List(Dynamic), Lua), LuaError) {
  do_eval(lua, code) |> result.map_error(parse_lua_error)
}

@external(erlang, "glua_ffi", "eval")
fn do_eval(
  lua lua: Lua,
  code code: String,
) -> Result(#(List(Dynamic), Lua), Dynamic)

/// Evaluates a Lua source file.
///
/// ## Examples
/// ```gleam
/// eval_file(new(), "path/to/hello.lua")
/// Ok(#(["hello, world!"], Lua))
/// ```
pub fn eval_file(
  lua lua: Lua,
  path path: String,
) -> Result(#(List(Dynamic), Lua), LuaError) {
  do_eval_file(lua, path) |> result.map_error(parse_lua_error)
}

@external(erlang, "glua_ffi", "eval_file")
fn do_eval_file(
  lua: Lua,
  path: String,
) -> Result(#(List(Dynamic), Lua), Dynamic)

// TODO: Actual error parsing
fn parse_lua_error(_err: Dynamic) -> LuaError {
  UnknownError
}
