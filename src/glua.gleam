//// A library to embed Lua in Gleam programs.
////
//// Gleam wrapper around [Luerl](https://github.com/rvirding/luerl).

import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option
import gleam/pair
import gleam/result
import gleam/string

/// Represents an instance of the Lua VM.
pub type Lua

/// Represents the errors than can happend during the parsing and execution of Lua code
pub type LuaError {
  /// The compilation process of the Lua code failed because of the presence of one or more compile errors.
  LuaCompileFailure(errors: List(LuaCompileError))
  /// The Lua environment threw an exception during code execution.
  LuaRuntimeException(exception: LuaRuntimeExceptionKind, state: Lua)
  /// A certain key was not found in the Lua environment.
  KeyNotFound(key: List(String))
  /// A Lua source file was not found
  FileNotFound(path: String)
  /// The value returned by the Lua environment could not be decoded using the provided decoder.
  UnexpectedResultType(List(decode.DecodeError))
  /// An error that could not be identified.
  UnknownError(error: dynamic.Dynamic)
}

/// Represents a Lua compilation error
pub type LuaCompileError {
  LuaCompileError(line: Int, kind: LuaCompileErrorKind, message: String)
}

/// Represents the kind of a Lua compilation error
pub type LuaCompileErrorKind {
  Parse
  Tokenize
}

/// Represents the kind of exceptions that can happen at runtime during Lua code execution.
pub type LuaRuntimeExceptionKind {
  /// The exception that happens when trying to access an index that does not exists on a table (also happens when indexing non-table values).
  IllegalIndex(index: String, value: String)
  /// The exception that happens when the `error` function is called.
  ErrorCall(message: String, level: option.Option(Int))
  /// The exception that happens when trying to call a function that is not defined.
  UndefinedFunction(value: String)
  /// The exception that happens when trying to call a method that is not defined for an object.
  UndefinedMethod(object: String, method: String)
  /// The exception that happens when an invalid arithmetic operation is performed.
  BadArith(operator: String, args: List(String))
  /// The exception that happens when a function is called with incorrect arguments.
  Badarg(function: String, args: List(dynamic.Dynamic))
  /// The exception that happens when a call to assert is made passing a value that evalues to `false` as the first argument.
  AssertError(message: String)
  /// An exception that could not be identified
  UnknownException
}

/// Turns a `glua.LuaError` value into a human-readable string
///
/// ## Examples
///
/// ```gleam
/// let assert Error(e) = glua.eval(
///   state: glua.new(),
///   code: "if true end",
/// )
///
/// glua.format_error(e)
/// // -> "Lua compile error: \n\nFailed to parse: error on line 1: syntax error before: 'end'"
/// ```
///
/// ```gleam
/// let assert Error(e) = glua.eval(
///   state: glua.new(),
///   code: "local a = 1; local b = true; return a + b",
/// )
///
/// glua.format_error(e)
/// // -> "Lua runtime exception: Bad arithmetic expression: 1 + true"
/// ```
///
/// ```gleam
/// let assert Error(e) = glua.get(
///   state: glua.new(),
///   keys: ["a_value"],
/// )
/// 
/// glua.format_error(e)
/// // -> "Key \"a_value\" not found"
/// ```
///
/// ```gleam
/// let assert Error(e) = glua.eval_file(
///   state: glua.new(),
///   path: "my_lua_file.lua",
/// )
///
/// glua.format_error(e)
/// // -> "Lua source file \"my_lua_file.lua\" not found"
/// ```
///
/// ```gleam
/// let assert Ok(#(state, [ref])) = glua.eval(
///   state: glua.new(),
///   code: "return 1 + 1",
/// )
/// let assert Error(e) = glua.deference(state:, ref:, using: decode.string)
///
/// glua.format_error(e)
/// // -> "Expected String, but found Int"
/// ```
pub fn format_error(error: LuaError) -> String {
  case error {
    LuaCompileFailure(errors) ->
      "Lua compile error: "
      <> "\n\n"
      <> string.join(list.map(errors, format_compile_error), with: "\n")
    LuaRuntimeException(exception, state) -> {
      let base = "Lua runtime exception: " <> format_exception(exception)
      let stacktrace = get_stacktrace(state)

      case stacktrace {
        "" -> base
        stacktrace -> base <> "\n\n" <> stacktrace
      }
    }
    KeyNotFound(path) ->
      "Key " <> "\"" <> string.join(path, with: ".") <> "\"" <> " not found"
    FileNotFound(path) ->
      "Lua source file " <> "\"" <> path <> "\"" <> " not found"
    UnexpectedResultType(decode_errors) ->
      list.map(decode_errors, format_decode_error) |> string.join(with: "\n")
    UnknownError(error) -> "Unknown error: " <> format_unknown_error(error)
  }
}

