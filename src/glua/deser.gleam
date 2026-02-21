//// The deserialize API is similar to the gleam/dynamic/decode API but has some differences.
////
//// The main difference is that it can change the state of a lua program due to metatables.
//// If you do not wish to keep the changed state, discard the new state.

import gleam/bit_array
import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/string
import glua.{type Lua, type Value}

pub opaque type Deserializer(t) {
  Deserializer(function: fn(Lua, Value) -> Return(t))
}

pub type DeserializeError {
  DeserializeError(expected: String, found: String, path: List(Value))
}

type Return(t) =
  #(t, List(DeserializeError))

pub fn field(
  field_path: Value,
  field_decoder: Deserializer(t),
  next: fn(t) -> Deserializer(final),
) -> Deserializer(final) {
  subfield([field_path], field_decoder, next)
}

pub fn subfield(
  field_path: List(Value),
  field_decoder: Deserializer(t),
  next: fn(t) -> Deserializer(final),
) -> Deserializer(final) {
  Deserializer(function: fn(lua, data) {
    let #(out, errors1) =
      index_into(
        lua,
        field_path,
        [],
        field_decoder.function,
        data,
        fn(lua, data, position) {
          let #(default, _) = field_decoder.function(lua, data)
          #(default, [DeserializeError("Field", "Nothing", [])])
          |> push_path(list.reverse(position))
        },
      )
    let #(out, errors2) = next(out).function(lua, data)
    #(out, list.append(errors1, errors2))
  })
}

fn index_into(
  lua: Lua,
  path: List(Value),
  position: List(Value),
  inner: fn(Lua, Value) -> Return(b),
  data: Value,
  handle_miss: fn(Lua, Value, List(Value)) -> Return(b),
) -> Return(b) {
  case path {
    [] -> {
      data
      |> inner(lua, _)
      |> push_path(list.reverse(position))
    }

    [key, ..path] -> {
      case classify(data) {
        "Table" ->
          case get_table_key(lua, data, key) {
            Ok(#(lua, data)) -> {
              index_into(lua, path, [key, ..position], inner, data, handle_miss)
            }
            Error(Nil) -> {
              handle_miss(lua, data, [key, ..position])
            }
          }
        class -> {
          let #(default, _) = inner(lua, data)
          #(default, [DeserializeError("Table", class, [])])
          |> push_path(list.reverse(position))
        }
      }
    }
  }
}

pub fn run(
  lua: Lua,
  data: Value,
  deser: Deserializer(t),
) -> Result(t, List(DeserializeError)) {
  let #(maybe_invalid_data, errors) = deser.function(lua, data)
  case errors {
    [] -> Ok(maybe_invalid_data)
    [_, ..] -> Error(errors)
  }
}

/// Puts all values in a MultiValue, a special container that is only addressable with `deser.item`
pub fn run_multi(lua: Lua, data: List(Value), deser: Deserializer(t)) {
  let list = new_mval(data)
  run(lua, list, deser)
}

@external(erlang, "glua_ffi", "new_mval")
fn new_mval(values: List(Value)) -> Value

pub fn item(
  field_path: Int,
  field_decoder: Deserializer(t),
  next: fn(t) -> Deserializer(final),
) -> Deserializer(final) {
  Deserializer(fn(lua, data) {
    let class = classify(data)
    let pos = glua.string("<MultiVal #" <> int.to_string(field_path) <> ">")

    let fail = fn(error) {
      let #(default, _) = field_decoder.function(lua, data)
      let #(out, errors) = next(default).function(lua, data)
      #(out, list.append([error], errors))
    }
    use <- bool.lazy_guard(class != "MultiValue", fn() {
      fail(DeserializeError("MultiValue", classify(data), [pos]))
    })
    case get_entry(data, field_path) {
      Ok(val) -> {
        let #(out, errors1) =
          val |> field_decoder.function(lua, _) |> push_path([pos])
        let #(out, errors2) = next(out).function(lua, data)
        #(out, list.append(errors1, errors2))
      }
      Error(Nil) -> fail(DeserializeError("Field", "Nothing", [pos]))
    }
  })
}

@external(erlang, "glua_ffi", "get_entry")
fn get_entry(mval: Value, idx: Int) -> Result(Value, Nil)

pub fn error_to_string(error: DeserializeError) {
  "Expected "
  <> error.expected
  <> " got "
  <> error.found
  <> " at ["
  <> error.path |> list.map(string.inspect) |> string.join(", ")
  <> "]"
}

