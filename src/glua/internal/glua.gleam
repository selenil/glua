/// Represents an instance of the Lua VM.
pub type Lua

pub type Value

pub type Function

@external(erlang, "glua_ffi", "coerce_nil")
pub fn nil() -> Value

@external(erlang, "glua_ffi", "coerce")
pub fn string(v: String) -> Value

@external(erlang, "glua_ffi", "coerce")
pub fn int(v: Int) -> Value
