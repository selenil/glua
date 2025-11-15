import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/result

/// Represents an instance of the Lua VM.
pub type Lua

/// Represents the errors than can happend during the parsing and execution of Lua code
pub type LuaError {
  UnknownError
}

/// Represents a chunk of Lua code that is already loaded into the Lua VM
pub type Chunk

/// Represents a value that can be passed to the Lua environment.
pub type Value

/// Represents a reference to a value inside the Lua environment.
///
/// Each one of the functions that returns values from the Lua environment has a `ref_` counterpart
/// that will return references to the values instead of decoding them.
pub type ValueRef

@external(erlang, "glua_ffi", "lua_nil")
pub fn nil(lua: Lua) -> #(Lua, Value)

pub fn string(lua: Lua, v: String) -> #(Lua, Value) {
  encode(lua, v)
}

pub fn bool(lua: Lua, v: Bool) -> #(Lua, Value) {
  encode(lua, v)
}

pub fn int(lua: Lua, v: Int) -> #(Lua, Value) {
  encode(lua, v)
}

pub fn float(lua: Lua, v: Float) -> #(Lua, Value) {
  encode(lua, v)
}

pub fn table(
  lua: Lua,
  encoders: #(fn(Lua, a) -> #(Lua, Value), fn(Lua, b) -> #(Lua, Value)),
  values: List(#(a, b)),
) -> #(Lua, Value) {
  let #(key_encoder, value_encoder) = encoders
  let #(lua, values) =
    list.map_fold(values, lua, fn(lua, pair) {
      let #(lua, k) = key_encoder(lua, pair.0)
      let #(lua, v) = value_encoder(lua, pair.1)
      #(lua, #(k, v))
    })

  encode(lua, values)
}

pub fn table_decoder(
  keys_decoder: decode.Decoder(a),
  values_decoder: decode.Decoder(b),
) -> decode.Decoder(List(#(a, b))) {
  let inner = {
    use key <- decode.field(0, keys_decoder)
    use val <- decode.field(1, values_decoder)
    decode.success(#(key, val))
  }

  decode.list(of: inner)
}

pub fn function(
  lua: Lua,
  v: fn(Lua, List(Dynamic)) -> #(Lua, Value),
) -> #(Lua, Value) {
  // wrapper to satisfy luerl's order of arguments and return value
  let fun = fn(args, lua) {
    let #(lua, ret) = v(lua, args)
    #(ret, lua)
  }
  encode(lua, fun)
}

/// Encodes a list of values using the provided encoded function.
pub fn list(
  lua: Lua,
  encoder: fn(Lua, a) -> #(Lua, Value),
  values: List(a),
) -> #(Lua, List(Value)) {
  list.map_fold(values, lua, encoder)
}

@external(erlang, "glua_ffi", "encode")
fn encode(lua: Lua, v: anything) -> #(Lua, Value)

/// Creates a new Lua VM instance
@external(erlang, "luerl", "init")
pub fn new() -> Lua

/// Gets a value in the Lua environment.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(lua_version) = glua.get(glua.new(), ["_Version"])
/// decode.run(lua_version, decode.string)
/// // -> Ok("Lua 5.3")
/// ```
///
/// ```gleam
/// let assert Ok(lua) = glua.set(glua.new(), ["my_table", "my_value"], True)
/// let assert Ok(val) = glua.get(lua, ["my_table", "my_value"])
/// decode.run(val, decode.bool)
/// // -> Ok(True)
/// ```
///
/// ```gleam
/// let lua = glua.new()
/// let assert Ok(fun) = glua.get(glua.new(), ["string", "upper"])
/// let assert Ok(#([result], _)) = glua.call_function(lua, fun, ["hello, world!"])
/// decode.run(val, decode.string)
/// // -> Ok("HELLO, WORLD!")
///
/// ```gleam
/// glua.get(glua.new(), ["non_existent"])
/// // -> Error(NonExistentValue)
/// ```
pub fn get(lua lua: Lua, keys keys: List(String)) -> Result(Dynamic, LuaError) {
  let #(keys, lua) = encode_list(keys, lua)

  do_get(lua, keys) |> result.map_error(parse_lua_error)
}

