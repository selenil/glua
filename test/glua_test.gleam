import gleam/dict
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

pub fn get_table_test() {
  let lua = glua.new()
  let my_table = [
    #("meaning of life", 42),
    #("pi", 3),
    #("euler's number", 3),
  ]
  let cool_numbers =
    glua.function(fn(lua, _params) {
      let table =
        glua.table(
          my_table
          |> list.map(fn(pair) { #(glua.string(pair.0), glua.int(pair.1)) }),
        )
      #(lua, [table])
    })

  let assert Ok(lua) = glua.set(lua, ["cool_numbers"], cool_numbers)
  let assert Ok(#(_lua, [table])) =
    glua.call_function_by_name(
      lua,
      ["cool_numbers"],
      [],
      using: glua.table_decoder(decode.string, decode.int),
    )

  assert dict.from_list(table) == dict.from_list(my_table)
}

pub fn sandbox_test() {
  let assert Ok(lua) = glua.sandbox(glua.new(), ["math", "max"])
  let args = list.map([20, 10], glua.int)

  let assert Error(glua.LuaRuntimeException(exception, _)) =
    glua.call_function_by_name(
      state: lua,
      keys: ["math", "max"],
      args:,
      using: decode.int,
    )

  assert exception == glua.ErrorCall("math.max is sandboxed", option.None)

  let assert Ok(lua) = glua.sandbox(glua.new(), ["string"])

  let assert Error(glua.LuaRuntimeException(glua.IllegalIndex(index, _), _)) =
    glua.eval(
      state: lua,
      code: "return string.upper('my_string')",
      using: decode.string,
    )

  assert index == "upper"

  let assert Ok(lua) = glua.sandbox(glua.new(), ["os", "execute"])

  let assert Error(glua.LuaRuntimeException(exception, _)) =
    glua.ref_eval(
      state: lua,
      code: "os.execute(\"echo 'sandbox test is failing'\"); os.exit(1)",
    )

  assert exception == glua.ErrorCall("os.execute is sandboxed", option.None)

  let assert Ok(lua) = glua.sandbox(glua.new(), ["print"])
  let arg = glua.string("sandbox test is failing")
  let assert Error(glua.LuaRuntimeException(exception, _)) =
    glua.call_function_by_name(
      state: lua,
      keys: ["print"],
      args: [arg],
      using: decode.string,
    )

  assert exception == glua.ErrorCall("print is sandboxed", option.None)
}

pub fn new_sandboxed_test() {
  let assert Ok(lua) = glua.new_sandboxed([])

  let assert Error(glua.LuaRuntimeException(exception, _)) =
    glua.ref_eval(state: lua, code: "return load(\"return 1\")")

  assert exception == glua.ErrorCall("load is sandboxed", option.None)

  let arg = glua.int(1)
  let assert Error(glua.LuaRuntimeException(exception, _)) =
    glua.ref_call_function_by_name(state: lua, keys: ["os", "exit"], args: [arg])

  assert exception == glua.ErrorCall("os.exit is sandboxed", option.None)

  let assert Error(glua.LuaRuntimeException(glua.IllegalIndex(index, _), _)) =
    glua.ref_eval(state: lua, code: "io.write('some_message')")

  assert index == "write"

  let assert Ok(lua) = glua.new_sandboxed([["package"], ["require"]])
  let assert Ok(lua) = glua.set_lua_paths(lua, paths: ["./test/lua/?.lua"])

  let code = "local s = require 'example'; return s"
  let assert Ok(#(_, [result])) =
    glua.eval(state: lua, code:, using: decode.string)

  assert result == "LUA IS AN EMBEDDABLE LANGUAGE"
}

pub fn encoding_and_decoding_nested_tables_test() {
  let nested_table = [
    #(
      glua.string("key"),
      glua.table([
        #(
          glua.int(1),
          glua.table([#(glua.string("deeper_key"), glua.string("deeper_value"))]),
        ),
      ]),
    ),
  ]

  let keys = ["my_nested_table"]

  let nested_table_decoder =
    glua.table_decoder(
      decode.string,
      glua.table_decoder(
        decode.int,
        glua.table_decoder(decode.string, decode.string),
      ),
    )
  let tbl = glua.table(nested_table)

  let assert Ok(lua) = glua.set(state: glua.new(), keys:, value: tbl)

  let assert Ok(result) =
    glua.get(state: lua, keys:, using: nested_table_decoder)

  assert result == [#("key", [#(1, [#("deeper_key", "deeper_value")])])]
}

pub type Userdata {
  Userdata(foo: String, bar: Int)
}

pub fn userdata_test() {
  let lua = glua.new()
  let userdata = Userdata("my-userdata", 1)
  let userdata_decoder = {
    use foo <- decode.field(1, decode.string)
    use bar <- decode.field(2, decode.int)
    decode.success(Userdata(foo:, bar:))
  }

  let assert Ok(lua) = glua.set(lua, ["my_userdata"], glua.userdata(userdata))
  let assert Ok(#(lua, [result])) =
    glua.eval(lua, "return my_userdata", userdata_decoder)

  assert result == userdata

  let userdata = Userdata("other_userdata", 2)
  let assert Ok(lua) =
    glua.set(lua, ["my_other_userdata"], glua.userdata(userdata))
  let assert Error(glua.LuaRuntimeException(glua.IllegalIndex(index, _), _)) =
    glua.eval(lua, "return my_other_userdata.foo", decode.string)

  assert index == "foo"
}

pub fn get_test() {
  let state = glua.new()

  let assert Ok(pi) =
    glua.get(state: state, keys: ["math", "pi"], using: decode.float)

  assert pi >. 3.14 && pi <. 3.15

  let keys = ["my_table", "my_value"]
  let encoded = glua.bool(True)
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
    == Error(glua.KeyNotFound(["non_existent_global"]))

  let encoded = glua.int(10)
  let assert Ok(state) =
    glua.set(state:, keys: ["my_table", "some_value"], value: encoded)

  assert glua.get(state:, keys: ["my_table", "my_val"], using: decode.int)
    == Error(glua.KeyNotFound(["my_table", "my_val"]))
}

pub fn set_test() {
  let encoded = glua.string("custom version")

  let assert Ok(lua) =
    glua.set(state: glua.new(), keys: ["_VERSION"], value: encoded)
  let assert Ok(result) =
    glua.get(state: lua, keys: ["_VERSION"], using: decode.string)

  assert result == "custom version"

  let numbers =
    [2, 4, 7, 12]
    |> list.index_map(fn(n, i) { #(i + 1, n * n) })

  let keys = ["math", "squares"]

  let encoded =
    glua.table(
      numbers |> list.map(fn(pair) { #(glua.int(pair.0), glua.int(pair.1)) }),
    )
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

    #(lua, list.map([count], glua.int))
  }

  let encoded = glua.function(count_odd)
  let assert Ok(lua) = glua.set(glua.new(), ["count_odd"], encoded)

  let arg =
    glua.table(
      list.index_map(list.range(1, 10), fn(i, n) {
        #(glua.int(i + 1), glua.int(n))
      }),
    )

  let assert Ok(#(lua, [result])) =
    glua.call_function_by_name(
      state: lua,
      keys: ["count_odd"],
      args: [arg],
      using: decode.int,
    )

  assert result == 5

  let tbl =
    glua.table([
      #(
        glua.string("is_even"),
        glua.function(fn(lua, args) {
          let assert [arg] = args
          let assert Ok(arg) = decode.run(arg, decode.int)
          #(lua, list.map([int.is_even(arg)], glua.bool))
        }),
      ),
      #(
        glua.string("is_odd"),
        glua.function(fn(lua, args) {
          let assert [arg] = args
          let assert Ok(arg) = decode.run(arg, decode.int)
          #(lua, list.map([int.is_odd(arg)], glua.bool))
        }),
      ),
    ])

  let arg = glua.int(4)

  let assert Ok(lua) = glua.set(state: lua, keys: ["my_functions"], value: tbl)

  let assert Ok(#(lua, [result])) =
    glua.call_function_by_name(
      state: lua,
      keys: ["my_functions", "is_even"],
      args: [arg],
      using: decode.bool,
    )

  assert result == True

  let assert Ok(#(_, [result])) =
    glua.eval(
      state: lua,
      code: "return my_functions.is_odd(4)",
      using: decode.bool,
    )

  assert result == False
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
    == Error(glua.KeyNotFound(["non_existent"]))
}

pub fn delete_private_test() {
  let lua = glua.set_private(glua.new(), "the_value", "that_will_be_deleted")

  assert glua.get_private(lua, "the_value", using: decode.string)
    == Ok("that_will_be_deleted")

  assert glua.delete_private(lua, "the_value")
    |> glua.get_private(key: "the_value", using: decode.string)
    == Error(glua.KeyNotFound(["the_value"]))
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

  let assert Error(e) =
    glua.load_file(state: glua.new(), path: "non_existent_file")
  assert e == glua.FileNotFound("non_existent_file")
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

  let assert Error(e) =
    glua.eval(state:, code: "if true then 1 + ", using: decode.int)
  assert e
    == glua.LuaCompileFailure([
      glua.LuaCompileError(1, glua.Parse, "syntax error before: 1"),
    ])

  let assert Error(e) =
    glua.eval(state:, code: "print(\"hi)", using: decode.int)

  assert e
    == glua.LuaCompileFailure([
      glua.LuaCompileError(1, glua.Tokenize, "syntax error near '\"'"),
    ])

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
    exception: glua.ErrorCall(message, level),
    state: _,
  )) = glua.eval(state:, code: "error('error message')", using: decode.int)

  assert message == "error message"
  assert level == option.None

  let assert Error(glua.LuaRuntimeException(
    exception: glua.ErrorCall(message, level),
    state: _,
  )) =
    glua.eval(state:, code: "error('error with level', 1)", using: decode.int)

  assert message == "error with level"
  assert level == option.Some(1)

  let assert Error(_) = glua.eval(state:, code: "error({1})", using: decode.int)

  let assert Error(glua.LuaRuntimeException(
    exception: glua.UndefinedFunction(value:),
    state: _,
  )) = glua.eval(state:, code: "local a = 5; a()", using: decode.int)

  assert value == "5"

  let assert Error(glua.LuaRuntimeException(
    exception: glua.UndefinedMethod(_, method:),
    state: _,
  )) =
    glua.eval(
      state:,
      code: "local i = function(x) return x end; i:call(1)",
      using: decode.string,
    )

  assert method == "call"

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

  let assert Error(_) =
    glua.eval(state:, code: "assert(false, {1})", using: decode.int)
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

  let encoded = glua.string("auL")

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

  let args = list.map(["Lua in ", "Gleam"], glua.string)

  let assert Ok(#(_, [result])) =
    glua.call_function(state: lua, ref: fun, args:, using: decode.string)

  assert result == "Lua in Gleam"
}

pub fn call_function_returns_proper_errors_test() {
  let state = glua.new()

  let assert Ok(#(state, [ref])) =
    glua.ref_eval(state:, code: "return string.upper")

  let arg = glua.string("Hello from Gleam!")

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
  let args = list.map([20, 10], glua.int)
  let assert Ok(#(lua, [result])) =
    glua.call_function_by_name(
      state: glua.new(),
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

  let arg = glua.float(10.2)
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

  let arg = glua.int(400)
  let assert Ok(#(_, [result])) =
    glua.call_function(state: lua, ref:, args: [arg], using: decode.float)
  assert result == 20.0
}

pub fn format_error_test() {
  let state = glua.new()

  let assert Error(e) = glua.ref_eval(state:, code: "1 +")
  assert glua.format_error(e)
    == "Lua compile error: \n\nFailed to parse: error on line 1: syntax error before: 1"

  let assert Error(e) = glua.ref_eval(state:, code: "assert(false)")
  assert glua.format_error(e)
    == "Lua runtime exception: Assertion failed with message: assertion failed\n\nLine 1: assert(false)"

  let assert Error(e) =
    glua.ref_eval(state:, code: "local a = true; local b = 1 * a")
  assert glua.format_error(e)
    == "Lua runtime exception: Bad arithmetic expression: 1 * true"

  let assert Error(e) =
    glua.get(state:, keys: ["non_existent"], using: decode.string)
  assert glua.format_error(e) == "Key \"non_existent\" not found"

  let assert Error(e) = glua.load_file(state:, path: "non_existent_file")
  assert glua.format_error(e)
    == "Lua source file \"non_existent_file\" not found"

  let assert Error(e) =
    glua.eval(state:, code: "return 1 + 1", using: decode.string)
  assert glua.format_error(e) == "Expected String, but found Int"
}
