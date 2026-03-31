# Glua

A library for embedding Lua in Gleam applications!

[![Package Version](https://img.shields.io/hexpm/v/glua)](https://hex.pm/packages/glua)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glua/)

```sh
gleam add glua@2
```

## Usage

### Executing Lua code

```gleam
let code = "
function greet()
  return 'Hello from Lua!'
end

return greet()
"
let assert Ok([result]) =
  glua.eval(code:)
  |> glua.returning_multi(decode.string)
  |> glua.run(glua.new(), _)

assert result == "Hello from Lua!"
```

### Parsing a chunk, then executing it

```gleam
let code = "return 'this is a chunk of Lua code'"

let assert Ok([result]) =
  glua.load(code:)
  |> glua.then(glua.eval_chunk)
  |> glua.returning_multi(decode.string)
  |> glua.run(glua.new(), _)

assert result == "this is a chunk of Lua code"
```

### Executing Lua files

```gleam
let assert Ok([n, m]) =
  glua.eval_file(path: "./my_lua_files/two_numbers.lua")
  |> glua.returning_multi(decode.int)
  |> glua.run(glua.new(), _)

assert n == 1 && m == 2
```

### Sandboxing

```gleam
let assert Ok(lua) = glua.new() |> glua.sandbox(["os", "execute"])
let assert Error(glua.LuaRuntimeException(exception, _)) =
  glua.run(
    glua.new(),
    glua.eval(code: "os.execute('rm -f important_file'); return 0"),
  )

// 'important_file' was not deleted
assert exception == glua.ErrorCall(["os.execute is sandboxed"])
```

### Getting values from Lua

```gleam
let assert Ok(version) =
  glua.get(keys: ["_VERSION"])
  |> glua.returning(decode.string)
  |> glua.run(glua.new(), _)

assert version == "Lua 5.3"
```

### Setting values in Lua

```gleam
// we need to encode any value we want to pass to Lua
let value = glua.string("my_value")

// `keys` is the full path to where the value will be set
// and any intermediate table will be created if it is not present
let keys = ["my_table", "my_value"]

let action = {
  use _ <- glua.then(glua.set(keys, value))

  // now we can get the value
  use value1 <- glua.then(
    glua.get(keys) |> glua.returning(decode.string)
  )

  // or return it from a Lua script
  use value2 <- glua.then(
    glua.eval(code: "return my_table.my_value") |> glua.returning(decode.string)
  )

  glua.success([value1, value2])
}

let assert Ok([v1, v2]) = glua.run(glua.new(), action)
assert v1 == "my_value"
assert v2 == v1
```

```gleam
// we can also encode a list of tuples as a table to set it in Lua
let my_table =
  [#("my_first_value", 1.2), #("my_second_value", 2.1)]
  |> list.map(fn(pair) { #(glua.string(pair.0), glua.float(pair.1)) })

let action = {
  use tbl <- glua.then(glua.table(my_table))
  use _ <- glua.then(glua.set(["my_table"], tbl))

  // now we can get its values
  glua.eval(code: "return my_table.my_second_value")
  |> glua.returning_multi(decode.float)
}

let assert Ok([result]) = glua.run(glua.new(), action)
assert result == 2.1 
```

### Calling Lua functions from Gleam

```gleam
// we need to encode each argument we pass to a Lua function
let args = list.map([1, 20, 7, 18], glua.int)

let action = {
  use fun <- glua.then(
    glua.get(["math", "max"])
  )

  glua.call_function(fun, args)
  |> glua.returning_multi(decode.int)
}

let assert Ok([result]) = glua.run(glua.new(), action)
assert result == 20

// `glua.call_function_by_name` is a shorthand for `glua.get` followed by `glua.call_function`
let assert Ok([result]) =
  glua.run(glua.new(), glua.call_function_by_name(["math", "max"], args))
assert result == 20
```

### Exposing Gleam functions to Lua

```gleam
let fun = fn(args: List(glua.Value)) {
  use args <- glua.then(
    glua.fold(args, glua.dereference(_, decode.float))
  )
  let assert [x, min, max] = args

  let result = float.clamp(x, min, max)
  glua.success([glua.float(result)])
}
|> glua.function

let keys = ["my_functions", "clamp"]

let args = list.map([2.3, 1.2, 2.1], glua.float)

let action = {
  use _ <- glua.then(glua.set(keys, fun))

  glua.call_function_by_name(keys, args)
  |> glua.returning_multi(decode.float)
}

let assert Ok([result]) = glua.run(glua.new(), action)
assert result == 2.1
```

Further documentation can be found at <https://hexdocs.pm/glua>.

## Credits

- [Luerl](https://github.com/rvirding/luerl): This library is powered by Luerl under the hood.
- [Elixir's Lua library](https://github.com/tv-labs/lua) - This library API is inspired by Elixir's Lua library.
