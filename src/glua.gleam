//// A library to embed Lua in Gleam programs.
////
//// Gleam wrapper around [Luerl](https://github.com/rvirding/luerl).

import gleam/dynamic
import gleam/dynamic/decode
import gleam/list
import gleam/pair
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

pub opaque type Operation(a) {
  Operation(function: fn(Lua) -> Result(#(Lua, a), LuaError))
}

pub fn do(state: Lua, op: Operation(a)) -> Result(a, LuaError) {
  // drop the updated state by design
  op.function(state) |> result.map(pair.second)
}

pub fn chain(op: Operation(a), next: fn(a) -> Operation(b)) -> Operation(b) {
  Operation(fn(state: Lua) {
    use #(new_state, out) <- result.try(op.function(state))
    next(out).function(new_state)
  })
}

pub fn map(op: Operation(a), next: fn(a) -> b) -> Operation(b) {
  Operation(fn(state: Lua) {
    result.map(op.function(state), pair.map_second(_, next))
  })
}

pub fn nil() -> Operation(Value) {
  Operation(fn(state: Lua) { encode(state, Nil) })
}

pub fn string(v: String) -> Operation(Value) {
  Operation(fn(state: Lua) { encode(state, v) })
}

pub fn bool(v: Bool) -> Operation(Value) {
  Operation(fn(state: Lua) { encode(state, v) })
}

pub fn int(v: Int) -> Operation(Value) {
  Operation(fn(state: Lua) { encode(state, v) })
}

pub fn float(v: Float) -> Operation(Value) {
  Operation(fn(state: Lua) { encode(state, v) })
}

pub fn table(
  encoders: #(fn(a) -> Operation(Value), fn(b) -> Operation(Value)),
  values: List(#(a, b)),
) -> Operation(Value) {
  let #(key_encoder, value_encoder) = encoders
  Operation(fn(state: Lua) {
    use #(new_state, values) <- result.try(
      list.try_fold(over: values, from: #(state, []), with: fn(acc, pair) {
        let #(state, values) = acc
        use #(st0, k) <- result.try(key_encoder(pair.0).function(state))
        use #(st1, v) <- result.map(value_encoder(pair.1).function(st0))

        #(st1, [#(k, v), ..values])
      }),
    )

    encode(new_state, values)
  })
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
  f: fn(List(dynamic.Dynamic)) -> Operation(List(Value)),
) -> Operation(Value) {
  // wrapper to satisfy luerl's order of arguments and return value
  // TODO: Refactor this to get rid of let assert and handle the error case properly
  let fun = fn(args: List(dynamic.Dynamic), state: Lua) {
    let assert Ok(ret) = f(args).function(state)
    ret |> pair.swap
  }

  Operation(fn(state: Lua) { encode(state, fun) })
}

pub fn list(
  encoder: fn(a) -> Operation(Value),
  values: List(a),
) -> Operation(List(Value)) {
  Operation(fn(state: Lua) {
    list.try_fold(values, #(state, []), fn(acc, val) {
      let #(state, values) = acc
      use #(new_state, val) <- result.map(encoder(val).function(state))
      #(new_state, [val, ..values])
    })
  })
}