pub fn at(path: List(Value), inner: Deserializer(a)) -> Deserializer(a) {
  Deserializer(function: fn(lua, data) {
    index_into(lua, path, [], inner.function, data, fn(lua, data, position) {
      let #(default, _) = inner.function(lua, data)
      #(default, [DeserializeError("Field", "Nothing", [])])
      |> push_path(list.reverse(position))
    })
  })
}

@external(erlang, "glua_ffi", "get_table_key")
fn get_table_key(
  lua: Lua,
  table: Value,
  key: Value,
) -> Result(#(Lua, Value), Nil)

fn push_path(layer: Return(t), path: List(Value)) -> Return(t) {
  let errors =
    list.map(layer.1, fn(error) {
      DeserializeError(..error, path: list.append(path, error.path))
    })
  #(layer.0, errors)
}

pub fn success(data: t) -> Deserializer(t) {
  Deserializer(function: fn(_lua, _) { #(data, []) })
}

pub fn deser_error(
  expected expected: String,
  found found: Value,
) -> List(DeserializeError) {
  [DeserializeError(expected: expected, found: classify(found), path: [])]
}

@external(erlang, "glua_ffi", "classify")
pub fn classify(a: anything) -> String

pub fn optional_field(
  key: Value,
  default: t,
  field_decoder: Deserializer(t),
  next: fn(t) -> Deserializer(final),
) -> Deserializer(final) {
  Deserializer(function: fn(lua, data) {
    let class = classify(data)
    use <- bool.lazy_guard(class != "Table", fn() {
      next(default).function(lua, data)
    })
    let #(out, errors1) =
      case get_table_key(lua, data, key) {
        Ok(#(lua, data)) -> {
          field_decoder.function(lua, data)
        }
        Error(Nil) -> #(default, [])
      }
      |> push_path([key])
    let #(out, errors2) = next(out).function(lua, data)
    #(out, list.append(errors1, errors2))
  })
}

pub fn optionally_at(
  path: List(Value),
  default: a,
  inner: Deserializer(a),
) -> Deserializer(a) {
  Deserializer(function: fn(lua, data) {
    index_into(lua, path, [], inner.function, data, fn(_, _, _) {
      #(default, [])
    })
  })
}

fn run_dynamic_function(
  lua: Lua,
  data: Value,
  expected: String,
  zero: t,
) -> Return(t) {
  let got = classify(data)
  case got == expected {
    True -> #(decode(data, lua), [])
    False -> #(zero, [
      DeserializeError(expected, got, []),
    ])
  }
}

/// Warning: Can panic
@external(erlang, "luerl", "decode")
fn decode(a: Value, lua: Lua) -> a

pub const string: Deserializer(String) = Deserializer(deser_string)

fn deser_string(lua, data: Value) -> Return(String) {
  run_dynamic_function(lua, data, "String", "")
}

pub const byte_string: Deserializer(BitArray) = Deserializer(deser_byte_string)

fn deser_byte_string(lua, data: Value) -> Return(BitArray) {
  run_dynamic_function(lua, data, "ByteString", bit_array.from_string(""))
}

pub const bool: Deserializer(Bool) = Deserializer(deser_bool)

fn deser_bool(lua, data: Value) -> Return(Bool) {
  run_dynamic_function(lua, data, "Bool", True)
}

pub const number: Deserializer(Float) = Deserializer(deser_num)

fn deser_num(lua, data: Value) -> Return(Float) {
  let got = classify(data)
  case got {
    "Float" -> #(decode(data, lua), [])
    "Int" -> {
      let int: Int = decode(data, lua)
      #(int.to_float(int), [])
    }
    _ -> #(0.0, [
      DeserializeError("Number", got, []),
    ])
  }
}

pub const int: Deserializer(Int) = Deserializer(deser_int)

fn deser_int(lua, data: Value) -> Return(Int) {
  let got = classify(data)
  let error = #(0, [
    DeserializeError("Int", got, []),
  ])
  case got {
    "Float" -> {
      let float: Float = decode(data, lua)
      let int = float.truncate(float)
      case int.to_float(int) == float {
        True -> #(int, [])
        False -> error
      }
    }
    "Int" -> {
      #(decode(data, lua), [])
    }
    _ -> error
  }
}

pub const raw: Deserializer(Value) = Deserializer(decode_raw)

fn decode_raw(_lua, data: Value) -> Return(Value) {
  let class = classify(data)
  case class {
    "Unknown"
    | // Disallow smuggling MultiValues out
      "MultiValue" -> #(glua.nil(), [DeserializeError("Any", class, [])])
    _ -> #(data, [])
  }
}

pub const userdata: Deserializer(dynamic.Dynamic) = Deserializer(
  deser_user_defined,
)

