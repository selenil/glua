import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option
import gleam/pair
import gleeunit
import glua

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn sandbox_test() {
  let assert Ok(lua) = glua.sandbox(glua.new(), ["math", "max"])
  let #(lua, args) = glua.list(lua, glua.int, [20, 10])

  let assert Error(glua.LuaRuntimeException(exception, _)) =
    glua.call_function_by_name(
      state: lua,
      keys: ["math", "max"],
      args:,
      using: decode.int,
    )

  assert exception == glua.ErrorCall(["math.max is sandboxed"])

  let assert Ok(lua) = glua.sandbox(glua.new(), ["string"])

  let assert Error(glua.LuaRuntimeException(glua.IllegalIndex(_, name), _)) =
    glua.eval(
      state: lua,
      code: "return string.upper('my_string')",
      using: decode.string,
    )

  assert name == "upper"

  let assert Ok(lua) = glua.sandbox(glua.new(), ["os", "execute"])

  let assert Error(glua.LuaRuntimeException(exception, _)) =
    glua.ref_eval(
      state: lua,
      code: "os.execute(\"echo 'sandbox test is failing'\"); os.exit(1)",
    )

  assert exception == glua.ErrorCall(["os.execute is sandboxed"])

  let assert Ok(lua) = glua.sandbox(glua.new(), ["print"])
  let #(lua, arg) = glua.string(lua, "sandbox test is failing")
  let assert Error(glua.LuaRuntimeException(exception, _)) =
    glua.call_function_by_name(
      state: lua,
      keys: ["print"],
      args: [arg],
      using: decode.string,
    )

  assert exception == glua.ErrorCall(["print is sandboxed"])
}