fn format_compile_error(error: LuaCompileError) -> String {
  let kind = case error.kind {
    Parse -> "parse"
    Tokenize -> "tokenize"
  }

  "Failed to "
  <> kind
  <> ": error on line "
  <> int.to_string(error.line)
  <> ": "
  <> error.message
}

fn format_exception(exception: LuaRuntimeExceptionKind) -> String {
  case exception {
    IllegalIndex(index, value) ->
      "Invalid index "
      <> "\""
      <> index
      <> "\""
      <> " at object "
      <> "\""
      <> value
      <> "\""
    ErrorCall(msg, level) -> {
      let base = "Error call: " <> msg

      case level {
        option.Some(level) -> base <> " at level " <> int.to_string(level)
        option.None -> base
      }
    }

    UndefinedFunction(fun) -> "Undefined function: " <> fun
    UndefinedMethod(obj, method) ->
      "Undefined method "
      <> "\""
      <> method
      <> "\""
      <> " for object: "
      <> "\""
      <> obj
      <> "\""
    BadArith(operator, args) ->
      "Bad arithmetic expression: "
      <> string.join(args, with: " " <> operator <> " ")

    Badarg(function, args) ->
      "Bad argument "
      <> string.join(list.map(args, format_lua_value), with: ", ")
      <> " for function "
      <> function
    AssertError(msg) -> "Assertion failed with message: " <> msg
    UnknownException -> "Unknown exception"
  }
}

@external(erlang, "glua_ffi", "get_stacktrace")
fn get_stacktrace(state: Lua) -> String

fn format_decode_error(error: decode.DecodeError) -> String {
  let base = "Expected " <> error.expected <> ", but found " <> error.found

  case error.path {
    [] -> base
    path -> base <> " at " <> string.join(path, with: ".")
  }
}

@external(erlang, "luerl_lib", "format_value")
fn format_lua_value(v: anything) -> String

@external(erlang, "luerl_lib", "format_error")
fn format_unknown_error(error: dynamic.Dynamic) -> String

/// The exception that happens when a functi
/// Represents a chunk of Lua code that is already loaded into the Lua VM
pub type Chunk

/// Represents a value that can be passed to the Lua environment.
pub type Value

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