@external(erlang, "glua_ffi", "unwrap_userdata")
fn unwrap_userdata(a: userdata) -> Result(dynamic.Dynamic, Nil)

fn deser_user_defined(lua, data: Value) -> Return(dynamic.Dynamic) {
  let got = classify(data)
  let error = #(dynamic.nil(), [DeserializeError("UserData", got, [])])
  use <- bool.guard(got != "UserData", error)
  use <- bool.guard(
    !userdata_exists(lua, data),
    #(dynamic.nil(), [
      DeserializeError("UserData", "NonexistentUserData", []),
    ]),
  )
  case unwrap_userdata(decode(data, lua)) {
    Ok(dyn) -> #(dyn, [])
    Error(Nil) -> error
  }
}

pub const function: Deserializer(glua.Function) = Deserializer(deser_function)

fn deser_function(_lua: Lua, data: Value) -> Return(glua.Function) {
  let got = classify(data)
  case got == "Function" {
    True -> #(coerce_funciton(data), [])
    False -> #(coerce_funciton(Nil), [
      DeserializeError("Function", got, []),
    ])
  }
}

@external(erlang, "glua_ffi", "coerce")
fn coerce_funciton(func: anything) -> glua.Function

/// Strictly decodes a list
/// 1. first element must start with 1
/// 2. no gaps
/// 3. no non number keys
pub fn list(of inner: Deserializer(a)) -> Deserializer(List(a)) {
  Deserializer(fn(lua, data) {
    let class = classify(data)
    let not_table_list = #([], [DeserializeError("TableList", class, [])])
    case class {
      "Table" -> {
        use <- bool.guard(
          !table_exists(lua, data),
          #([], [
            DeserializeError("TableList", "NonexistentTable", []),
          ]),
        )
        let res =
          get_table_list_transform(lua, data, #([], []), fn(it, acc) {
            case acc.1 {
              [] -> {
                case inner.function(lua, it) {
                  #(value, []) -> {
                    #(list.prepend(acc.0, value), acc.1)
                  }
                  #(_, errors) ->
                    push_path(#([], errors), [glua.string("items")])
                }
              }
              [_, ..] -> acc
            }
          })
        case res {
          Ok(it) -> it
          Error(Nil) -> not_table_list
        }
      }
      _ -> not_table_list
    }
  })
}

@external(erlang, "glua_ffi", "get_table_list_transform")
fn get_table_list_transform(
  lua: Lua,
  table: Value,
  accumulator: acc,
  func: fn(Value, acc) -> acc,
) -> Result(acc, Nil)

/// An ipairs style list decoder.
/// This function consults __index
pub fn ipairs(
  of inner: Deserializer(a),
  limit limit: Int,
) -> Deserializer(List(a)) {
  Deserializer(function: fn(lua, data) {
    let class = classify(data)
    case class {
      "Table" -> {
        use <- bool.guard(
          !table_exists(lua, data),
          #([], [
            DeserializeError("Table", "NonexistentTable", []),
          ]),
        )
        case ipair_inner(data, [], 1, lua, inner, limit) {
          Ok(ok) -> #(ok, [])
          Error(errs) -> #([], errs)
        }
      }
      _ -> #([], [DeserializeError("Table", class, [])])
    }
  })
}

fn ipair_inner(
  table: Value,
  out: List(a),
  idx: Int,
  lua: Lua,
  deser: Deserializer(a),
  limit: Int,
) -> Result(List(a), List(DeserializeError)) {
  use <- bool.lazy_guard(idx > limit, fn() {
    Error([DeserializeError("Table", "UnprocessableTable", [])])
  })
  case get_table_key(lua, table, glua.int(idx)) {
    Ok(#(lua, val)) -> {
      case deser.function(lua, val) {
        #(value, []) -> {
          ipair_inner(table, [value, ..out], idx + 1, lua, deser, limit)
        }
        #(_, errors) -> {
          push_path(#([], errors), [glua.string("items")]).1
          |> Error
        }
      }
    }
    Error(Nil) -> Ok(list.reverse(out))
  }
}

pub fn dict(
  key: Deserializer(key),
  value: Deserializer(value),
) -> Deserializer(Dict(key, value)) {
  Deserializer(fn(lua, data) {
    let class = classify(data)
    case class {
      "Table" -> {
        use <- bool.guard(
          !table_exists(lua, data),
          #(dict.new(), [DeserializeError("Table", "NonexistentTable", [])]),
        )
        get_table_transform(lua, data, #(dict.new(), []), fn(k, v, a) {
          // If there are any errors from previous key-value pairs then we
          // don't need to run the decoders, instead return the existing acc.
          case a.1 {
            [] -> fold_dict(lua, a, k, v, key.function, value.function)
            [_, ..] -> a
          }
        })
      }
      _ -> #(dict.new(), [DeserializeError("Table", class, [])])
    }
  })
}

