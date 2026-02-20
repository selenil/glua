import gleam/dict
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/pair
import gleam/result
import gleeunit
import glua

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn get_table_test() {
  let my_table = [
    #("meaning of life", 42),
    #("pi", 3),
    #("euler's number", 3),
  ]
  let cool_numbers =
    glua.function(fn(_params) {
      use table <- glua.then(glua.table(
        my_table
        |> list.map(fn(pair) { #(glua.string(pair.0), glua.int(pair.1)) }),
      ))
      glua.success([table])
    })

  let action = {
    use Nil <- glua.then(glua.set(["cool_numbers"], cool_numbers))
    use ret <- glua.then(glua.call_function_by_name(["cool_numbers"], []))
    let assert [number] = ret
    use table <- glua.then(glua.dereference(
      ref: number,
      using: decode.dict(decode.string, decode.int),
    ))
    assert table == dict.from_list(my_table)
    glua.success(Nil)
  }
  let assert Ok(_) = glua.run(glua.new(), action)
}

pub fn sandbox_test() {
  let assert Ok(lua) = glua.sandbox(glua.new(), ["math", "max"])
  let args = list.map([20, 10], glua.int)

  let assert Error(glua.LuaRuntimeException(exception, _)) =
    glua.run(lua, glua.call_function_by_name(keys: ["math", "max"], args:))

  assert exception == glua.ErrorCall("math.max is sandboxed", option.None)

  let assert Ok(lua) = glua.sandbox(glua.new(), ["string"])

  let assert Error(glua.LuaRuntimeException(glua.IllegalIndex(index, _), _)) =
    glua.run(lua, glua.eval("return string.upper('my_string')"))

  assert index == "upper"

  let assert Ok(lua) = glua.sandbox(glua.new(), ["os", "execute"])

  let assert Error(glua.LuaRuntimeException(exception, _)) =
    glua.run(
      lua,
      glua.eval(
        // TODO: test failure case
        "os.execute(\"echo 'sandbox test is failing'\"); os.exit(1)",
      ),
    )

  assert exception == glua.ErrorCall("os.execute is sandboxed", option.None)

  let assert Ok(lua) = glua.sandbox(glua.new(), ["print"])
  let assert Error(glua.LuaRuntimeException(exception, _)) =
    glua.run(
      lua,
      glua.call_function_by_name(keys: ["print"], args: [
        glua.string("sandbox test is failing"),
      ]),
    )

  assert exception == glua.ErrorCall("print is sandboxed", option.None)
}

pub fn new_sandboxed_test() {
  let assert Ok(lua) = glua.new_sandboxed([])

  let assert Error(glua.LuaRuntimeException(exception, _)) =
    glua.run(lua, glua.eval("return load(\"return 1\")"))

  assert exception == glua.ErrorCall("load is sandboxed", option.None)

  let assert Error(glua.LuaRuntimeException(exception, _)) =
    glua.run(
      lua,
      glua.call_function_by_name(keys: ["os", "exit"], args: [
        glua.int(1),
      ]),
    )

  assert exception == glua.ErrorCall("os.exit is sandboxed", option.None)

  let assert Error(glua.LuaRuntimeException(glua.IllegalIndex(index, _), _)) =
    glua.run(lua, glua.eval("io.write('some_message')"))

  assert index == "write"

  let assert Ok(lua) = glua.new_sandboxed([["package"], ["require"]])
  let action = {
    use _ <- glua.then(glua.set_lua_paths(paths: ["./test/lua/?.lua"]))

    let code = "local s = require 'example'; return s"
    use ref <- glua.then(glua.eval(code))
    use ref <- glua.try(list.first(ref))
    use result <- glua.map(glua.dereference(ref:, using: decode.string))

    assert result == "LUA IS AN EMBEDDABLE LANGUAGE"
    glua.success(Nil)
  }
  let assert Ok(_) = glua.run(lua, action)
}

pub fn guard_test() {
  let action = {
    use ret <- glua.then(
      glua.call_function_by_name(keys: ["math", "sqrt"], args: [glua.float(9.0)]),
    )
    use ref <- glua.try(list.first(ret))

    use n <- glua.then(glua.dereference(ref:, using: decode.float))
    use <- glua.guard(when: n <. 0.0, return: Nil)

    glua.success("the root square of 9.0 is " <> float.to_string(n))
  }

  assert glua.run(glua.new(), action) |> result.map(pair.second)
    == Ok("the root square of 9.0 is 3.0")

  let action = {
    use ret <- glua.then(glua.eval(code: "local a = 1"))
    use <- glua.guard(
      when: ret == [],
      return: "Expected at least one return value",
    )

    glua.success("unreachable")
  }

  assert glua.run(glua.new(), action)
    == Error(glua.CustomError("Expected at least one return value"))
}

pub fn map_test() {
  let action =
    glua.get(keys: ["math", "pi"])
    |> glua.then(glua.dereference(_, using: decode.float))
    |> glua.map(float.truncate)

  assert glua.run(glua.new(), action) |> result.map(pair.second) == Ok(3)

  let action = {
    use ret <- glua.then(glua.eval("return 3 * true"))
    use ref <- glua.try(list.first(ret))

    glua.map(glua.dereference(ref:, using: decode.int), fn(n) {
      "the result is " <> int.to_string(n)
    })
  }
  let assert Error(glua.LuaRuntimeException(exception, _state)) =
    glua.run(glua.new(), action)

  assert exception == glua.BadArith("*", ["3", "true"])
}

pub fn encoding_and_decoding_nested_tables_test() {
  let action = {
    use tb1 <- glua.then(
      glua.table([#(glua.string("deeper_key"), glua.string("deeper_value"))]),
    )
    use tb2 <- glua.then(glua.table([#(glua.int(1), tb1)]))
    use tb3 <- glua.then(glua.table([#(glua.string("key"), tb2)]))

    let keys = ["my_nested_table"]

    let nested_table_decoder =
      decode.dict(
        decode.string,
        decode.dict(decode.int, decode.dict(decode.string, decode.string)),
      )

    use Nil <- glua.then(glua.set(keys:, value: tb3))
    use ref <- glua.then(glua.get(keys:))

    use result <- glua.then(glua.dereference(ref:, using: nested_table_decoder))

    assert result
      == dict.from_list([
        #(
          "key",
          dict.from_list([
            #(1, dict.from_list([#("deeper_key", "deeper_value")])),
          ]),
        ),
      ])
    glua.success(Nil)
  }

  let assert Ok(_) = glua.run(glua.new(), action)
}

pub type Userdata {
  Userdata(foo: String, bar: Int)
}

pub fn userdata_test() {
  let action = {
    use userdata <- glua.then(glua.userdata(Userdata("my-userdata", 1)))
    let userdata_decoder = {
      use foo <- decode.field(1, decode.string)
      use bar <- decode.field(2, decode.int)
      decode.success(Userdata(foo:, bar:))
    }

    use Nil <- glua.then(glua.set(["my_userdata"], userdata))
    use ref <- glua.then(glua.eval("return my_userdata"))
    use ref <- glua.try(list.first(ref))
    use result <- glua.then(glua.dereference(ref:, using: userdata_decoder))

    assert result == Userdata("my-userdata", 1)

    use userdata <- glua.then(glua.userdata(Userdata("other-userdata", 2)))
    use Nil <- glua.then(glua.set(["my_other_userdata"], userdata))
    glua.success(Nil)
  }
  let assert Ok(#(lua, Nil)) = glua.run(glua.new(), action)

  let assert Error(glua.LuaRuntimeException(glua.IllegalIndex(index, _), _)) =
    glua.run(lua, glua.eval("return my_other_userdata.foo"))

  assert index == "foo"
}

pub fn get_test() {
  let action = {
    use ref <- glua.then(glua.get(keys: ["math", "pi"]))
    use pi <- glua.then(glua.dereference(ref:, using: decode.float))

    // TODO: Replace with glua/lib/math.pi
    assert pi >. 3.14 && pi <. 3.15

    let keys = ["my_table", "my_value"]
    use Nil <- glua.then(glua.set(keys:, value: glua.bool(True)))
    use ref <- glua.then(glua.get(keys:))
    use ret <- glua.then(glua.dereference(ref:, using: decode.bool))

    assert ret == True
    glua.success(Nil)
  }
  let assert Ok(_) = glua.run(glua.new(), action)

  let action = {
    let code =
      "
  my_value = 10
  return 'ignored'
"
    use _ <- glua.then(glua.eval(code))
    use ref <- glua.then(glua.get(keys: ["my_value"]))
    use ret <- glua.then(glua.dereference(ref:, using: decode.int))

    assert ret == 10
    glua.success(Nil)
  }
  let assert Ok(_) = glua.run(glua.new(), action)
}

pub fn get_returns_proper_errors_test() {
  assert glua.run(glua.new(), glua.get(keys: ["non_existent_global"]))
    == Error(glua.KeyNotFound(["non_existent_global"]))

  let action = {
    use Nil <- glua.then(glua.set(
      keys: ["my_table", "some_value"],
      value: glua.int(10),
    ))
    use _ret <- glua.then(glua.get(keys: ["my_table", "my_val"]))
    panic as "unreachable"
  }
  let assert Error(glua.KeyNotFound(["my_table", "my_val"])) =
    glua.run(glua.new(), action)
}

pub fn set_test() {
  let action = {
    let encoded = glua.string("custom version")

    use Nil <- glua.then(glua.set(keys: ["_VERSION"], value: encoded))
    use ref <- glua.then(glua.get(keys: ["_VERSION"]))
    use result <- glua.then(glua.dereference(ref:, using: decode.string))

    assert result == "custom version"

    let numbers =
      [2, 4, 7, 12]
      |> list.index_map(fn(n, i) { #(i + 1, n * n) })

    let keys = ["math", "squares"]

    use encoded <- glua.then(glua.table(
      numbers |> list.map(fn(pair) { #(glua.int(pair.0), glua.int(pair.1)) }),
    ))
    use Nil <- glua.then(glua.set(keys, encoded))

    use ref <- glua.then(glua.get(keys))
    use check <- glua.then(glua.dereference(
      ref:,
      using: decode.dict(decode.int, decode.int),
    ))
    assert check == dict.from_list([#(1, 4), #(2, 16), #(3, 49), #(4, 144)])

    let count_odd = fn(args: List(glua.Value)) {
      let assert [list] = args
      use list <- glua.then(glua.dereference(
        list,
        decode.dict(decode.int, decode.int),
      ))

      let count =
        list.map(dict.to_list(list), pair.second)
        |> list.count(int.is_odd)

      glua.success(list.map([count], glua.int))
    }

    let encoded = glua.function(count_odd)
    use Nil <- glua.then(glua.set(["count_odd"], encoded))

    use arg <- glua.then(
      glua.table(
        list.index_map(list.range(1, 10), fn(i, n) {
          #(glua.int(i + 1), glua.int(n))
        }),
      ),
    )

    use refs <- glua.then(
      glua.call_function_by_name(keys: ["count_odd"], args: [arg]),
    )
    use ref <- glua.try(list.first(refs))

    use result <- glua.then(glua.dereference(ref:, using: decode.int))

    assert result == 5

    use tbl <- glua.then(
      glua.table([
        #(
          glua.string("is_even"),
          glua.function(fn(args) {
            let assert [arg] = args
            use arg <- glua.then(glua.dereference(arg, decode.int))
            list.map([int.is_even(arg)], glua.bool)
            |> glua.success()
          }),
        ),
        #(
          glua.string("is_odd"),
          glua.function(fn(args) {
            let assert [arg] = args
            use arg <- glua.then(glua.dereference(arg, decode.int))
            list.map([int.is_odd(arg)], glua.bool)
            |> glua.success()
          }),
        ),
      ]),
    )

    use Nil <- glua.then(glua.set(keys: ["my_functions"], value: tbl))

    use refs <- glua.then(
      glua.call_function_by_name(keys: ["my_functions", "is_even"], args: [
        glua.int(4),
      ]),
    )
    use ref <- glua.try(list.first(refs))
    use result <- glua.then(glua.dereference(ref:, using: decode.bool))

    assert result == True

    use refs <- glua.then(glua.eval("return my_functions.is_odd(4)"))
    use ref <- glua.try(list.first(refs))
    use result <- glua.then(glua.dereference(ref:, using: decode.bool))

    assert result == False
    glua.success(Nil)
  }
  glua.run(glua.new(), action)
}

pub fn set_lua_paths_test() {
  let action = {
    use Nil <- glua.then(glua.set_lua_paths(paths: ["./test/lua/?.lua"]))

    let code = "local s = require 'example'; return s"

    use refs <- glua.then(glua.eval(code))
    use ref <- glua.try(list.first(refs))
    use result <- glua.then(glua.dereference(ref:, using: decode.string))

    assert result == "LUA IS AN EMBEDDABLE LANGUAGE"
    glua.success(Nil)
  }
  glua.run(glua.new(), action)
}

pub fn get_private_test() {
  assert glua.new()
    |> glua.set_private("test", [1, 2, 3])
    |> glua.get_private("test", using: decode.list(decode.int))
    == Ok([1, 2, 3])

  assert glua.new()
    |> glua.get_private("non_existent", decode.string)
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
  let action = {
    use chunk <- glua.then(glua.load(code: "return 5 * 5"))
    use refs <- glua.then(glua.eval_chunk(chunk))
    use ref <- glua.try(list.first(refs))
    use result <- glua.then(glua.dereference(ref:, using: decode.int))

    assert result == 25
    glua.success(Nil)
  }
  let assert Ok(_) = glua.run(glua.new(), action)
}

pub fn eval_load_file_test() {
  let action = {
    use chunk <- glua.then(glua.load_file("./test/lua/example.lua"))
    use refs <- glua.then(glua.eval_chunk(chunk))
    use ref <- glua.try(list.first(refs))
    use result <- glua.then(glua.dereference(ref:, using: decode.string))

    assert result == "LUA IS AN EMBEDDABLE LANGUAGE"
    use _ <- glua.then(glua.load_file("non_existent_file"))

    panic as "unreachable"
  }
  let assert Error(glua.FileNotFound("non_existent_file")) =
    glua.run(glua.new(), action)
}

pub fn eval_test() {
  let actions = {
    use refs <- glua.then(glua.eval("return 'hello, ' .. 'world!'"))
    use ref <- glua.try(list.first(refs))
    use result <- glua.then(glua.dereference(ref:, using: decode.string))

    assert result == "hello, world!"

    use refs <- glua.then(glua.eval("return 2 + 2, 3 - 1"))
    use return <- glua.then(
      glua.fold(refs, glua.dereference(ref: _, using: decode.int)),
    )
    assert return == [4, 2]
    glua.success(Nil)
  }
  glua.run(glua.new(), actions)
}

pub fn eval_returns_proper_errors_test() {
  let lua = glua.new()

  let assert Error(e) = glua.run(lua, glua.eval("if true then 1 + "))
  assert e
    == glua.LuaCompileFailure([
      glua.LuaCompileError(1, glua.Parse, "syntax error before: 1"),
    ])

  let assert Error(e) = glua.run(lua, glua.eval("print(\"hi)"))
  assert e
    == glua.LuaCompileFailure([
      glua.LuaCompileError(1, glua.Tokenize, "syntax error near '\"'"),
    ])

  let action = {
    use refs <- glua.then(glua.eval("return 'Hello from Lua!'"))
    use ref <- glua.try(list.first(refs))
    use _ <- glua.then(glua.dereference(ref:, using: decode.int))
    panic as "unreachable"
  }
  assert glua.run(lua, action)
    == Error(
      glua.UnexpectedResultType([decode.DecodeError("Int", "String", [])]),
    )

  let assert Error(glua.LuaRuntimeException(
    exception: glua.IllegalIndex(value:, index:),
    state: _,
  )) = glua.run(lua, glua.eval("return a.b"))

  assert value == "nil"
  assert index == "b"

  let assert Error(glua.LuaRuntimeException(
    exception: glua.ErrorCall(message, level),
    state: _,
  )) = glua.run(lua, glua.eval("error('error message')"))

  assert message == "error message"
  assert level == option.None

  let assert Error(glua.LuaRuntimeException(
    exception: glua.ErrorCall(message, level),
    state: _,
  )) = glua.run(lua, glua.eval("error('error with level', 1)"))

  assert message == "error with level"
  assert level == option.Some(1)

  let assert Error(_) = glua.run(lua, glua.eval("error({1})"))

  let assert Error(glua.LuaRuntimeException(
    exception: glua.UndefinedFunction(value:),
    state: _,
  )) = glua.run(lua, glua.eval("local a = 5; a()"))

  assert value == "5"

  let assert Error(glua.LuaRuntimeException(
    exception: glua.UndefinedMethod(_, method:),
    state: _,
  )) = glua.run(lua, glua.eval("local i = function(x) return x end; i:call(1)"))

  assert method == "call"

  let assert Error(glua.LuaRuntimeException(
    exception: glua.BadArith(operator:, args:),
    state: _,
  )) = glua.run(lua, glua.eval("return 10 / 0"))

  assert operator == "/"
  assert args == ["10", "0"]

  let assert Error(glua.LuaRuntimeException(
    exception: glua.AssertError(message:),
    state: _,
  )) = glua.run(lua, glua.eval("assert(1 == 2, 'assertion failed')"))

  assert message == "assertion failed"

  let assert Error(_) = glua.run(lua, glua.eval("assert(false, {1})"))
}

pub fn eval_file_test() {
  let action = {
    use refs <- glua.then(glua.eval_file("./test/lua/example.lua"))
    use ref <- glua.try(list.first(refs))
    use result <- glua.then(glua.dereference(ref:, using: decode.string))

    assert result == "LUA IS AN EMBEDDABLE LANGUAGE"
    glua.success(Nil)
  }
  glua.run(glua.new(), action)
}

pub fn call_function_test() {
  let action = {
    use return <- glua.then(glua.eval("return string.reverse"))
    use fun <- glua.try(list.first(return))

    let encoded = glua.string("auL")

    use refs <- glua.then(glua.call_function(fun, [encoded]))
    use ref <- glua.try(list.first(refs))
    use result <- glua.then(glua.dereference(ref:, using: decode.string))

    assert result == "Lua"

    use return <- glua.then(glua.eval("return function(a, b) return a .. b end"))
    use fun <- glua.try(list.first(return))

    let args = list.map(["Lua in ", "Gleam"], glua.string)

    use refs <- glua.then(glua.call_function(fun, args))
    use ref <- glua.try(list.first(refs))
    use result <- glua.then(glua.dereference(ref:, using: decode.string))

    assert result == "Lua in Gleam"
    glua.success(Nil)
  }
  let assert Ok(_) = glua.run(glua.new(), action)
}

pub fn call_function_returns_proper_errors_test() {
  let action = {
    use refs <- glua.then(glua.eval("return string.upper"))
    use ref <- glua.try(list.first(refs))
    use refs <- glua.then(
      glua.call_function(ref, [glua.string("Hello from Gleam!")]),
    )
    use ref <- glua.try(list.first(refs))
    use _ <- glua.then(glua.dereference(ref:, using: decode.int))
    panic as "unreachable"
  }

  assert glua.run(glua.new(), action)
    == Error(
      glua.UnexpectedResultType([decode.DecodeError("Int", "String", [])]),
    )

  let action = {
    use refs <- glua.then(glua.eval("return 1"))
    use ref <- glua.try(list.first(refs))
    use _ <- glua.then(glua.call_function(ref, []))
    panic as "unreachable"
  }

  let assert Error(glua.LuaRuntimeException(
    exception: glua.UndefinedFunction(value:),
    state: _,
  )) = glua.run(glua.new(), action)

  assert value == "1"

  let fun =
    fn(args) {
      case args {
        [a] -> glua.success([a])
        _ -> glua.error("called without arguments")
      }
    }
    |> glua.function

  let assert Error(glua.LuaRuntimeException(
    exception: glua.ErrorCall(message: msg, level: option.None),
    state: _,
  )) = glua.run(glua.new(), glua.call_function(fun, []))

  assert msg == "called without arguments"

  let fun =
    fn(args) {
      case args {
        [] -> glua.success([])
        _ -> glua.error_with_level("function takes 0 arguments", 1)
      }
    }
    |> glua.function

  let assert Error(glua.LuaRuntimeException(
    exception: glua.ErrorCall(message: msg, level: option.Some(level)),
    state: _,
  )) = glua.run(glua.new(), glua.call_function(fun, [glua.int(2)]))

  assert msg == "function takes 0 arguments"
  assert level == 1
}

pub fn call_function_by_name_test() {
  let action = {
    let args = list.map([20, 10], glua.int)
    use refs <- glua.then(glua.call_function_by_name(
      keys: ["math", "max"],
      args:,
    ))
    use ref <- glua.try(list.first(refs))
    use result <- glua.then(glua.dereference(ref:, using: decode.int))

    assert result == 20

    use refs <- glua.then(glua.call_function_by_name(
      keys: ["math", "min"],
      args:,
    ))
    use ref <- glua.try(list.first(refs))
    use result <- glua.then(glua.dereference(ref:, using: decode.int))

    assert result == 10

    let arg = glua.float(10.2)
    use refs <- glua.then(
      glua.call_function_by_name(keys: ["math", "type"], args: [arg]),
    )
    use ref <- glua.try(list.first(refs))
    use result <- glua.then(glua.dereference(
      ref:,
      using: decode.optional(decode.string),
    ))

    assert result == option.Some("float")

    glua.success(Nil)
  }
  let assert Ok(_) = glua.run(glua.new(), action)
}

pub fn nested_function_references_test() {
  let action = {
    let code = "return function() return math.sqrt end"

    use refs <- glua.then(glua.eval(code))
    use ref <- glua.try(list.first(refs))
    use refs <- glua.then(glua.call_function(ref, []))
    use ref <- glua.try(list.first(refs))

    use refs <- glua.then(glua.call_function(ref, [glua.int(400)]))
    use ref <- glua.try(list.first(refs))
    use result <- glua.then(glua.dereference(ref:, using: decode.float))
    assert result == 20.0
    glua.success(Nil)
  }
  let assert Ok(_) = glua.run(glua.new(), action)
}

pub fn format_error_test() {
  let lua = glua.new()

  let assert Error(e) = glua.run(lua, glua.eval("1 +"))
  assert glua.format_error(e)
    == "Lua compile error: \n\nFailed to parse: error on line 1: syntax error before: 1"

  let assert Error(e) = glua.run(lua, glua.eval("assert(false)"))
  assert glua.format_error(e)
    == "Lua runtime exception: Assertion failed with message: assertion failed\n\nLine 1: assert(false)"

  let assert Error(e) =
    glua.run(lua, glua.eval("local a = true; local b = 1 * a"))
  assert glua.format_error(e)
    == "Lua runtime exception: Bad arithmetic expression: 1 * true"

  let assert Error(e) = glua.run(lua, glua.get(keys: ["non_existent"]))
  assert glua.format_error(e) == "Key \"non_existent\" not found"

  let assert Error(e) = glua.run(lua, glua.load_file("non_existent_file"))
  assert glua.format_error(e)
    == "Lua source file \"non_existent_file\" not found"

  let action = {
    use refs <- glua.then(glua.eval("return 1 + 1"))
    use ref <- glua.try(list.first(refs))
    use _ <- glua.then(glua.dereference(ref:, using: decode.string))
    panic as "unreachable"
  }
  let assert Error(e) = glua.run(glua.new(), action)
  assert glua.format_error(e) == "Expected String, but found Int"

  let assert Error(e) = glua.run(glua.new(), glua.failure(1))
  assert glua.format_error(e) == "1"
}

pub fn decode_function_test() {
  let lua_sqrt = {
    use ref <- glua.then(glua.get(keys: ["math", "sqrt"]))
    glua.dereference(ref:, using: glua.function_decoder())
  }

  let assert Ok(_) =
    glua.run(glua.new(), {
      use fun <- glua.then(lua_sqrt)
      use ret <- glua.then(fun([glua.int(9)]))
      use ref <- glua.try(list.first(ret))
      use result <- glua.map(glua.dereference(ref:, using: decode.float))

      assert result == 3.0
      Nil
    })

  let assert Error(glua.LuaRuntimeException(_, _)) =
    glua.run(glua.new(), {
      use fun <- glua.then(lua_sqrt)
      fun([])
    })

  let code =
    "
  local function fold(tbl, initial, cb)
    local acc = initial
    for _, v in ipairs(tbl) do
      local new_acc = cb(acc, v)
      acc = new_acc
   end
   return acc
  end

  return fold
"

  let lua_fold = {
    use ret <- glua.then(glua.eval(code:))
    use ref <- glua.try(list.first(ret))
    glua.dereference(ref:, using: glua.function_decoder())
  }

  let assert Ok(_) =
    glua.run(glua.new(), {
      use tbl <- glua.then(
        list.index_map([3, 9, 27], fn(x, i) { #(glua.int(i + 1), glua.int(x)) })
        |> glua.table,
      )

      let callback =
        fn(args) {
          use args <- glua.map(glua.fold(args, glua.dereference(_, decode.int)))
          let assert [acc, v] = args
          glua.int(acc * v)
          |> list.wrap
        }
        |> glua.function

      use fun <- glua.then(lua_fold)
      use ret <- glua.then(fun([tbl, glua.int(1), callback]))
      use ref <- glua.try(list.first(ret))
      use result <- glua.map(glua.dereference(ref:, using: decode.int))
      assert result == 729
      Nil
    })

  let assert Error(glua.LuaRuntimeException(exn, _)) =
    glua.run(glua.new(), {
      use fun <- glua.then(lua_fold)
      use tbl <- glua.then(
        list.index_map([3, 9, 27], fn(x, i) { #(glua.int(i + 1), glua.int(x)) })
        |> glua.table,
      )
      fun([tbl, glua.int(1)])
    })
  assert exn == glua.UndefinedFunction("nil")

  let lua_table_unpack = {
    use ref <- glua.then(glua.get(keys: ["table", "unpack"]))
    glua.dereference(ref:, using: glua.function_decoder())
  }

  let assert Ok(_) =
    glua.run(glua.new(), {
      use fun <- glua.then(lua_table_unpack)
      use tbl <- glua.then(
        ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
        |> list.index_map(fn(l, i) { #(glua.int(i + 1), glua.string(l)) })
        |> glua.table,
      )

      use ret <- glua.then(fun([tbl, glua.int(4), glua.int(8)]))
      use result <- glua.then(
        glua.fold(ret, glua.dereference(_, using: decode.string)),
      )

      assert result == ["d", "e", "f", "g", "h"]

      use ret <- glua.then(fun([tbl, glua.int(8)]))
      use result <- glua.then(
        glua.fold(ret, glua.dereference(_, using: decode.string)),
      )
      assert result == ["h", "i", "j"]
      glua.success(Nil)
    })

  let assert Error(glua.LuaRuntimeException(_, _)) =
    glua.run(glua.new(), {
      use fun <- glua.then(lua_table_unpack)
      fun([])
    })

  let code = "return function() error('some error') end"

  let assert Error(glua.LuaRuntimeException(exn, _)) =
    glua.run(glua.new(), {
      use ret <- glua.then(glua.eval(code:))
      use ref <- glua.try(list.first(ret))
      use fun <- glua.then(glua.dereference(
        ref:,
        using: glua.function_decoder(),
      ))
      fun([])
    })

  assert exn == glua.ErrorCall("some error", option.None)

  let code = "return function() return 3 * true end"
  let assert Error(glua.LuaRuntimeException(exn, _)) =
    glua.run(glua.new(), {
      use ret <- glua.then(glua.eval(code:))
      use ref <- glua.try(list.first(ret))
      use fun <- glua.then(glua.dereference(
        ref:,
        using: glua.function_decoder(),
      ))
      fun([])
    })

  assert exn == glua.BadArith("*", ["3", "true"])
}
