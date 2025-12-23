//// A library to embed Lua in Gleam programs.
////
//// Gleam wrapper around [Luerl](https://github.com/rvirding/luerl).

import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleam/string

/// Represents an instance of the Lua VM.
pub type Lua

/// Represents the errors than can happend during the parsing and execution of Lua code
pub type LuaError {
  /// There was an exception when compiling the Lua code.
  LuaCompilerException(messages: List(String))
  /// The Lua environment threw an exception during code execution.
  LuaRuntimeException(exception: LuaRuntimeExceptionKind, state: Lua)
  /// A certain key was not found in the Lua environment.
  KeyNotFound
  /// The value returned by the Lua environment could not be decoded using the provided decoder.
  UnexpectedResultType(List(decode.DecodeError))
  /// An error that could not be identified.
  UnknownError
}

/// Represents the kind of exceptions that can happen at runtime during Lua code execution.
pub type LuaRuntimeExceptionKind {
  /// The exception that happens when trying to access an index that does not exists on a table (also happens when indexing non-table values).
  IllegalIndex(value: String, index: String)
  /// The exception that happens when the `error` function is called.
  ErrorCall(messages: List(String))
  /// The exception that happens when trying to call a function that is not defined.
  UndefinedFunction(value: String)
  /// The exception that happens when an invalid arithmetic operation is performed.
  BadArith(operator: String, args: List(String))
  /// The exception that happens when a call to assert is made passing a value that evalues to `false` as the first argument.
  AssertError(message: String)
  /// An exception that could not be identified
  UnknownException
}

/// The exception that happens when a functi
/// Represents a chunk of Lua code that is already loaded into the Lua VM
pub type Chunk

/// Represents a value that can be passed to the Lua environment.
pub type Value

/// Represents a reference to a value inside the Lua environment.
///
/// Each one of the functions that returns values from the Lua environment has a `ref_` counterpart
/// that will return references to the values instead of decoding them.
pub type ValueRef

@external(erlang, "glua_ffi", "coerce_nil")
pub fn nil() -> Value

@external(erlang, "glua_ffi", "coerce")
pub fn string(v: String) -> Value

@external(erlang, "glua_ffi", "coerce")
pub fn bool(v: Bool) -> Value

@external(erlang, "glua_ffi", "coerce")
pub fn int(v: Int) -> Value

@external(erlang, "glua_ffi", "coerce")
pub fn float(v: Float) -> Value