@external(erlang, "glua_ffi", "table_exists")
fn table_exists(state: Lua, table: Value) -> Bool

@external(erlang, "glua_ffi", "userdata_exists")
fn userdata_exists(state: Lua, userdata: Value) -> Bool

/// Preconditions: `table` is a lua table
@external(erlang, "glua_ffi", "get_table_transform")
fn get_table_transform(
  lua: Lua,
  table: Value,
  accumulator: acc,
  func: fn(Value, Value, acc) -> acc,
) -> acc

fn fold_dict(
  lua: Lua,
  acc: #(Dict(k, v), List(DeserializeError)),
  key: Value,
  value: Value,
  key_decoder: fn(Lua, Value) -> Return(k),
  value_decoder: fn(Lua, Value) -> Return(v),
) -> Return(Dict(k, v)) {
  // First we decode the key.
  case key_decoder(lua, key) {
    #(key, []) ->
      // Then we decode the value.
      case value_decoder(lua, value) {
        #(value, []) -> {
          // It worked! Insert the new key-value pair so we can move onto the next.
          let dict = dict.insert(acc.0, key, value)
          #(dict, acc.1)
        }
        #(_, errors) ->
          push_path(#(dict.new(), errors), [glua.string("values")])
      }
    #(_, errors) -> push_path(#(dict.new(), errors), [glua.string("keys")])
  }
}

pub fn optional(inner: Deserializer(a)) -> Deserializer(Option(a)) {
  Deserializer(function: fn(lua, data) {
    case classify(data) {
      "Nil" -> #(option.None, [])
      _ -> {
        let #(data, errors) = inner.function(lua, data)
        #(option.Some(data), errors)
      }
    }
  })
}

pub fn map(decoder: Deserializer(a), transformer: fn(a) -> b) -> Deserializer(b) {
  Deserializer(function: fn(lua, d) {
    let #(data, errors) = decoder.function(lua, d)
    #(transformer(data), errors)
  })
}

pub fn map_errors(
  decoder: Deserializer(a),
  transformer: fn(List(DeserializeError)) -> List(DeserializeError),
) -> Deserializer(a) {
  Deserializer(function: fn(lua, d) {
    let #(data, errors) = decoder.function(lua, d)
    #(data, transformer(errors))
  })
}

pub fn collapse_errors(
  decoder: Deserializer(a),
  name: String,
) -> Deserializer(a) {
  Deserializer(function: fn(lua, dynamic_data) {
    let #(data, errors) as layer = decoder.function(lua, dynamic_data)
    case errors {
      [] -> layer
      [_, ..] -> #(data, deser_error(name, dynamic_data))
    }
  })
}

pub fn then(
  decoder: Deserializer(a),
  next: fn(Lua, a) -> Deserializer(b),
) -> Deserializer(b) {
  Deserializer(function: fn(lua, dynamic_data) {
    let #(data, errors) = decoder.function(lua, dynamic_data)
    let decoder = next(lua, data)
    let #(data, _) as layer = decoder.function(lua, dynamic_data)
    case errors {
      [] -> layer
      [_, ..] -> #(data, errors)
    }
  })
}

pub fn one_of(
  first: Deserializer(a),
  or alternatives: List(Deserializer(a)),
) -> Deserializer(a) {
  Deserializer(function: fn(lua, dynamic_data) {
    let #(_, errors) as layer = first.function(lua, dynamic_data)
    case errors {
      [] -> layer
      [_, ..] -> run_decoders(dynamic_data, lua, layer, alternatives)
    }
  })
}

fn run_decoders(
  data: Value,
  lua: Lua,
  failure: Return(a),
  decoders: List(Deserializer(a)),
) -> Return(a) {
  case decoders {
    [] -> failure

    [decoder, ..decoders] -> {
      let #(_, errors) as layer = decoder.function(lua, data)
      case errors {
        [] -> layer
        [_, ..] -> run_decoders(data, lua, failure, decoders)
      }
    }
  }
}

pub fn failure(zero: a, expected: String) -> Deserializer(a) {
  Deserializer(function: fn(_lua, d) { #(zero, deser_error(expected, d)) })
}

pub fn recursive(inner: fn() -> Deserializer(a)) -> Deserializer(a) {
  Deserializer(function: fn(lua, data) {
    let decoder = inner()
    decoder.function(lua, data)
  })
}
