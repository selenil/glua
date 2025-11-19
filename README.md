# Glua

A library for embedding Lua in Gleam applications!

[![Package Version](https://img.shields.io/hexpm/v/glua)](https://hex.pm/packages/glua)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glua/)

```sh
gleam add glua@1
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

let assert Ok(#(_state, [result])) = glua.eval(
  state: glua.new(),
  code:,
  using: decode.string
)

assert result == "Hello from Lua!"
```

### Parsing a chunk, then executing it

```gleam
let code = "return 'this is a chunk of Lua code'"
let assert Ok(#(state, chunk)) = glua.load(state: glua.new(), code:)
let assert Ok(#(_state, [result])) =
  glua.eval_chunk(state:, chunk:, using: decode.string)

assert result == "this is a chunk of Lua code"
```

### Executing Lua files

```gleam
let assert Ok(#(_state, [n, m])) = glua.eval_file(
  state: glua.new(),
  path: "./my_lua_files/two_numbers.lua"
  using: decode.int
)

assert n == 1 && m == 2
```

### Getting values from Lua

```gleam
let assert Ok(version) = glua.get(
  state: glua.new(),
  keys: ["_VERSION"],
  using: decode.string
)

assert version == "Lua 5.3"
```

### Setting values in Lua

```gleam
// we need to encode any value we want to pass to Lua
let #(lua, encoded) = glua.string(glua.new(), "my_value")

// `keys` is the full path to where the value will be set
// and any intermediate table will be created if it is not present
let keys = ["my_table", "my_value"]
let assert Ok(lua) = glua.set(state: lua, keys:, value: encoded)

// now we can get the value
let assert Ok(value) = glua.get(state: lua, keys:, using: decode.string)

// or return it from a Lua script
let assert Ok(returned) = glua.eval(
  state: lua,
  code: "return my_table.my_value",
  using: decode.string
)

assert value == returned == "my_value"
```

```gleam
// we can also encode a list of tuples as a table to set it in Lua
let my_table = [
  #("my_first_value", 1.2),
  #("my_second_value", 2.1)
]

// the function we use to encode the keys and the function we use to encode the values
let encoders = #(glua.string, glua.float)

let #(lua, encoded) = glua.new() |> glua.table(encoders, my_table)
let assert Ok(lua) = glua.set(state: lua, keys: ["my_table"], value: encoded)

// now we can get its values
let assert #(lua, [result]) = glua.eval(
  state: lua,
  code: "return my_table.my_second_value",
  using: decode.float
)

assert result == 2.1 

// or we can get the whole table and decode it back to a list of tuples
assert glua.get(
  state: lua,
  keys: ["my_table"],
  using: glua.table_decoder(decode.string, decode.bool)
) == Ok([
  #("my_first_value", 1.2),
  #("my_second_value", 2.1)
])
```

### Calling Lua functions from Gleam

```gleam
// here we use `ref_get` instead of `get` because we need a reference to the function
// and not a decoded value
let lua = glua.new()
let assert Ok(fun) = glua.ref_get(
  state: lua,
  keys: ["math", "max"]
)

// we need to encode each argument we pass to a Lua function
// `glua.list` encodes a list of values using a single encoder function
let args = glua.list(lua, glua.int, [1, 20, 7, 18])

let assert Ok(#(state, [result])) = glua.call_function(
  state: lua,
  ref: fun,
  args:,
  using: decode.int
)

assert result == 20

// `glua.call_function_by_name` is a shorthand for `glua.ref_get` followed by `glua.call_function`
let assert Ok(#(_state, [result])) = glua.call_function_by_name(
  state: lua,
  keys: ["math", "max"],
  args:,
  using: decode.int
)

assert result == 20
```

### Exposing Gleam functions to Lua

```gleam
let #(lua, fun) = {
  use lua, args <- glua.function(glua.new())

  let assert [x, min, max] = args
  let assert Ok([x, min, max]) = list.try_map(
    [x, min, max],
    decode.run(_, decode.float)
  )

  let result = float.clamp(x, min, max)

  glua.list(lua, glua.float, [result])
}

let keys = ["my_functions", "clamp"]

let assert Ok(lua) = glua.set(state: lua, keys:, value: fun)

let #(lua, args) = glua.list(lua, glua.float, [2.3, 1.2, 2.1])
let assert Ok(#(_lua, [result])) = glua.call_function_by_name(
  state: lua,
  keys:,
  args:,
  using: decode.float
)

assert result == 2.1
```

Further documentation can be found at <https://hexdocs.pm/glua>.

## Credits

- [Luerl](https://github.com/rvirding/luerl): This library is powered by Luerl under the hood.
- [Elixr's Lua library](https://github.com/tv-labs/lua) - This library API is inspired by Elixir's Lua library.