pub fn new_sandboxed_test() {
  let assert Ok(lua) = glua.new_sandboxed([])

  let assert Error(glua.LuaRuntimeException(exception, _)) =
    glua.ref_eval(state: lua, code: "return load(\"return 1\")")

  assert exception == glua.ErrorCall(["load is sandboxed"])

  let #(lua, arg) = glua.int(lua, 1)
  let assert Error(glua.LuaRuntimeException(exception, _)) =
    glua.ref_call_function_by_name(state: lua, keys: ["os", "exit"], args: [arg])

  assert exception == glua.ErrorCall(["os.exit is sandboxed"])

  let assert Error(glua.LuaRuntimeException(glua.IllegalIndex(_, name), _)) =
    glua.ref_eval(state: lua, code: "io.write('some_message')")

  assert name == "write"

  let assert Ok(lua) = glua.new_sandboxed([["package"], ["require"]])
  let assert Ok(lua) = glua.set_lua_paths(lua, paths: ["./test/lua/?.lua"])

  let code = "local s = require 'example'; return s"
  let assert Ok(#(_, [result])) =
    glua.eval(state: lua, code:, using: decode.string)

  assert result == "LUA IS AN EMBEDDABLE LANGUAGE"
}

pub fn get_test() {
  let state = glua.new()

  let assert Ok(pi) =
    glua.get(state: state, keys: ["math", "pi"], using: decode.float)

  assert pi >. 3.14 && pi <. 3.15

  let keys = ["my_table", "my_value"]
  let #(state, encoded) = glua.bool(state, True)
  let assert Ok(state) = glua.set(state:, keys:, value: encoded)
  let assert Ok(ret) = glua.get(state:, keys:, using: decode.bool)

  assert ret == True

  let code =
    "
  my_value = 10
  return 'ignored'
"
  let assert Ok(#(state, _)) =
    glua.new() |> glua.eval(code:, using: decode.string)
  let assert Ok(ret) = glua.get(state:, keys: ["my_value"], using: decode.int)

  assert ret == 10
}

pub fn get_returns_proper_errors_test() {
  let state = glua.new()

  assert glua.get(state:, keys: ["non_existent_global"], using: decode.string)
    == Error(glua.KeyNotFound)

  let #(state, encoded) = glua.int(state, 10)
  let assert Ok(state) =
    glua.set(state:, keys: ["my_table", "some_value"], value: encoded)

  assert glua.get(state:, keys: ["my_table", "my_val"], using: decode.int)
    == Error(glua.KeyNotFound)
}

pub fn set_test() {
  let #(lua, encoded) = glua.string(glua.new(), "custom version")

  let assert Ok(lua) = glua.set(state: lua, keys: ["_VERSION"], value: encoded)
  let assert Ok(result) =
    glua.get(state: lua, keys: ["_VERSION"], using: decode.string)

  assert result == "custom version"

  let numbers =
    [2, 4, 7, 12]
    |> list.index_map(fn(n, i) { #(i + 1, n * n) })

  let keys = ["math", "squares"]

  let #(lua, encoded) = glua.table(lua, #(glua.int, glua.int), numbers)
  let assert Ok(lua) = glua.set(lua, keys, encoded)

  assert glua.get(lua, keys, glua.table_decoder(decode.int, decode.int))
    == Ok([#(1, 4), #(2, 16), #(3, 49), #(4, 144)])

  let count_odd = fn(lua: glua.Lua, args: List(dynamic.Dynamic)) {
    let assert [list] = args
    let assert Ok(list) =
      decode.run(list, glua.table_decoder(decode.int, decode.int))

    let count =
      list.map(list, pair.second)
      |> list.count(int.is_odd)

    glua.list(lua, glua.int, [count])
  }

  let #(lua, encoded) = glua.function(glua.new(), count_odd)
  let assert Ok(lua) = glua.set(lua, ["count_odd"], encoded)

  let #(lua, arg) =
    glua.table(
      lua,
      #(glua.int, glua.int),
      list.index_map(list.range(1, 10), fn(i, n) { #(i + 1, n) }),
    )

  let assert Ok(#(_, [result])) =
    glua.call_function_by_name(
      state: lua,
      keys: ["count_odd"],
      args: [arg],
      using: decode.int,
    )

  assert result == 5
}

pub fn set_lua_paths_test() {
  let assert Ok(state) =
    glua.set_lua_paths(state: glua.new(), paths: ["./test/lua/?.lua"])

  let code = "local s = require 'example'; return s"

  let assert Ok(#(_, [result])) = glua.eval(state:, code:, using: decode.string)

  assert result == "LUA IS AN EMBEDDABLE LANGUAGE"
}

pub fn get_private_test() {
  assert glua.new()
    |> glua.set_private("test", [1, 2, 3])
    |> glua.get_private("test", using: decode.list(decode.int))
    == Ok([1, 2, 3])

  assert glua.new()
    |> glua.get_private("non_existent", using: decode.string)
    == Error(glua.KeyNotFound)
}

pub fn delete_private_test() {
  let lua = glua.set_private(glua.new(), "the_value", "that_will_be_deleted")

  assert glua.get_private(lua, "the_value", using: decode.string)
    == Ok("that_will_be_deleted")

  assert glua.delete_private(lua, "the_value")
    |> glua.get_private(key: "the_value", using: decode.string)
    == Error(glua.KeyNotFound)
}

pub fn load_test() {
  let assert Ok(#(lua, chunk)) =
    glua.load(state: glua.new(), code: "return 5 * 5")
  let assert Ok(#(_, [result])) =
    glua.eval_chunk(state: lua, chunk:, using: decode.int)

  assert result == 25
}

pub fn eval_load_file_test() {
  let assert Ok(#(lua, chunk)) =
    glua.load_file(state: glua.new(), path: "./test/lua/example.lua")
  let assert Ok(#(_, [result])) =
    glua.eval_chunk(state: lua, chunk:, using: decode.string)

  assert result == "LUA IS AN EMBEDDABLE LANGUAGE"
}

pub fn eval_test() {
  let assert Ok(#(lua, [result])) =
    glua.eval(
      state: glua.new(),
      code: "return 'hello, ' .. 'world!'",
      using: decode.string,
    )

  assert result == "hello, world!"

  let assert Ok(#(_, results)) =
    glua.eval(state: lua, code: "return 2 + 2, 3 - 1", using: decode.int)

  assert results == [4, 2]
}

pub fn eval_returns_proper_errors_test() {
  let state = glua.new()

  assert glua.eval(state:, code: "if true then 1 + ", using: decode.int)
    == Error(
      glua.LuaCompilerException(messages: ["syntax error before: ", "1"]),
    )

  assert glua.eval(state:, code: "return 'Hello from Lua!'", using: decode.int)
    == Error(
      glua.UnexpectedResultType([decode.DecodeError("Int", "String", [])]),
    )

  let assert Error(glua.LuaRuntimeException(
    exception: glua.IllegalIndex(value:, index:),
    state: _,
  )) = glua.eval(state:, code: "return a.b", using: decode.int)

  assert value == "nil"
  assert index == "b"

  let assert Error(glua.LuaRuntimeException(
    exception: glua.ErrorCall(messages:),
    state: _,
  )) = glua.eval(state:, code: "error('error message')", using: decode.int)

  assert messages == ["error message"]

  let assert Error(glua.LuaRuntimeException(
    exception: glua.UndefinedFunction(value:),
    state: _,
  )) = glua.eval(state:, code: "local a = 5; a()", using: decode.int)

  assert value == "5"
  let assert Error(glua.LuaRuntimeException(
    exception: glua.BadArith(operator:, args:),
    state: _,
  )) = glua.eval(state:, code: "return 10 / 0", using: decode.int)

  assert operator == "/"
  assert args == ["10", "0"]

  let assert Error(glua.LuaRuntimeException(
    exception: glua.AssertError(message:),
    state: _,
  )) =
    glua.eval(
      state:,
      code: "assert(1 == 2, 'assertion failed')",
      using: decode.int,
    )

  assert message == "assertion failed"
}

pub fn eval_file_test() {
  let assert Ok(#(_, [result])) =
    glua.eval_file(
      state: glua.new(),
      path: "./test/lua/example.lua",
      using: decode.string,
    )

  assert result == "LUA IS AN EMBEDDABLE LANGUAGE"
}

pub fn call_function_test() {
  let assert Ok(#(lua, [fun])) =
    glua.ref_eval(state: glua.new(), code: "return string.reverse")

  let #(lua, encoded) = glua.string(lua, "auL")

  let assert Ok(#(lua, [result])) =
    glua.call_function(
      state: lua,
      ref: fun,
      args: [encoded],
      using: decode.string,
    )

  assert result == "Lua"

  let assert Ok(#(lua, [fun])) =
    glua.ref_eval(state: lua, code: "return function(a, b) return a .. b end")

  let #(lua, args) = glua.list(lua, glua.string, ["Lua in ", "Gleam"])

  let assert Ok(#(_, [result])) =
    glua.call_function(state: lua, ref: fun, args:, using: decode.string)

  assert result == "Lua in Gleam"
}

pub fn call_function_returns_proper_errors_test() {
  let state = glua.new()

  let assert Ok(#(state, [ref])) =
    glua.ref_eval(state:, code: "return string.upper")

  let #(state, arg) = glua.string(state, "Hello from Gleam!")

  assert glua.call_function(state:, ref:, args: [arg], using: decode.int)
    == Error(
      glua.UnexpectedResultType([decode.DecodeError("Int", "String", [])]),
    )

  let assert Ok(#(lua, [ref])) = glua.ref_eval(state:, code: "return 1")

  let assert Error(glua.LuaRuntimeException(
    exception: glua.UndefinedFunction(value:),
    state: _,
  )) = glua.call_function(state: lua, ref:, args: [], using: decode.string)

  assert value == "1"
}

pub fn call_function_by_name_test() {
  let #(lua, args) = glua.new() |> glua.list(glua.int, [20, 10])
  let assert Ok(#(lua, [result])) =
    glua.call_function_by_name(
      state: lua,
      keys: ["math", "max"],
      args:,
      using: decode.int,
    )

  assert result == 20

  let assert Ok(#(lua, [result])) =
    glua.call_function_by_name(
      state: lua,
      keys: ["math", "min"],
      args:,
      using: decode.int,
    )

  assert result == 10

  let #(lua, arg) = glua.float(lua, 10.2)
  let assert Ok(#(_, [result])) =
    glua.call_function_by_name(
      state: lua,
      keys: ["math", "type"],
      args: [arg],
      using: decode.optional(decode.string),
    )

  assert result == option.Some("float")
}

pub fn nested_function_references_test() {
  let code = "return function() return math.sqrt end"

  let assert Ok(#(lua, [ref])) = glua.ref_eval(state: glua.new(), code:)
  let assert Ok(#(lua, [ref])) =
    glua.ref_call_function(state: lua, ref:, args: [])

  let #(lua, arg) = glua.int(lua, 400)
  let assert Ok(#(_, [result])) =
    glua.call_function(state: lua, ref:, args: [arg], using: decode.float)
  assert result == 20.0
}
