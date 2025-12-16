# Glua

A library for embedding Lua in Gleam applications!

[![Package Version](https://img.shields.io/hexpm/v/glua)](https://hex.pm/packages/glua)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glua/)

```sh
gleam add glua@1
```

## Usage

The central concept of this library is the `Operation` type, which represents an operation that can be executed within a
Lua state. The `Operation` type is generic with only one parameter: `a`, which is the type of the value the operation
returns in case everything suceeded during execution. Things like executing Lua code, loading Lua source files or mutating
the Lua globals are represented using the `Operation` type.

To execute an `Operation`  `glua.do` passing the Lua state you want to use and the operation in cuestion.
New Lua states are created using `glua.new` or `glua.new_sandboxed`. 

Multiple operations can be composed using `glua.chain`, which takes a callback describing what to do with the result value of
the operation. If one operation fails inside a chain, the rest are not executed and the error is returned instead, stopping the chain.

### Executing Lua code

```gleam
let code = "
function greet()
  return 'Hello from Lua!'
end

return greet()
"

let assert Ok([result]) = glua.do(glua.new(), glua.eval(
  code:,
  using: decode.string
))

assert result == "Hello from Lua!"
```

### Parsing a chunk, then executing it

```gleam
let code = "return 'this is a chunk of Lua code'"

let assert Ok([result]) = glua.do(glua.new(), {
  use chunk <- glua.chain(glua.load(code:))
  glua.eval_chunk(chunk:, using: decode.string)
})

assert result == "this is a chunk of Lua code"
```

### Executing Lua files

```gleam
let assert Ok([n, m]) = glua.do(glua.new(), glua.eval_file(
  path: "./my_lua_files/two_numbers.lua"
  using: decode.int
))

assert n == 1 && m == 2
```

### Sandboxing

```gleam
let assert Ok(lua) = glua.new() |> glua.sandbox(["os", "execute"])
let assert Error(glua.LuaRuntimeException(exception, _)) = glua.do(lua, glua.eval(
  code: "os.execute('rm -f important_file'); return 0",
  using: decode.int
)

// 'important_file' was not deleted
assert exception == glua.ErrorCall(["os.execute is sandboxed"])
```

### Getting values from Lua

```gleam
let assert Ok(version) = glua.do(glua.new(), glua.get(
  keys: ["_VERSION"],
  using: decode.string
)

assert version == "Lua 5.3"
```

### Setting values in Lua

```gleam
// `keys` is the full path to where the value will be set
// and any intermediate table will be created if it is not present
let keys = ["my_table", "my_value"]

// we need to encode any value we want to pass to Lua
let prepare_state = {
  use value <- glua.chain(glua.string("my_value"))
  glua.set(keys:, value:)
}

// now we can get the value
let assert Ok(value) = glua.do(glua.new(), {
  use _ <- glua.chain(prepare_state)
  glua.get(keys:, using: decode.string)
})

// or return it from a Lua script
let assert Ok([returned]) = glua.do(glua.new(), {
  use _ <- glua.chain(prepare_state)
  glua.eval(code: "return my_table.my_value", using: decode.string)
})

assert value == "my_value"
assert returned == "my_value"
```

```gleam
// we can also encode a list of tuples as a table to set it in Lua
let my_table = [
  #("my_first_value", 1.2),
  #("my_second_value", 2.1)
]

// the function we use to encode the keys and the function we use to encode the values
let encoders = #(glua.string, glua.float)
let prepare_state = {
  use tbl <- glua.chain(glua.table(encoders, my_table))
  glua.set(["my_table"], tbl)
}

let assert Ok([result]) = glua.do(glua.new(), {
  use _ <- glua.chain(prepare_state)

  // now we can get its values
  glua.eval(
    code: "return my_table.my_second_value",
    using: decode.float
  )
})

assert result == 2.1 

// or we can get the whole table and decode it back to a list of tuples
assert glua.do(glua.new(), {
  use _ <- glua.chain(prepare_state)
  glua.get(
    keys: ["my_table"],
    using: glua.table_decoder(decode.string, decode.float)
)}) == Ok([
  #("my_first_value", 1.2),
  #("my_second_value", 2.1)
])
```

### Calling Lua functions from Gleam

```gleam
let make_args = {
  // we need to encode each argument we pass to a Lua function
  // `glua.list` encodes a list of values using a single encoder function
  glua.list(glua.int, [1, 20, 7, 18])
}

let assert Ok([result]) = glua.do(glua.new(), {
  // here we use `ref_get` instead of `get` because we need a reference to the function
  // and not a decoded value
  use ref <- glua.chain(glua.ref_get(
    keys: ["math", "max"]
  ))

  use args <- glua.chain(make_args)

  glua.call_function(
    ref:,
    args:,
    using: decode.int
  )
})

assert result == 20

// `glua.call_function_by_name` is a shorthand for `glua.ref_get` followed by `glua.call_function`
let assert Ok([result]) = glua.do(glua.new(), {
  use args <- glua.chain(make_args)
  
  glua.call_function_by_name(
    keys: ["math", "max"],
    args:,
    using: decode.int
  )
})

assert result == 20
```

### Exposing Gleam functions to Lua

```gleam
let make_fun = {
  glua.function(fn(args: List(dynamic.Dynamic)) {
    let assert [x, min, max] = args
    let assert Ok([x, min, max]) = list.try_map(
      [x, min, max],
      decode.run(_, decode.float)
    )

    let result = float.clamp(x, min, max)
    glua.list(glua.float, [result])
  })
}
  
let keys = ["my_functions", "clamp"]

let assert Ok([result]) = glua.do(glua.new(), {
  use fun <- glua.chain(make_fun)
  use args <- glua.chain(glua.list(glua.float, [2.3, 1.2, 2.1]))
  use _ <- glua.chain(glua.set(keys:, value: fun))

  glua.call_function_by_name(
    keys:,
    args:,
    using: decode.float
  )})

assert result == 2.1
```

Further documentation can be found at <https://hexdocs.pm/glua>.

## Credits

- [Luerl](https://github.com/rvirding/luerl): This library is powered by Luerl under the hood.
- [Elixir's Lua library](https://github.com/tv-labs/lua) - This library API is inspired by Elixir's Lua library.
