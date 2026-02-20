//// A library to embed Lua in Gleam programs.
////
//// Gleam wrapper around [Luerl](https://github.com/rvirding/luerl).

import gleam/bool
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
pub type LuaError(error) {
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
  /// An app-defined error
  CustomError(error: error)
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
/// let assert Error(e) = glua.run(glua.new(), glua.eval(
///   code: "if true end",
/// ))
///
/// glua.format_error(e)
/// // -> "Lua compile error: \n\nFailed to parse: error on line 1: syntax error before: 'end'"
/// ```
///
/// ```gleam
/// let assert Error(e) = glua.run(glua.new(), glua.eval(
///   code: "local a = 1; local b = true; return a + b",
/// ))
///
/// glua.format_error(e)
/// // -> "Lua runtime exception: Bad arithmetic expression: 1 + true"
/// ```
///
/// ```gleam
/// let assert Error(e) = glua.run(glua.new(), glua.get(
///   keys: ["a_value"],
/// ))
/// 
/// glua.format_error(e)
/// // -> "Key \"a_value\" not found"
/// ```
///
/// ```gleam
/// let assert Error(e) = glua.run(glua.new(), glua.eval_file(
///   path: "my_lua_file.lua",
/// ))
///
/// glua.format_error(e)
/// // -> "Lua source file \"my_lua_file.lua\" not found"
/// ```
///
/// ```gleam
/// let assert Error(e) = glua.run(glua.new(), {
///   use ret <- glua.then(glua.eval(
///     code: "return 1 + 1",
///   ))
///   use ref <- glua.try(list.first(ret))
/// 
///   glua.dereference(ref:, using: decode.string)
/// })
///
/// glua.format_error(e)
/// // -> "Expected String, but found Int"
/// ```
pub fn format_error(error: LuaError(e)) -> String {
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
    CustomError(error) -> string.inspect(error)
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

/// Represents an action that can be run within a Lua state and potentially mutates that state.
///
/// `Action`s are how we interact with a Lua VM and thus many functions in this library
/// returns an `Action` when invoked. It is important to note that the execution of any `Action` is defered until
/// you pass it to `glua.run`:
///
/// ```gleam
/// // no Lua code has been evaluated or even parsed,
/// // we're just creating an `Action`
/// let action = glua.eval("return 1")
///
/// glua.run(glua.new(), action) // now our Lua code is evaluated
/// ```
///
/// `Action`s *can* fail and *can* mutate the Lua state. When calling multiple `Action`s in sequence,
/// you need to make sure each one is executed within the Lua state returned by the previous one since
/// executing an `Action` using outdated state could lead to unexpected behaviour.
///
/// ```gleam
/// let state = glua.new()
/// let result = {
///   use #(new_state, _) <- result.try(
///     glua.run(state, glua.set(keys: ["a_number"], value: glua.int(36)))
///   )
///   use #(new_state, ret) <- result.try(
///     glua.run(state, glua.eval("return math.sqrt(a_number)"))
///   )
///
///   // we know that `math.sqrt` only returns one value
///   let assert [ref] = ret
///
///   glua.run(new_state, glua.dereference(ref:, using: decode.float))
///   |> result.map(pair.second)
/// }
/// result
/// // -> Ok(6.0)
/// ```
///
/// However, `glua` provides function to compose `Actions`s toghether without having to pass
/// the state explicitly. The most common of such functions is `glua.then`, which allows us to take
/// an existing `Action` and use its return value to construct another `Action`.
/// `glua.then` will automatically pass the state returned by the first action to the second one
/// and it will halt the chain as soon as any `Action` fails (like `result.try`).
/// This is equivalent to the above example:
///
/// ```gleam
/// let state = glua.new()
/// let action = {
///   use _ <- glua.then(glua.set(keys: ["a_number"], value: glua.int(36)))
///   use ret <- glua.then(glua.eval(code: "return math.sqrt(a_number)"))
///
///   // we know that `math.sqrt` only returns one value
///   let assert [ref] = ret
///   glua.dereference(ref:, using: decode.float)
/// }
///
/// glua.run(state, action) |> result.map(pair.second)
/// // -> Ok(6.0)
/// ```
///
/// An `Action` takes two types parameters, `return` is the type of the value that the `Action`
/// would return in case it succeeds, and `error` is the type of custom errors that
/// the `Action` could return.
pub opaque type Action(return, error) {
  Action(function: fn(Lua) -> Result(#(Lua, return), LuaError(error)))
}

/// Runs an `Action` within a Lua environment.
///
/// ## Examples
///
/// ```gleam
/// let state = glua.new()
/// glua.run(state, {
///   use ret <- glua.then(glua.eval("return 'Hello from Lua!'"))
///   use ref <- glua.try(list.first(ret))
///   glua.dereference(ref:, using: decode.string)
/// })
/// // -> Ok(#(_state, "Hello from Lua!"))
/// ```
pub fn run(
  state lua: Lua,
  action action: Action(return, error),
) -> Result(#(Lua, return), LuaError(error)) {
  action.function(lua)
}

/// Composes two `Action`s into a single one, by executing the first one and passing its return value
/// to a function that returns another `Action`.
///
/// If the first `Action` returns an `Error` when executed, then the function is not called
/// and the error is returned.
///
/// This function is the most common way to chain together multiple `Action`s.
///
/// ## Examples
///
/// ```gleam
/// let my_value = 1
/// let assert Ok(#(_state, ret)) = glua.run(glua.new(), {
///   use _ <- glua.then(glua.set(keys: ["my_value"], value: glua.int(my_value)))
///   use ref <- glua.then(glua.get(keys: ["my_value"]))
///   glua.dereference(ref:, using: decode.int)
/// })
///
/// assert ret == my_value
/// ```
///
/// ```gleam
/// glua.run(glua.new(), {
///   use ret <- glua.then(glua.eval_file(path: "./my_file.lua"))
///   glua.call_function_by_name(path: ["table", "pack"], args: ret)
/// })
/// // -> Error(glua.FileNotFound("./my_file.lua"))
/// ```
pub fn then(action: Action(a, e), next: fn(a) -> Action(b, e)) -> Action(b, e) {
  use state <- Action
  use #(new, ret) <- result.try(action.function(state))

  next(ret).function(new)
}

/// Transforms the provided result into an `Action` by passing its value to a function
/// that yields an `Action`.
///
/// If the input is an `Error`, then the function is not called and instead a failing `Action`
/// is returned with the original error.
///
/// This is a shorthand for writing a case with `glua.then`:
///
/// ```gleam
/// use fun <- glua.then(glua.get(["string", "reverse"]))
/// use return <- glua.then(glua.call_function(fun:, args: [glua.string("Hello")]))
/// use value <- glua.try(list.first(return))
/// glua.dereference(ref: value, using: decode.string)
/// ```
///
/// as opposed to this:
///
/// ```gleam
/// use fun <- glua.then(glua.get(["string", "reverse"]))
/// use return <- glua.then(glua.call_function(fun, [glua.string("Hello")]))
/// case return {
///   [first] -> glua.dereference(ref: first, using: decode.string)
///   _ -> glua.failure(Nil)
/// }
/// ```
pub fn try(result: Result(a, e), next: fn(a) -> Action(b, e)) -> Action(b, e) {
  case result {
    Ok(ret) -> Action(next(ret).function)
    Error(err) -> failure(err)
  }
}

/// Runs a callback function if the given bool is `False`, otherwise return a failing `Action`
/// using the provided value.
///
/// ## Examples
///
/// ```gleam
/// glua.run(glua.new(), {
///   use ret <- glua.then(glua.eval(code: "local a = 1"))
///   use <- glua.guard(when: ret == [], return: "expected at least one value from Lua")
///
///  glua.fold(ret, glua.dereference(_, using: decode.int))
/// })
/// // -> Error(glua.CustomError("expected at least one value from Lua"))
/// ```
pub fn guard(
  when requirement: Bool,
  return consequence: e,
  otherwise alternative: fn() -> Action(a, e),
) -> Action(a, e) {
  bool.guard(requirement, failure(consequence), alternative)
}

/// Creates an `Action` that always succeeds and returns `value`.
///
/// ## Examples
///
/// ```gleam
/// glua.run(glua.new(), glua.success("my value"))
/// // -> Ok(#(_state, "my_value"))
/// ```
pub fn success(value: a) -> Action(a, e) {
  use state <- Action
  Ok(#(state, value))
}

/// Creates an `Action` that always fails with `glua.CustomError(error)`.
///
/// ## Examples
///
/// ```gleam
/// glua.run(
///   glua.new(),
///   glua.failure("incorrect number of return values")
/// )
/// // -> Error(glua.CustomError("incorrect number of return values"))
/// ```
pub fn failure(error: e) -> Action(a, e) {
  use _ <- Action
  Error(CustomError(error))
}

/// Invokes the Lua `error` function with the provided message.
pub fn error(message: String) -> Action(List(Value), e) {
  call_function_by_name(["error"], [string(message)])
}

/// Invokes the Lua `error` function with the provided message and level.
pub fn error_with_level(message: String, level: Int) -> Action(List(Value), e) {
  call_function_by_name(["error"], [string(message), int(level)])
}

/// Transforms the return value of an `Action` with the provided function.
///
/// If the `Action` returns an `Error` when executed then the function is not called and the
/// error is returned.
///
/// ## Examples
///
/// ```gleam
/// glua.run(glua.new(), {
///   use ref <- glua.then(glua.get(keys: ["_VERSION"]))
///   use version <- glua.map(glua.dereference(ref:, using: decode.string))
///   "glua supports " <> version
/// })
/// // -> Ok(#(_state, "glua supports Lua 5.3"))
/// ```
///
/// ```gleam
/// glua.run(glua.new(), {
///   use n <- glua.map(glua.get(keys: ["my_number"]))
///   n * 2
/// })
/// // -> Error(glua.KeyNotFound(["my_number"]))
/// ```
pub fn map(over action: Action(a, e), with fun: fn(a) -> b) -> Action(b, e) {
  use state <- Action
  action.function(state)
  |> result.map(pair.map_second(_, fun))
}

/// Maps a list of elements into a list of `Action`s by calling a function in each element and then flattens
/// all the `Action`s into a single one.
///
/// ## Examples
///
/// ```gleam
/// let numbers = [9, 16, 25]
/// let keys = ["math", "sqrt"]
/// glua.run(glua.new(), glua.fold(numbers, fn(n) {
///   use ret <- glua.then(glua.call_function_by_name(keys:, args: [glua.int(n)]))
///
///   let assert [ref] = ret
///   glua.dereference(ref:, using: decode.float)
/// }))
/// // -> Ok(#(_state, [3.0, 4.0, 5.0]))
/// ```
pub fn fold(
  over list: List(a),
  with fun: fn(a) -> Action(b, e),
) -> Action(List(b), e) {
  use state <- Action
  list.try_fold(list, #(state, []), fn(acc, e) {
    let #(state, results) = acc
    fun(e).function(state)
    |> result.map(pair.map_second(_, fn(ret) { [ret, ..results] }))
  })
  |> result.map(pair.map_second(_, list.reverse))
}

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

pub fn table(values: List(#(Value, Value))) -> Action(Value, e) {
  use state <- Action
  Ok(do_table(values, state) |> pair.swap)
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

/// Encodes a Gleam function into a Lua function.
///
/// > **Note**: The function to be encoded has to return an `Action` with a `Never` type
/// > as the `error` parameter, meaning that the function cannot invoke `glua.failure` in its body.
/// > If you want to return an error inside that function, you should use `glua.error` or `glua.error_with_code`,
/// > both of which will call the Lua `error` function.
pub fn function(f: fn(List(Value)) -> Action(List(Value), Never)) -> Value {
  do_function(f)
}

// Taken from hexdocs.pm/funtil/1.1.0/funtil.html#Never
/// This type is used to represent a value that can never happen. What does that
/// mean exactly?
///
/// - A `Bool` is a type that has two values: `True` and `False`.
/// - `Nil` is a type that has one value: `Nil`.
/// - `Never` is a type that has zero values: it's impossible to construct!
///
/// This library uses this type to make `glua.failure` impossible to construct in `glua.function`s
/// to encourage using `glua.error` instead since `glua.failure` wouldn't make sense in that case.
pub type Never

pub fn function_decoder() -> decode.Decoder(
  fn(List(Value)) -> Action(List(Value), e),
) {
  decode.new_primitive_decoder("LuaFunction", decode_lua_function)
}

@external(erlang, "glua_ffi", "decode_fun")
fn decode_lua_function(
  v: dynamic.Dynamic,
) -> Result(
  fn(List(Value)) -> Action(List(Value), e),
  fn(List(Value)) -> Action(List(Value), e),
)

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
/// glua.run(glua.new(), {
///   use userdata <- glua.then(userdata(User("Jhon Doe", False)))
///   use _ <- glua.then(glua.set(
///     keys: ["a_user"],
///     value: userdata
///   ))
///   
///   use ret <- glua.then(glua.eval(code: "return a_user"))
///   use ref <- glua.try(list.first(ret))
///
///   glua.dereference(ref:, using: user_decoder)
/// })
/// // -> Ok(#(_state, User("Jhon Doe", False)))
/// ```
///
/// ```gleam
/// pub type Person {
///   Person(name: String, email: String)
/// }
///
/// let assert Error(glua.LuaRuntimeException(glua.IllegalIndex(_), _)) =
///   glua.run(glua.new(), {
///     use userdata <- glua.then(glua.userdata(
///       Person(name: "Lucy", email: "lucy@example.com")
///     ))
///     use _ <- glua.then(glua.set(
///       keys: ["lucy"],
///       value: userdata
///     ))
///
///     glua.eval(code: "return lucy.email")
///   })
/// ```
pub fn userdata(v: anything) -> Action(Value, e) {
  use state <- Action
  Ok(do_userdata(v, state) |> pair.swap)
}

@external(erlang, "luerl_heap", "alloc_userdata")
fn do_userdata(v: anything, lua: Lua) -> #(Value, Lua)

@external(erlang, "glua_ffi", "wrap_fun")
fn do_function(fun: fn(List(Value)) -> Action(List(Value), e)) -> Value

/// Converts a reference to a Lua value into type-safe Gleam data using the provided decoder.
///
/// ## Examples
///
/// ```gleam
/// glua.run(glua.new(), { 
///   use ret <- glua.then(glua.eval(code: "return 'Hello from Lua!'"))
///   use ref <- glua.try(list.first(ret))
///
///   glua.dereference(ref:, using: decode.string)
/// }
/// // -> Ok(#(_state, "Hello from Lua!"))
/// ```
///
/// ```gleam
/// let assert Ok(#(state, [ref1, ref2])) = glua.run(
///   glua.new(),
///   glua.eval(code: "return 1, true")
/// )
///
/// let assert Ok(#(_state, 1)) =
///   glua.run(state, glua.dereference(ref: ref1, using: decode.int))
/// let assert Ok(#(_state, True)) =
///   glua.run(state, glua.dereference(ref: ref2, using: decode.bool))
/// ```
pub fn dereference(
  ref ref: Value,
  using decoder: decode.Decoder(a),
) -> Action(a, e) {
  use state <- Action
  use ret <- result.map(
    do_dereference(state, ref)
    |> decode.run(decoder)
    |> result.map_error(UnexpectedResultType),
  )

  #(state, ret)
}

@external(erlang, "glua_ffi", "dereference")
fn do_dereference(lua: Lua, ref: Value) -> dynamic.Dynamic

pub fn returning(
  action act: Action(Value, e),
  using decoder: decode.Decoder(a),
) -> Action(a, e) {
  use ref <- then(act)
  dereference(ref, decoder)
}

pub fn returning_list(
  action act: Action(List(Value), e),
  using decoder: decode.Decoder(a),
) -> Action(List(a), e) {
  use refs <- then(act)
  fold(refs, dereference(_, decoder))
}

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
) -> Result(Lua, LuaError(e)) {
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
/// let assert Ok(state) = glua.new() |> glua.sandbox(["os"], ["execute"])
/// let assert Error(glua.LuaRuntimeException(exception, _)) =
///   glua.run(state, glua.eval(
///     code: "os.execute(\"rm -f important_file\"); return 0",
///   ))
///
/// // 'important_file' was not deleted
/// assert exception == glua.ErrorCall(["os.execute is sandboxed"])
/// ```
pub fn sandbox(
  state lua: Lua,
  keys keys: List(String),
) -> Result(Lua, LuaError(e)) {
  let msg = string.join(keys, with: ".") <> " is sandboxed"

  set(["_G", ..keys], sandbox_fun(msg)).function(lua)
  |> result.map(pair.first)
}

@external(erlang, "glua_ffi", "sandbox_fun")
fn sandbox_fun(msg: String) -> Value

/// Gets a value in the Lua environment.
///
/// ## Examples
///
/// ```gleam
/// glua.run(glua.new(), {
///   use ref <- glua.then(glua.get(keys: ["_VERSION"]))
///   glua.dereference(ref:, using: decode.string)
/// })
/// // -> Ok(#(_state, "Lua 5.3"))
/// ```
///
/// ```gleam
/// glua.run(glua.new(), {
///   use _ <- glua.then(glua.set(
///     keys: ["my_table", "my_value"],
///     value: glua.bool(True)
///   ))
///   use ref <- glua.then(glua.get(keys: ["my_table", "my_value"]))
///
///   glua.dereference(ref:, using: decode.bool)
/// })
/// // -> Ok(#(_state, True))
/// ```
///
/// ```gleam
/// glua.run(glua.new(), glua.get(keys: ["non_existent"]))
/// // -> Error(glua.KeyNotFound(["non_existent"]))
/// ```
pub fn get(keys keys: List(String)) -> Action(Value, e) {
  use state <- Action
  use ret <- result.map(do_get(state, keys))
  #(state, ret)
}

@external(erlang, "glua_ffi", "get_table_keys")
fn do_get(lua: Lua, keys: List(String)) -> Result(Value, LuaError(e))

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
) -> Result(a, LuaError(e)) {
  use value <- result.try(do_get_private(lua, key))
  decode.run(value, decoder) |> result.map_error(UnexpectedResultType)
}

@external(erlang, "glua_ffi", "get_private")
fn do_get_private(lua: Lua, key: String) -> Result(dynamic.Dynamic, LuaError(e))

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
/// glua.run(glua.new(), {
///   use _ <- glua.then(glua.set(
///     keys: ["my_number"],
///     value: glua.int(10)
///   ))
///   use ref <- glua.get(keys: ["my_number"])
///
///   glua.dereference(ref:, using: decode.int)
/// })
/// // -> Ok(#(_state, 10))
/// ```
///
/// ```gleam
/// let emails = ["jhondoe@example.com", "lucy@example.com"]
/// let assert Ok(#(_state, results)) = glua.run(glua.new(), {
///   use encoded <- glua.then(glua.table(
///     list.index_map(emails, fn(email, i) { #(glua.int(i + 1), glua.string(email)) })
///   ))
///   use _ <- glua.then(glua.set(["info", "emails"], encoded))
///
///   use ret <- glua.then(glua.eval(code: "return info.emails"))
///   use ref <- glua.try(list.first(ret))
///
///   glua.dereference(ref:, using: decode.dict(decode.int, decode.string))
///   |> glua.map(dict.values)
/// })
///
/// assert results == emails
/// ```
pub fn set(keys keys: List(String), value val: Value) -> Action(Nil, e) {
  use state <- Action
  use #(new, keys) <- result.try(
    list.try_fold(keys, #(state, []), fn(acc, key) {
      let #(state, keys) = acc
      let keys = list.append(keys, [key])
      case do_get(state, keys) {
        Ok(_) -> Ok(#(state, keys))

        Error(KeyNotFound(_)) -> {
          let #(tbl, new) = do_table([], state)
          use new <- result.map(do_set(new, keys, tbl))
          #(new, keys)
        }

        Error(e) -> Error(e)
      }
    }),
  )

  do_set(new, keys, val)
  |> result.map(fn(state) { #(state, Nil) })
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
  keys: List(String),
  values: List(#(String, Value)),
) -> Action(Nil, e) {
  use _ <- then(
    fold(values, fn(pair) { set(list.append(keys, [pair.0]), pair.1) }),
  )

  success(Nil)
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
/// glua.run(glua.new(), {
///   use _ <- glua.then(glua.set_lua_paths(paths: my_scripts_paths))
///   use ret <- glua.then(glua.eval(
///     code: "local my_math = require 'my_script'; return my_math.square(3)"
///   ))
///   use ref <- glua.try(list.first(ret))
///
///   glua.dereference(ref:, using: decode.int)
/// })
/// // -> Ok(#(_state, 9))
/// ```
pub fn set_lua_paths(paths paths: List(String)) -> Action(Nil, e) {
  let paths = string.join(paths, with: ";") |> string
  set(["package", "path"], paths)
}

@external(erlang, "glua_ffi", "set_table_keys")
fn do_set(lua: Lua, keys: List(String), val: a) -> Result(Lua, LuaError(e))

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
pub fn load(code code: String) -> Action(Chunk, e) {
  Action(do_load(_, code))
}

@external(erlang, "glua_ffi", "load")
fn do_load(lua: Lua, code: String) -> Result(#(Lua, Chunk), LuaError(e))

/// Parses a Lua source file and returns it as a compiled chunk.
///
/// To eval the returned chunk, use `glua.eval_chunk`.
pub fn load_file(path path: String) -> Action(Chunk, e) {
  Action(do_load_file(_, path))
}

@external(erlang, "glua_ffi", "load_file")
fn do_load_file(lua: Lua, path: String) -> Result(#(Lua, Chunk), LuaError(e))

/// Evaluates a string of Lua code.
///
/// ## Examples
///
/// ```gleam
/// glua.run(glua.new(), {
///   use ret <- glua.then(glua.eval(code: "return 1 + 2"))
///   use ref <- glua.try(list.first(ret))
///   
///   glua.dereference(ref:, using: decode.int)
/// })
/// // -> Ok(#(_state, 3))
/// ```
///
/// ```gleam
/// let assert Ok(#(state, [ref1, ref2])) = glua.run(glua.new(), glua.eval(
///   code: "return 'hello, world!', 10",
/// ))
///
/// let assert Ok(#(_state, "hello world")) =
///   glua.run(state, glua.dereference(ref: ref1, using: decode.string))
/// let assert Ok(#(_state, 10)) =
///   glua.run(state, glua.dereference(ref: ref2, using: decode.int))
/// ```
///
/// ```gleam
/// glua.run(glua.new(), glua.eval(code: "return 1 * "))
/// // -> Error(glua.LuaCompileFailure(
///   [glua.LuaCompileError(1, Parse, "syntax error before: ")]
/// ))
/// ```
///
/// > **Note**: If you are evaluating the same piece of code multiple times,
/// > instead of calling `glua.eval` repeatly it is recommended to first convert
/// > the code to a chunk by passing it to `glua.load`, and then
/// > evaluate that chunk using `glua.eval_chunk`.
pub fn eval(code code: String) -> Action(List(Value), e) {
  Action(do_eval(_, code))
}

@external(erlang, "glua_ffi", "eval")
fn do_eval(lua: Lua, code: String) -> Result(#(Lua, List(Value)), LuaError(e))

/// Evaluates a compiled chunk of Lua code.
///
/// ## Examples
/// 
/// ```gleam
/// glua.run(glua.new(), {
///   use chunk <- glua.then(glua.load(
///     code: "return 'hello, world!'"
///   ))
/// 
///   use ret <- glua.then(glua.eval_chunk(chunk:))
///   use ref <- glua.try(list.first(ret))
///
///   glua.dereference(ref:, using: decode.string)
/// // -> Ok(#(_state, "hello, world!"))
/// ```
pub fn eval_chunk(chunk chunk: Chunk) -> Action(List(Value), e) {
  Action(do_eval_chunk(_, chunk))
}

@external(erlang, "glua_ffi", "eval_chunk")
fn do_eval_chunk(
  lua: Lua,
  chunk: Chunk,
) -> Result(#(Lua, List(Value)), LuaError(e))

/// Evaluates a Lua source file.
///
/// ## Examples
/// 
/// ```gleam
/// glua.run(glua.new(), {
///   use ret <- glua.then(glua.eval_file(
///     path: "path/to/hello.lua",
///   ))
///   use ref <- glua.try(list.first(ret))
///
///   glua.dereference(ref:, using: decode.string)
/// })
/// // -> Ok(#(_state, "hello, world!"))
/// ```
///
/// ```gleam
/// glua.run(glua.new(), glua.eval_file(
///   path: "path/to/non/existent/file",
/// ))
/// // -> Error(glua.FileNotFound(["path/to/non/existent/file"]))
/// ```
pub fn eval_file(path path: String) -> Action(List(Value), e) {
  Action(do_eval_file(_, path))
}

@external(erlang, "glua_ffi", "eval_file")
fn do_eval_file(
  lua: Lua,
  path: String,
) -> Result(#(Lua, List(Value)), LuaError(e))

/// Calls a Lua function by reference.
///
/// ## Examples
///
/// ```gleam
/// glua.run(glua.new(), {
///   use ret <- glua.then(glua.eval(code: "return math.sqrt"))
///   use fun <- glua.try(list.first(ret))
///
///   use ret <- glua.then(glua.call_function(
///     ref: fun,
///     args: [glua.int(81)],
///   ))
///   use ref <- glua.try(list.first(ret))
///
///   glua.dereference(ref:, using: decode.float)
/// })
/// // -> Ok(#(_state, 9.0))
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
///
/// glua.run(glua.new(), {
///   use ret <- glua.then(glua.eval(code:))
///   use ref <- glua.try(list.first(ret))
///
///   use ret <- glua.then(glua.call_function(
///     ref: fun,
///     args: [glua.int(10)],
///   ))
///   use ref <- glua.try(list.first(ret))
///
///   glua.dereference(ref:, using: decode.int)
/// })
/// // -> Ok(#(_state, 55))
/// ```
pub fn call_function(
  ref fun: Value,
  args args: List(Value),
) -> Action(List(Value), e) {
  Action(do_call_function(_, fun, args))
}

@external(erlang, "glua_ffi", "call_function")
fn do_call_function(
  lua: Lua,
  fun: Value,
  args: List(Value),
) -> Result(#(Lua, List(Value)), LuaError(e))

/// Gets a reference to the function at `keys`, then inmediatly calls it with the provided `args`.
///
/// This is a shorthand for `glua.get` followed by `glua.call_function`.
///
/// ## Examples
///
/// ```gleam
/// glua.run(glua.new(), {
///   use ret <- glua.then(glua.call_function_by_name(
///     keys: ["string", "upper"],
///     args: [glua.string("hello from Gleam!")]
///   ))
///   use ref <- glua.try(list.first(ret))
///
///   glua.dereference(ref:, using: decode.string)
/// })
/// // -> Ok(#(_state, "HELLO FROM GLEAM!"))
/// ```
pub fn call_function_by_name(
  keys keys: List(String),
  args args: List(Value),
) -> Action(List(Value), e) {
  use fun <- then(get(keys))
  call_function(fun, args)
}