@external(erlang, "glua_ffi", "encode")
fn encode(state: Lua, v: anything) -> Result(#(Lua, Value), LuaError)

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
  set(["_G", ..keys], sandbox_fun(msg)).function(lua) |> result.map(pair.first)
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
  keys keys: List(String),
  using decoder: decode.Decoder(a),
) -> Operation(a) {
  Operation(fn(state: Lua) {
    use #(new_state, value) <- result.try(do_get(state, keys))

    use decoded <- result.try(
      decode.run(value, decoder) |> result.map_error(UnexpectedResultType),
    )

    Ok(#(new_state, decoded))
  })
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
  key key: String,
  using decoder: decode.Decoder(a),
) -> Operation(a) {
  Operation(fn(state: Lua) {
    use #(new_state, value) <- result.try(do_get_private(state, key))
    use decoded <- result.try(
      decode.run(value, decoder) |> result.map_error(UnexpectedResultType),
    )

    Ok(#(new_state, decoded))
  })
}

/// Same as `glua.get`, but returns a reference to the value instead of decoding it
pub fn ref_get(keys keys: List(String)) -> Operation(ValueRef) {
  Operation(fn(state: Lua) { do_ref_get(state, keys) })
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
pub fn set(keys keys: List(String), value val: Value) -> Operation(Value) {
  Operation(fn(state: Lua) {
    let new_state = {
      use acc, key <- list.try_fold(keys, #([], state))
      let #(keys, lua) = acc
      let keys = list.append(keys, [key])
      case do_ref_get(lua, keys) {
        Ok(_) -> Ok(#(keys, lua))

        Error(KeyNotFound) -> {
          let #(tbl, lua) = alloc_table([], lua)
          do_set(lua, keys, tbl)
          |> result.map(fn(state) { #(keys, state) })
        }

        Error(e) -> Error(e)
      }
    }

    use #(keys, state) <- result.try(new_state)
    use new_state <- result.try(do_set(state, keys, val))
    Ok(#(new_state, val))
  })
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
pub fn set_private(key key: String, value value: a) -> Operation(a) {
  Operation(fn(state: Lua) {
    let new_state = do_set_private(key, value, state)
    Ok(#(new_state, value))
  })
}

/// Sets a group of values under a particular table in the Lua environment.
pub fn set_api(
  keys: List(String),
  values: List(#(String, Value)),
) -> Operation(List(#(String, Value))) {
  Operation(fn(state: Lua) {
    use new_state <- result.try(
      list.try_fold(values, state, fn(state, pair) {
        let #(key, val) = pair
        set(list.append(keys, [key]), val).function(state)
        |> result.map(pair.first)
      }),
    )

    Ok(#(new_state, values))
  })
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
pub fn set_lua_paths(paths paths: List(String)) -> Operation(Value) {
  use paths <- chain(string(string.join(paths, with: ";")))
  set(["package", "path"], paths)
}

@external(erlang, "luerl", "decode_list")
fn decode_list(keys: List(a), lua: Lua) -> List(dynamic.Dynamic)

@external(erlang, "luerl_emul", "alloc_table")
fn alloc_table(content: List(a), lua: Lua) -> #(a, Lua)

@external(erlang, "glua_ffi", "get_table_keys_dec")
fn do_get(
  lua: Lua,
  keys: List(String),
) -> Result(#(Lua, dynamic.Dynamic), LuaError)

@external(erlang, "glua_ffi", "get_private")
fn do_get_private(
  lua: Lua,
  key: String,
) -> Result(#(Lua, dynamic.Dynamic), LuaError)

@external(erlang, "glua_ffi", "get_table_keys")
fn do_ref_get(
  lua: Lua,
  keys: List(String),
) -> Result(#(Lua, ValueRef), LuaError)

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
pub fn delete_private(key key: String) -> Operation(Nil) {
  Operation(fn(state: Lua) { Ok(#(do_delete_private(key, state), Nil)) })
}

@external(erlang, "luerl", "delete_private")
fn do_delete_private(key: String, lua: Lua) -> Lua

/// Parses a string of Lua code and returns it as a compiled chunk.
///
/// To eval the returned chunk, use `glua.eval_chunk` or `glua.ref_eval_chunk`.
pub fn load(code code: String) -> Operation(Chunk) {
  Operation(fn(state: Lua) { do_load(state, code) })
}

@external(erlang, "glua_ffi", "load")
fn do_load(lua: Lua, code: String) -> Result(#(Lua, Chunk), LuaError)

/// Parses a Lua source file and returns it as a compiled chunk.
///
/// To eval the returned chunk, use `glua.eval_chunk` or `glua.ref_eval_chunk`.
pub fn load_file(path path: String) -> Operation(Chunk) {
  Operation(fn(state: Lua) { do_load_file(state, path) })
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
  code code: String,
  using decoder: decode.Decoder(a),
) -> Operation(List(a)) {
  Operation(fn(state: Lua) {
    use #(new_state, ret) <- result.try(do_eval(state, code))
    use decoded <- result.try(
      list.try_map(ret, decode.run(_, decoder))
      |> result.map_error(UnexpectedResultType),
    )

    Ok(#(new_state, decoded))
  })
}

@external(erlang, "glua_ffi", "eval_dec")
fn do_eval(
  lua: Lua,
  code: String,
) -> Result(#(Lua, List(dynamic.Dynamic)), LuaError)

/// Same as `glua.eval`, but returns references to the values instead of decode them
pub fn ref_eval(code code: String) -> Operation(List(ValueRef)) {
  Operation(function: fn(state: Lua) { do_ref_eval(state, code) })
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
  chunk chunk: Chunk,
  using decoder: decode.Decoder(a),
) -> Operation(List(a)) {
  Operation(fn(state: Lua) {
    use #(new_state, ret) <- result.try(do_eval_chunk(state, chunk))
    use decoded <- result.try(
      list.try_map(ret, decode.run(_, decoder))
      |> result.map_error(UnexpectedResultType),
    )

    Ok(#(new_state, decoded))
  })
}

@external(erlang, "glua_ffi", "eval_chunk_dec")
fn do_eval_chunk(
  lua: Lua,
  chunk: Chunk,
) -> Result(#(Lua, List(dynamic.Dynamic)), LuaError)

/// Same as `glua.eval_chunk`, but returns references to the values instead of decode them
pub fn ref_eval_chunk(chunk chunk: Chunk) -> Operation(List(ValueRef)) {
  Operation(fn(state: Lua) { do_ref_eval_chunk(state, chunk) })
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
  path path: String,
  using decoder: decode.Decoder(a),
) -> Operation(List(a)) {
  Operation(fn(state: Lua) {
    use #(new_state, ret) <- result.try(do_eval_file(state, path))
    use decoded <- result.try(
      list.try_map(ret, decode.run(_, decoder))
      |> result.map_error(UnexpectedResultType),
    )

    Ok(#(new_state, decoded))
  })
}

@external(erlang, "glua_ffi", "eval_file_dec")
fn do_eval_file(
  lua: Lua,
  path: String,
) -> Result(#(Lua, List(dynamic.Dynamic)), LuaError)

/// Same as `glua.eval_file`, but returns references to the values instead of decode them.
pub fn ref_eval_file(path path: String) -> Operation(List(ValueRef)) {
  Operation(fn(state: Lua) { do_ref_eval_file(state, path) })
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
  ref fun: ValueRef,
  args args: List(Value),
  using decoder: decode.Decoder(a),
) -> Operation(List(a)) {
  Operation(fn(state: Lua) {
    use #(new_state, ret) <- result.try(do_call_function(state, fun, args))
    use decoded <- result.try(
      list.try_map(ret, decode.run(_, decoder))
      |> result.map_error(UnexpectedResultType),
    )

    Ok(#(new_state, decoded))
  })
}

@external(erlang, "glua_ffi", "call_function_dec")
fn do_call_function(
  lua: Lua,
  fun: ValueRef,
  args: List(Value),
) -> Result(#(Lua, List(dynamic.Dynamic)), LuaError)

/// Same as `glua.call_function`, but returns references to the values instead of decode them.
pub fn ref_call_function(
  ref fun: ValueRef,
  args args: List(Value),
) -> Operation(List(ValueRef)) {
  Operation(fn(state: Lua) { do_ref_call_function(state, fun, args) })
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
  keys keys: List(String),
  args args: List(Value),
  using decoder: decode.Decoder(a),
) -> Operation(List(a)) {
  use fun <- chain(ref_get(keys))
  call_function(fun, args, decoder)
}

/// Same as `glua.call_function_by_name`, but it chains `glua.ref_get` with `glua.ref_call_function` instead of `glua.call_function`
pub fn ref_call_function_by_name(
  keys keys: List(String),
  args args: List(Value),
) -> Operation(List(ValueRef)) {
  use fun <- chain(ref_get(keys))
  ref_call_function(fun, args)
}