pub fn table(lua: Lua, values: List(#(Value, Value))) -> #(Lua, Value) {
  do_table(values, lua) |> pair.swap
}

@external(erlang, "luerl_heap", "alloc_table")
fn do_table(values: List(#(Value, Value)), lua: Lua) -> #(Value, Lua)

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
  do_function(f)
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
/// let #(state, userdata) = glua.userdata(state, User(name: "Jhon Doe", is_admin: False))
/// let assert Ok(state) = glua.set(
///   state:,
///   keys: ["a_user"],
///   value: userdata
/// )
///
/// let assert Ok(#(state, [ref])) = glua.eval(state:, code: "return a_user")
/// glua.deference(state:, ref:, using: user_decoder)
/// // -> Ok(User("Jhon Doe", False))
/// ```
///
/// ```gleam
/// pub type Person {
///   Person(name: String, email: String)
/// }
///
/// let state = glua.new()
/// let #(state, userdata) = glua.userdata(state, Person(name: "Lucy", email: "lucy@example.com"))
/// let assert Ok(lua) = glua.set(
///   state:,
///   keys: ["lucy"],
///   value: userdata
/// )
///
/// let assert Error(glua.LuaRuntimeException(glua.IllegalIndex(_), _)) =
///   glua.eval(state:, code: "return lucy.email")
/// ```
pub fn userdata(lua: Lua, v: anything) -> #(Lua, Value) {
  do_userdata(v, lua) |> pair.swap
}

@external(erlang, "luerl_heap", "alloc_userdata")
fn do_userdata(v: anything, lua: Lua) -> #(Value, Lua)

@external(erlang, "glua_ffi", "wrap_fun")
fn do_function(
  fun: fn(Lua, List(dynamic.Dynamic)) -> #(Lua, List(Value)),
) -> Value

/// Converts a reference to a Lua value into type-safe Gleam data using the provided decoder.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(#(state, [ref])) = glua.eval(
///   state: glua.new(),
///   code: "return 'Hello from Lua!'"
/// )
/// glua.deference(state:, ref:, using: decode.string)
/// // -> Ok("Hello from Lua!")
/// ```
///
/// ```gleam
/// let assert Ok(#(state, [ref1, ref2])) = glua.eval(
///   state: glua.new(),
///   code: "return 1, true"
/// )
/// assert glua.deference(state:, ref: ref1, using: decode.int) == Ok(1)
/// assert glua.deference(state:, ref: ref2, using: decode.bool) == Ok(True)
/// ```
pub fn deference(
  state lua: Lua,
  ref ref: Value,
  using decoder: decode.Decoder(a),
) -> Result(a, LuaError) {
  do_deference(lua, ref)
  |> decode.run(decoder)
  |> result.map_error(UnexpectedResultType)
}

@external(erlang, "glua_ffi", "deference")
fn do_deference(lua: Lua, ref: Value) -> dynamic.Dynamic

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
/// let state = glua.new()
/// let assert Ok(ref) = glua.get(state:, keys: ["_VERSION"])
/// glua.deference(state:, ref:, using: decode.string)
/// // -> Ok("Lua 5.3")
/// ```
///
/// ```gleam
/// let assert Ok(state) = glua.set(
///   state: glua.new(),
///   keys: ["my_table", "my_value"],
///   value: glua.bool(True)
/// )
///
/// let assert Ok(ref) = glua.get(state:, keys: ["my_table", "my_value"])
/// glua.deference(state:, ref:, using: decode.bool)
/// // -> Ok(True)
/// ```
///
/// ```gleam
/// glua.get(state: glua.new(), keys: ["non_existent"])
/// // -> Error(glua.KeyNotFound(["non_existent"]))
/// ```
@external(erlang, "glua_ffi", "get_table_keys")
pub fn get(state lua: Lua, keys keys: List(String)) -> Result(Value, LuaError)

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
  decode.run(value, decoder) |> result.map_error(UnexpectedResultType)
}

@external(erlang, "glua_ffi", "get_private")
fn do_get_private(lua: Lua, key: String) -> Result(dynamic.Dynamic, LuaError)

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
/// let assert Ok(state) = glua.set(
///   state: glua.new(),
///   keys: ["my_number"],
///   value: glua.int(10)
/// )
///
/// let assert Ok(ref) = glua.get(state: lua, keys: ["my_number"])
/// glua.deference(state:, ref:, using: decode.int)
/// // -> Ok(10)
/// ```
///
/// ```gleam
/// let emails = ["jhondoe@example.com", "lucy@example.com"]
/// let #(state, encoded) = glua.table(
///   glua.new(),
///   list.index_map(emails, fn(email, i) { #(glua.int(i + 1), glua.string(email)) })
/// )
/// let assert Ok(state) = glua.set(
///   state:,
///   keys: ["info", "emails"],
///   value: encoded
/// )
///
/// let assert Ok(#(state, [ref])) = glua.eval(state:, code: "return info.emails")
/// let assert Ok(results) =
///   glua.deference(state:, ref:, using: decode.dict(decode.int, decode.string))
///   |> result.map(dict.values)
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
    case get(lua, keys) {
      Ok(_) -> Ok(#(keys, lua))

      Error(KeyNotFound(_)) -> {
        let #(tbl, lua) = do_table([], lua)
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
/// let assert Ok(#(state, [ref])) = glua.eval(
///   state:,
///   code: "local my_math = require 'my_script'; return my_math.square(3)"
/// )
/// glua.deference(state:, ref:, using: decode.int)
/// // -> Ok(9)
/// ```
pub fn set_lua_paths(
  state lua: Lua,
  paths paths: List(String),
) -> Result(Lua, LuaError) {
  let paths = string.join(paths, with: ";") |> string
  set(lua, ["package", "path"], paths)
}

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
///   == Error(glua.KeyNotFound(["my_value"]))
/// ```
pub fn delete_private(state lua: Lua, key key: String) -> Lua {
  do_delete_private(key, lua)
}

@external(erlang, "luerl", "delete_private")
fn do_delete_private(key: String, lua: Lua) -> Lua

/// Parses a string of Lua code and returns it as a compiled chunk.
///
/// To eval the returned chunk, use `glua.eval_chunk`.
@external(erlang, "glua_ffi", "load")
pub fn load(
  state lua: Lua,
  code code: String,
) -> Result(#(Lua, Chunk), LuaError)

/// Parses a Lua source file and returns it as a compiled chunk.
///
/// To eval the returned chunk, use `glua.eval_chunk`.
@external(erlang, "glua_ffi", "load_file")
pub fn load_file(
  state lua: Lua,
  path path: String,
) -> Result(#(Lua, Chunk), LuaError)

/// Evaluates a string of Lua code.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(#(state, [ref])) = glua.eval(
///   state: glua.new(),
///   code: "return 1 + 2",
/// )
/// glua.deference(state:, ref:, using: decode.int)
/// // -> Ok(3)
/// ```
///
/// ```gleam
/// let assert Ok(#(state, [ref1, ref2])) = glua.eval(
///   state: glua.new(),
///   code: "return 'hello, world!', 10",
/// )
/// assert glua.deference(state:, ref: ref1, using: decode.string) == "hello, world!"
/// assert glua.deference(state:, ref: ref2, using: decode.int) == 10
/// ```
///
/// ```gleam
/// glua.eval(state: glua.new(), code: "return 1 * ")
/// // -> Error(glua.LuaCompilerException(
///   messages: ["syntax error before: ", "1"]
/// ))
/// ```
///
/// > **Note**: If you are evaluating the same piece of code multiple times,
/// > instead of calling `glua.eval` repeatly it is recommended to first convert
/// > the code to a chunk by passing it to `glua.load`, and then
/// > evaluate that chunk using `glua.eval_chunk`.
@external(erlang, "glua_ffi", "eval")
pub fn eval(
  state lua: Lua,
  code code: String,
) -> Result(#(Lua, List(Value)), LuaError)

/// Evaluates a compiled chunk of Lua code.
///
/// ## Examples
/// ```gleam
/// let assert Ok(#(lua, chunk)) = glua.load(
///   state: glua.new(),
///   code: "return 'hello, world!'"
/// )
///
/// let assert Ok(#(state, [ref])) = glua.eval_chunk(
///   state: lua,
///   chunk:,
/// )
/// glua.deference(state:, ref:, using: decode.string)
/// // -> Ok("hello, world!")
/// ```
@external(erlang, "glua_ffi", "eval_chunk")
pub fn eval_chunk(
  state lua: Lua,
  chunk chunk: Chunk,
) -> Result(#(Lua, List(Value)), LuaError)

/// Evaluates a Lua source file.
///
/// ## Examples
/// ```gleam
/// let assert Ok(#(state, [ref])) = glua.eval_file(
///   state: glua.new(),
///   path: "path/to/hello.lua",
/// )
/// glua.deference(state:, ref:, using: decode.string)
/// Ok("hello, world!")
/// ```
///
/// ```gleam
/// glua.eval_file(
///   state: glua.new(),
///   path: "path/to/non/existent/file",
/// )
/// //-> Error(glua.FileNotFound(["path/to/non/existent/file"]))
/// ```
@external(erlang, "glua_ffi", "eval_file")
pub fn eval_file(
  state lua: Lua,
  path path: String,
) -> Result(#(Lua, List(Value)), LuaError)

/// Calls a Lua function by reference.
///
/// ## Examples
/// ```gleam
/// let assert Ok(#(state, [fun])) = glua.eval(state: glua.new(), code: "return math.sqrt")
/// let assert Ok(#(state, [ref])) = glua.call_function(
///   state:,
///   ref: fun,
///   args: [glua.int(81)],
/// )
/// glua.deference(state:, ref:, using: decode.int)
/// // -> Ok(9)
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
/// let assert Ok(#(state, [fun])) = glua.eval(state: glua.new(), code:)
/// let assert Ok(#(state), [ref])) = glua.call_function(
///   state: lua,
///   ref: fun,
///   args: [glua.int(10)],
/// )
/// glua.deference(state:, ref:, using: decode.int)
/// // -> Ok(55)
/// ```
@external(erlang, "glua_ffi", "call_function")
pub fn call_function(
  state lua: Lua,
  ref fun: Value,
  args args: List(Value),
) -> Result(#(Lua, List(Value)), LuaError)

/// Gets a reference to the function at `keys`, then inmediatly calls it with the provided `args`.
///
/// This is a shorthand for `glua.get` followed by `glua.call_function`.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(#(state, [ref])) = glua.call_function_by_name(
///   state: glua.new(),
///   keys: ["string", "upper"],
///   args: [glua.string("hello from Gleam!")],
/// )
/// glua.deference(state:, ref:, using: decode.string)
/// // -> Ok(HELLO FROM GLEAM!")
/// ```
pub fn call_function_by_name(
  state lua: Lua,
  keys keys: List(String),
  args args: List(Value),
) -> Result(#(Lua, List(Value)), LuaError) {
  use fun <- result.try(get(lua, keys))
  call_function(lua, fun, args)
}