@external(erlang, "glua_ffi", "coerce")
pub fn table(values: List(#(Value, Value))) -> Value

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
  f: fn(Lua, List(dynamic.Dynamic)) -> #(Lua, List(Value)),
) -> Value {
  // we need a little wrapper for functions to satisfy luerl's order of arguments and return value type
  wrap_function(f)
}

pub fn list(encoder: fn(a) -> Value, values: List(a)) -> List(Value) {
  list.map(values, encoder)
}

/// Encodes any Gleam value as a reference that can be passed to a Lua program.
///
/// Deferencing a userdata value inside Lua code will cause a Lua exception.
///
/// ## Examples
///
/// ```gleam
/// pub type User {
///   User(name: String, is_admin: Bool)
/// }
///
/// let user_decoder = {
///   use name <- decode.field(1, decode.string)
///   use is_admin <- decode.field(2, decode.bool)
///   decode.success(User(name:, is_admin:))
/// }
///
/// let state = glua.new()
/// let assert Ok(state) = glua.set(
///   state:,
///   keys: ["a_user"],
///   value: glua.userdata(User(name: "Jhon Doe", is_admin: False))
/// )
///
/// let assert Ok(#(_, [result])) = glua.eval(state:, code: "return a_user", using: user_decoder)
/// assert result == User("Jhon Doe", False)
/// ```
///
/// ```gleam
/// pub type Person {
///   Person(name: String, email: String)
/// }
///
/// let state = glua.new()
/// let assert Ok(lua) = glua.set(
///   state:,
///   keys: ["lucy"],
///   value: glua.userdata(Person(name: "Lucy", email: "lucy@example.com"))
/// )
///
/// let assert Error(glua.LuaRuntimeException(glua.IllegalIndex(_), _)) =
///   glua.eval(state:, code: "return lucy.email", using: decode.string)
/// ```
@external(erlang, "glua_ffi", "coerce_userdata")
pub fn userdata(v: anything) -> Value

@external(erlang, "glua_ffi", "wrap_fun")
fn wrap_function(
  fun: fn(Lua, List(dynamic.Dynamic)) -> #(Lua, List(Value)),
) -> Value

/// Allocates memory in the Lua state for an encoded value.
///
/// Whenever you try to set an encoded value in the Lua state or pass it as an argument to a Lua function,
/// `glua` allocates memory in the Lua state for that value automatically. This means that the same value
/// can be allocated multiple times depending on how you use it and that multiple, distinct versions
/// of that value could exist at runtime.
///
/// Consider this example:
///
/// ```gleam
/// let proxy =
///   fn(state, _) {
///     let assert Ok(#(state, _)) =
///       glua.ref_call_function_by_name(state:, keys: ["error"], args: [
///         glua.string("attempt to update a read-only table"),
///       ])
///
///     #(state, [])
///   }
///   |> glua.function
///
/// let state = glua.new()
/// let table = glua.table([])
/// let metatable = glua.table([#(glua.string("__newindex"), proxy)])
/// let assert Ok(#(state, _)) =
///   glua.ref_call_function_by_name(state:, keys: ["setmetatable"], args: [
///     table,
///     metatable,
///   ])
/// let assert Ok(state) = glua.set(state:, keys: ["my_table"], value: table)
///
/// let code =
///   "my_table.my_key = 'this should not be the value'; return my_table.my_key"
///
/// glua.eval(state:, code:, using: decode.string)
/// // -> Ok(#(_, ["this should not be the key"]))
/// ```
///
/// Here we expect that a Lua exception will be raised whenever we try to set a new key in `table`,
/// but we can still set new keys as usual. This happens because `table` is allocated twice, making the table
/// you pass as an argument to `setmetatable` and the table you set at `my_table` two different tables at runtime.
///
/// There are situations where you want to allocate memory only once for a value and make sure that
/// at runtime there is only one copy of that value. This function does exactly that.
///
/// We can fix our example by using `glua.alloc`:
///
/// ```gleam
/// let proxy =
///   fn(state, _) {
///     let assert Ok(#(state, _)) =
///       glua.ref_call_function_by_name(state:, keys: ["error"], args: [
///         glua.string("attempt to update a read-only table"),
///       ])
///
///     #(state, [])
///   }
///   |> glua.function
///
/// // we use `glua.alloc` here to avoid `table` to be allocated multiple times
/// let #(state, table) = glua.alloc(glua.new(), glua.table([]))
///
/// // we can keep `metatable` as it because it is only used once
/// let metatable = glua.table([#(glua.string("__newindex"), proxy)])
///
/// let assert Ok(#(state, _)) = glua.ref_call_function_by_name(
///   state:,
///   keys: ["setmetatable"],
///   args: [table, metatable]
/// )
/// let assert Ok(state) = glua.set(state:, keys: ["my_table"], value: table)
///
/// let code =
///   "my_table.my_key = 'this should not be the value'; return my_table.my_key"
///
/// glua.eval(state:, code:, using: decode.string)
/// // -> Error(glua.LuaRuntimeException(glua.ErrorCall([
///           "attempt to update a read-only table"
///       ]), _)
/// ```
///
/// > **Note**: This function should only be used to allocate memory for tables or userdata values.
/// > For the rest of types that can be encoded, like strings, integers, floats or booleans, this function does nothing.
@external(erlang, "glua_ffi", "alloc")
pub fn alloc(lua: Lua, v: Value) -> #(Lua, Value)

/// Creates a new Lua VM instance
@external(erlang, "luerl", "init")
pub fn new() -> Lua

/// List of Lua modules and functions that will be sandboxed by default
pub const default_sandbox = [
  ["io"],
  ["file"],
  ["os", "execute"],
  ["os", "exit"],
  ["os", "getenv"],
  ["os", "remove"],
  ["os", "rename"],
  ["os", "tmpname"],
  ["package"],
  ["load"],
  ["loadfile"],
  ["require"],
  ["dofile"],
  ["loadstring"],
]

/// Creates a new Lua VM instance with sensible modules and functions sandboxed.
///
/// Check `glua.default_sandbox` to see what modules and functions will be sandboxed.
///
/// This function accepts a list of paths to Lua values that will be excluded from being sandboxed,
/// so needed modules or functions can be enabled while keeping sandboxed the rest.
/// In case you want to sandbox more Lua values, pass to `glua.sandbox` the returned Lua state.
pub fn new_sandboxed(
  allow excluded: List(List(String)),
) -> Result(Lua, LuaError) {
  list_substraction(default_sandbox, excluded)
  |> list.try_fold(from: new(), with: sandbox)
}

@external(erlang, "erlang", "--")
fn list_substraction(a: List(a), b: List(a)) -> List(a)

/// Swaps out the value at `keys` with a function that causes a Lua error when called.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(lua) = glua.new() |> glua.sandbox(["os"], ["execute"])
/// let assert Error(glua.LuaRuntimeException(exception, _)) = glua.eval(
///   state: lua,
///   code: "os.execute(\"rm -f important_file\"); return 0",
///   using: decode.int
/// )
/// // 'important_file' was not deleted
/// assert exception == glua.ErrorCall(["os.execute is sandboxed"])
/// ```
pub fn sandbox(state lua: Lua, keys keys: List(String)) -> Result(Lua, LuaError) {
  let msg = string.join(keys, with: ".") <> " is sandboxed"
  set(lua, ["_G", ..keys], sandbox_fun(msg))
}

@external(erlang, "glua_ffi", "sandbox_fun")
fn sandbox_fun(msg: String) -> Value

/// Gets a value in the Lua environment.
///
/// ## Examples
///
/// ```gleam
/// glua.get(state: glua.new(), keys: ["_VERSION"], using: decode.string)
/// // -> Ok("Lua 5.3")
/// ```
///
/// ```gleam
/// let #(lua, encoded) = glua.new() |> glua.bool(True)
/// let assert Ok(lua) = glua.set(
///   state: lua,
///   keys: ["my_table", "my_value"],
///   value: encoded
/// )
///
/// glua.get(
///   state: lua,
///   keys: ["my_table", "my_value"],
///   using: decode.bool
/// )
/// // -> Ok(True)
/// ```
///
/// ```gleam
/// glua.get(state: glua.new(), keys: ["non_existent"], using: decode.string)
/// // -> Error(glua.KeyNotFound)
/// ```
pub fn get(
  state lua: Lua,
  keys keys: List(String),
  using decoder: decode.Decoder(a),
) -> Result(a, LuaError) {
  use value <- result.try(do_get(lua, keys))

  use decoded <- result.try(
    decode.run(value, decoder) |> result.map_error(UnexpectedResultType),
  )

  Ok(decoded)
}

/// Gets a private value that is not exposed to the Lua runtime.
///
/// ## Examples
///
/// ```gleam
/// assert glua.new()
///      |> glua.set_private("private_value", "secret_value")
///      |> glua.get_private("private_value", decode.string)
///   == Ok("secret_value")
/// ```
pub fn get_private(
  state lua: Lua,
  key key: String,
  using decoder: decode.Decoder(a),
) -> Result(a, LuaError) {
  use value <- result.try(do_get_private(lua, key))
  use decoded <- result.try(
    decode.run(value, decoder) |> result.map_error(UnexpectedResultType),
  )

  Ok(decoded)
}

/// Same as `glua.get`, but returns a reference to the value instead of decoding it
pub fn ref_get(
  state lua: Lua,
  keys keys: List(String),
) -> Result(ValueRef, LuaError) {
  do_ref_get(lua, keys)
}

/// Sets a value in the Lua environment.
///
/// All nested keys will be created as intermediate tables.
///
/// If successfull, this function will return the updated Lua state
/// and the setted value will be available in Lua scripts.
///
/// ## Examples
///
/// ```gleam
/// let #(lua, encoded) = glua.new() |> glua.int(10)
/// let assert Ok(lua) = glua.set(
///   state: lua,
///   keys: ["my_number"],
///   value: encoded
/// )
///
/// glua.get(state: lua, keys: ["my_number"], using: decode.int)
/// // -> Ok(10)
/// ```
///
/// ```gleam
/// let emails = ["jhondoe@example.com", "lucy@example.com"]
/// let #(lua, encoded) = glua.new() |> glua.list(glua.string, emails)
/// let assert Ok(lua) = glua.set(
///   state: lua,
///   keys: ["info", "emails"],
///   value: encoded
/// )
///
/// let assert Ok(#(_, results)) = glua.eval(
///   state: lua,
///   code: "return info.emails",
///   using: decode.string
/// )
///
/// assert results == emails
/// ```
pub fn set(
  state lua: Lua,
  keys keys: List(String),
  value val: Value,
) -> Result(Lua, LuaError) {
  let state = {
    use acc, key <- list.try_fold(keys, #([], lua))
    let #(keys, lua) = acc
    let keys = list.append(keys, [key])
    case do_ref_get(lua, keys) {
      Ok(_) -> Ok(#(keys, lua))

      Error(KeyNotFound) -> {
        let #(lua, tbl) = alloc(lua, table([]))
        do_set(lua, keys, tbl)
        |> result.map(fn(lua) { #(keys, lua) })
      }

      Error(e) -> Error(e)
    }
  }

  use #(keys, lua) <- result.try(state)
  do_set(lua, keys, val)
}

/// Sets a value that is not exposed to the Lua runtime and can only be accessed from Gleam.
///
/// ## Examples
/// ```gleam
/// assert glua.new()
///        |> glua.set("secret_value", "private_value")
///        |> glua.get("secret_value")
///   == Ok("secret_value")
/// ```
pub fn set_private(state lua: Lua, key key: String, value value: a) -> Lua {
  do_set_private(key, value, lua)
}

/// Sets a group of values under a particular table in the Lua environment.
pub fn set_api(
  lua: Lua,
  keys: List(String),
  values: List(#(String, Value)),
) -> Result(Lua, LuaError) {
  use state, #(key, val) <- list.try_fold(values, lua)
  set(state, list.append(keys, [key]), val)
}

/// Sets the paths where the Lua runtime will look when requiring other Lua files.
///
/// > **Warning**: This function will not work properly if `["package"]` or `["require"]` are sandboxed
/// > in the provided Lua state. If you constructed the Lua state using `glua.new_sandboxed`,
/// > remember to allow the required values by passing `[["package"], ["require"]]` to `glua.new_sandboxed`.
///
/// ## Examples
///
/// ```gleam
/// let my_scripts_paths = ["app/scripts/lua/?.lua"]
/// let assert Ok(state) = glua.set_lua_paths(
///   state: glua.new(),
///   paths: my_scripts_paths
/// )
///
/// let assert Ok(#(_, [result])) = glua.eval(
///   state:,
///   code: "local my_math = require 'my_script'; return my_math.square(3)"
///   using: decode.int
/// )
///
/// assert result = 9
/// ```
pub fn set_lua_paths(
  state lua: Lua,
  paths paths: List(String),
) -> Result(Lua, LuaError) {
  let paths = string.join(paths, with: ";") |> string
  set(lua, ["package", "path"], paths)
}

@external(erlang, "glua_ffi", "get_table_keys_dec")
fn do_get(lua: Lua, keys: List(String)) -> Result(dynamic.Dynamic, LuaError)

@external(erlang, "glua_ffi", "get_private")
fn do_get_private(lua: Lua, key: String) -> Result(dynamic.Dynamic, LuaError)

@external(erlang, "glua_ffi", "get_table_keys")
fn do_ref_get(lua: Lua, keys: List(String)) -> Result(ValueRef, LuaError)

@external(erlang, "glua_ffi", "set_table_keys")
fn do_set(lua: Lua, keys: List(String), val: a) -> Result(Lua, LuaError)

@external(erlang, "luerl", "put_private")
fn do_set_private(key: String, value: a, lua: Lua) -> Lua

/// Remove a private value that is not exposed to the Lua runtime. 
///
/// ## Examples
///
/// ```gleam
/// let lua = glua.set_private(glua.new(), "my_value", "will_be_removed"
/// assert glua.get(lua, "my_value", decode.string) == Ok("will_be_removed")
///
/// assert glua.delete_private(lua, "my_value")
///        |> glua.get("my_value", decode.string)
///   == Error(glua.KeyNotFound)
/// ```
pub fn delete_private(state lua: Lua, key key: String) -> Lua {
  do_delete_private(key, lua)
}

@external(erlang, "luerl", "delete_private")
fn do_delete_private(key: String, lua: Lua) -> Lua

/// Parses a string of Lua code and returns it as a compiled chunk.
///
/// To eval the returned chunk, use `glua.eval_chunk` or `glua.ref_eval_chunk`.
pub fn load(
  state lua: Lua,
  code code: String,
) -> Result(#(Lua, Chunk), LuaError) {
  do_load(lua, code)
}

@external(erlang, "glua_ffi", "load")
fn do_load(lua: Lua, code: String) -> Result(#(Lua, Chunk), LuaError)

/// Parses a Lua source file and returns it as a compiled chunk.
///
/// To eval the returned chunk, use `glua.eval_chunk` or `glua.ref_eval_chunk`.
pub fn load_file(
  state lua: Lua,
  path path: String,
) -> Result(#(Lua, Chunk), LuaError) {
  do_load_file(lua, path)
}

@external(erlang, "glua_ffi", "load_file")
fn do_load_file(lua: Lua, path: String) -> Result(#(Lua, Chunk), LuaError)

/// Evaluates a string of Lua code.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(#(_, results)) = glua.eval(
///   state: glua.new(),
///   code: "return 1 + 2",
///   using: decode.int
/// )
/// assert results == [3]
/// ```
///
/// ```gleam
/// let my_decoder = decode.one_of(decode.string, or: [
///   decode.int |> decode.map(int.to_string)
/// ])
///
/// let assert Ok(#(_, results)) = glua.eval(
///   state: glua.new(),
///   code: "return 'hello, world!', 10",
///   using: my_decoder
/// )
/// assert results == ["hello, world!", "10"]
/// ```
///
/// ```gleam
/// glua.eval(state: glua.new(), code: "return 1 * ", using: decode.int)
/// // -> Error(glua.LuaCompilerException(
///   messages: ["syntax error before: ", "1"]
/// ))
/// ```
///
/// ```gleam
/// glua.eval(state: glua.new(), code: "return 'Hello, world!'", using: decode.int)
/// // -> Error(glua.UnexpectedResultType(
///   [decode.DecodeError("Int", "String", [])]
/// ))
/// ```
///
/// > **Note**: If you are evaluating the same piece of code multiple times,
/// > instead of calling `glua.eval` repeatly it is recommended to first convert
/// > the code to a chunk by passing it to `glua.load`, and then
/// > evaluate that chunk using `glua.eval_chunk` or `glua.ref_eval_chunk`.
pub fn eval(
  state lua: Lua,
  code code: String,
  using decoder: decode.Decoder(a),
) -> Result(#(Lua, List(a)), LuaError) {
  use #(lua, ret) <- result.try(do_eval(lua, code))
  use decoded <- result.try(
    list.try_map(ret, decode.run(_, decoder))
    |> result.map_error(UnexpectedResultType),
  )

  Ok(#(lua, decoded))
}

@external(erlang, "glua_ffi", "eval_dec")
fn do_eval(
  lua: Lua,
  code: String,
) -> Result(#(Lua, List(dynamic.Dynamic)), LuaError)

/// Same as `glua.eval`, but returns references to the values instead of decode them
pub fn ref_eval(
  state lua: Lua,
  code code: String,
) -> Result(#(Lua, List(ValueRef)), LuaError) {
  do_ref_eval(lua, code)
}

@external(erlang, "glua_ffi", "eval")
fn do_ref_eval(
  lua: Lua,
  code: String,
) -> Result(#(Lua, List(ValueRef)), LuaError)

/// Evaluates a compiled chunk of Lua code.
///
/// ## Examples
/// ```gleam
/// let assert Ok(#(lua, chunk)) = glua.load(
///   state: glua.new(),
///   code: "return 'hello, world!'"
/// )
///
/// let assert Ok(#(_, results)) = glua.eval_chunk(
///   state: lua,
///   chunk:,
///   using: decode.string
/// )
///
/// assert results == ["hello, world!"]
/// ```
pub fn eval_chunk(
  state lua: Lua,
  chunk chunk: Chunk,
  using decoder: decode.Decoder(a),
) -> Result(#(Lua, List(a)), LuaError) {
  use #(lua, ret) <- result.try(do_eval_chunk(lua, chunk))
  use decoded <- result.try(
    list.try_map(ret, decode.run(_, decoder))
    |> result.map_error(UnexpectedResultType),
  )

  Ok(#(lua, decoded))
}

@external(erlang, "glua_ffi", "eval_chunk_dec")
fn do_eval_chunk(
  lua: Lua,
  chunk: Chunk,
) -> Result(#(Lua, List(dynamic.Dynamic)), LuaError)

/// Same as `glua.eval_chunk`, but returns references to the values instead of decode them
pub fn ref_eval_chunk(
  state lua: Lua,
  chunk chunk: Chunk,
) -> Result(#(Lua, List(ValueRef)), LuaError) {
  do_ref_eval_chunk(lua, chunk)
}

@external(erlang, "glua_ffi", "eval_chunk")
fn do_ref_eval_chunk(
  lua: Lua,
  chunk: Chunk,
) -> Result(#(Lua, List(ValueRef)), LuaError)

/// Evaluates a Lua source file.
///
/// ## Examples
/// ```gleam
/// let assert Ok(#(_, results)) = glua.eval_file(
///   state: glua.new(),
///   path: "path/to/hello.lua",
///   using: decode.string
/// )
///
/// assert results == ["hello, world!"]
/// ```
pub fn eval_file(
  state lua: Lua,
  path path: String,
  using decoder: decode.Decoder(a),
) -> Result(#(Lua, List(a)), LuaError) {
  use #(lua, ret) <- result.try(do_eval_file(lua, path))
  use decoded <- result.try(
    list.try_map(ret, decode.run(_, decoder))
    |> result.map_error(UnexpectedResultType),
  )

  Ok(#(lua, decoded))
}

@external(erlang, "glua_ffi", "eval_file_dec")
fn do_eval_file(
  lua: Lua,
  path: String,
) -> Result(#(Lua, List(dynamic.Dynamic)), LuaError)

/// Same as `glua.eval_file`, but returns references to the values instead of decode them.
pub fn ref_eval_file(
  state lua: Lua,
  path path: String,
) -> Result(#(Lua, List(ValueRef)), LuaError) {
  do_ref_eval_file(lua, path)
}

@external(erlang, "glua_ffi", "eval_file")
fn do_ref_eval_file(
  lua: Lua,
  path: String,
) -> Result(#(Lua, List(ValueRef)), LuaError)

/// Calls a Lua function by reference.
///
/// ## Examples
/// ```gleam
/// let assert Ok(#(lua, fun)) = glua.ref_eval(state: glua.new(), code: "return math.sqrt")
///
/// let #(lua, encoded) = glua.int(lua, 81)
/// let assert Ok(#(_, [result])) = glua.call_function(
///   state: lua,
///   ref: fun,
///   args: [encoded],
///   using: decode.int
/// )
///
/// assert result == 9
/// ```
///
/// ```gleam
/// let code = "function fib(n)
///   if n <= 1 then
///     return n
///   else
///     return fib(n - 1) + fib(n - 2)
///   end
/// end
///
/// return fib
/// "
/// let assert Ok(#(lua, fun)) = glua.ref_eval(state: glua.new(), code:)
///
/// let #(lua, encoded) = glua.int(lua, 10)
/// let assert Ok(#(_, [result])) = glua.call_function(
///   state: lua,
///   ref: fun,
///   args: [encoded],
///   using: decode.int
/// )
///
/// assert result == 55 
/// ```
pub fn call_function(
  state lua: Lua,
  ref fun: ValueRef,
  args args: List(Value),
  using decoder: decode.Decoder(a),
) -> Result(#(Lua, List(a)), LuaError) {
  use #(lua, ret) <- result.try(do_call_function(lua, fun, args))
  use decoded <- result.try(
    list.try_map(ret, decode.run(_, decoder))
    |> result.map_error(UnexpectedResultType),
  )

  Ok(#(lua, decoded))
}

@external(erlang, "glua_ffi", "call_function_dec")
fn do_call_function(
  lua: Lua,
  fun: ValueRef,
  args: List(Value),
) -> Result(#(Lua, List(dynamic.Dynamic)), LuaError)

/// Same as `glua.call_function`, but returns references to the values instead of decode them.
pub fn ref_call_function(
  state lua: Lua,
  ref fun: ValueRef,
  args args: List(Value),
) -> Result(#(Lua, List(ValueRef)), LuaError) {
  do_ref_call_function(lua, fun, args)
}

@external(erlang, "glua_ffi", "call_function")
fn do_ref_call_function(
  lua: Lua,
  fun: ValueRef,
  args: List(Value),
) -> Result(#(Lua, List(ValueRef)), LuaError)

/// Gets a reference to the function at `keys`, then inmediatly calls it with the provided `args`.
///
/// This is a shorthand for `glua.ref_get` followed by `glua.call_function`.
///
/// ## Examples
///
/// ```gleam
/// let #(lua, encoded) = glua.new() |> glua.string("hello from gleam!")
/// let assert Ok(#(_, [s])) = glua.call_function_by_name(
///   state: lua,
///   keys: ["string", "upper"],
///   args: [encoded],
///   using: decode.string
/// )
///
/// assert s == "HELLO FROM GLEAM!" 
/// ```
pub fn call_function_by_name(
  state lua: Lua,
  keys keys: List(String),
  args args: List(Value),
  using decoder: decode.Decoder(a),
) -> Result(#(Lua, List(a)), LuaError) {
  use fun <- result.try(ref_get(lua, keys))
  call_function(lua, fun, args, decoder)
}

/// Same as `glua.call_function_by_name`, but it chains `glua.ref_get` with `glua.ref_call_function` instead of `glua.call_function`
pub fn ref_call_function_by_name(
  state lua: Lua,
  keys keys: List(String),
  args args: List(Value),
) -> Result(#(Lua, List(ValueRef)), LuaError) {
  use fun <- result.try(ref_get(lua, keys))
  ref_call_function(lua, fun, args)
}