/// Sets a value in the Lua environment.
///
/// All nested keys will be created as intermediate tables.
///
/// If successfull, this function will return the updated Lua state
/// and the value will be available in Lua scripts.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(lua) = glua.set(glua.new(), ["my_number"], 10)
/// let assert Ok(n) = glua.get(lua, ["my_number"])
/// decode.run(n, decode.int)
/// // -> Ok(10)
/// ```
///
/// ```gleam
/// let assert Ok(lua) = glua.set(glua.new(), ["info", "emails"], ["jhondoe@example.com", "lucy@example.com"])
/// let assert Ok(#(emails, _)) = glua.eval(lua, "return info.emails")
/// decode.run(dynamic.list(emails), decode.list(of: decode.string))
/// // -> Ok(["jhondoe@example.com", "lucy@example.com"])
/// ```
pub fn set(
  lua lua: Lua,
  keys keys: List(String),
  val val: a,
) -> Result(Lua, LuaError) {
  let encoded = encode_list(keys, lua)
  let state = {
    use acc, key <- list.try_fold(encoded.0, #([], encoded.1))
    let #(keys, lua) = acc
    let keys = list.append(keys, [key])
    case do_get(lua, keys) {
      Ok(_) -> Ok(#(keys, lua))
      _ -> {
        let #(tbl, lua) = alloc_table([], lua)
        case do_set(lua, keys, tbl) {
          Ok(lua) -> Ok(#(keys, lua))
          Error(e) -> Error(parse_lua_error(e))
        }
      }
    }
  }
  use state <- result.try(state)
  let #(keys, lua) = state
  do_set(lua, keys, val) |> result.map_error(parse_lua_error)
}

@external(erlang, "luerl", "encode_list")
fn encode_list(keys: List(String), lua: Lua) -> #(List(Dynamic), Lua)

@external(erlang, "luerl_emul", "alloc_table")
fn alloc_table(content: List(a), lua: Lua) -> #(a, Lua)

@external(erlang, "glua_ffi", "get_table_keys")
fn do_get(lua: Lua, keys: List(Dynamic)) -> Result(Dynamic, Dynamic)

@external(erlang, "glua_ffi", "set_table_keys")
fn do_set(lua: Lua, keys: List(Dynamic), val: a) -> Result(Lua, Dynamic)

/// Parses a string of Lua code and returns it as a compiled chunk.
///
/// To eval the returned chunk, use `glua.eval_chunk`.
pub fn load(lua lua: Lua, code code: String) -> Result(#(Chunk, Lua), LuaError) {
  do_load(lua, code) |> result.map_error(parse_lua_error)
}

@external(erlang, "glua_ffi", "load")
fn do_load(lua lua: Lua, code code: String) -> Result(#(Chunk, Lua), Dynamic)

/// Parses a Lua source file and returns it as a compiled chunk.
///
/// To eval the returned chunk, use `glua.eval_chunk`.
pub fn load_file(
  lua lua: Lua,
  code code: String,
) -> Result(#(Chunk, Lua), LuaError) {
  do_load_file(lua, code) |> result.map_error(parse_lua_error)
}

@external(erlang, "glua_ffi", "load_file")
fn do_load_file(
  lua lua: Lua,
  code code: String,
) -> Result(#(Chunk, Lua), Dynamic)

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
/// Note: If you are evaluating the same piece of code multiple times,
/// instead of calling `glua.eval` repeatly it is recommended to first convert
/// the code to a chunk by passing it to `glua.load`, and then
/// evaluate that chunk using `glua.eval_chunk`
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

/// Evaluates a compiled chunk of Lua code.
///
/// ## Examples
/// ```gleam
/// let assert Ok(#(chunk, lua)) = load(glua.new(), "return 'hello, world!'")
/// eval(lua, chunk)
/// -> Ok(#(["hello, world!"], Lua)) 
/// ```
pub fn eval_chunk(
  lua lua: Lua,
  chunk chunk: Chunk,
) -> Result(#(List(Dynamic), Lua), LuaError) {
  do_eval_chunk(lua, chunk) |> result.map_error(parse_lua_error)
}

@external(erlang, "glua_ffi", "eval_chunk")
fn do_eval_chunk(
  lua lua: Lua,
  chunk chunk: Chunk,
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

/// Calls a Lua function by reference.
///
/// ## Examples
/// ```gleam
/// let assert Ok(#(fun, lua)) = glua.eval(glua.new(), "return math.sqrt")
/// let assert Ok(#([result], _)) = glua.call_function(lua, fun, [49])
/// let decoded = decode.run(result, decode.int)
/// assert decoded == Ok(49)
/// ```
///
/// ```gleam
/// let code = "function fib(n)
///   if n <= 1 then
///     return n
///   else
///     return fib(n - 1) + fib(n - 2)
///   end
///end
///
///return fib
///"
/// let assert Ok(#(fun, lua)) = glua.eval(glua.new(), code)
/// let assert Ok(#([result], _)) = glua.call_function(lua, fun, [10])
/// let decoded = decode.run(result, decode.int)
/// assert decoded == Ok(55)
/// ```
pub fn call_function(
  lua lua: Lua,
  fun fun: Dynamic,
  args args: List(a),
) -> Result(#(List(Dynamic), Lua), LuaError) {
  do_call_function(lua, fun, args) |> result.map_error(parse_lua_error)
}

@external(erlang, "glua_ffi", "call_function")
fn do_call_function(
  lua: Lua,
  fun: Dynamic,
  args: List(a),
) -> Result(#(List(Dynamic), Lua), Dynamic)

/// Gets a reference to the function at `keys`, then inmediatly calls it with the provided `args`.
///
/// This is a shorthand for `glua.get` followed by `glua.call_function`.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(#([s], _)) = glual.call_function_by_name(glua:new(), ["string", "lower"], "HELLO FROM GLEAM!")
/// decode.run(s, decode.string)
/// // -> Ok(hello from gleam") 
/// ```
pub fn call_function_by_name(
  lua lua: Lua,
  keys keys: List(String),
  args args: List(a),
) -> Result(#(List(Dynamic), Lua), LuaError) {
  use fun <- result.try(get(lua, keys))
  call_function(lua, fun, args)
}

// TODO: Actual error parsing
fn parse_lua_error(_err: Dynamic) -> LuaError {
  UnknownError
}
