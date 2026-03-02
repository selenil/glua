import glua
import glua/lib
import glua/lib/bit32
import glua/lib/debug
import glua/lib/io
import glua/lib/math
import glua/lib/os
import glua/lib/package
import glua/lib/string
import glua/lib/table
import glua/lib/utf8

/// Checks to see if a value matches a value at the given path.
fn check(val: glua.Value, path: List(String)) {
  let assert Ok(found) = glua.run(glua.new(), glua.get(path))
  assert val == found
}

pub fn lib_basic_test() {
  check(lib.lua_version |> glua.string, ["_VERSION"])
  check(lib.assert_(), ["assert"])
  check(lib.collect_garbage(), ["collectgarbage"])
  check(lib.do_file(), ["dofile"])
  check(lib.eprint(), ["eprint"])
  check(lib.error(), ["error"])
  check(lib.get_meta_table(), ["getmetatable"])
  check(lib.ipairs(), ["ipairs"])
  check(lib.load(), ["load"])
  check(lib.load_file(), ["loadfile"])
  check(lib.load_string(), ["loadstring"])
  check(lib.next(), ["next"])
  check(lib.pairs(), ["pairs"])
  check(lib.pcall(), ["pcall"])
  check(lib.print(), ["print"])
  check(lib.raw_equal(), ["rawequal"])
  check(lib.raw_get(), ["rawget"])
  check(lib.raw_len(), ["rawlen"])
  check(lib.raw_set(), ["rawset"])
  check(lib.select(), ["select"])
  check(lib.set_meta_table(), ["setmetatable"])
  check(lib.to_number(), ["tonumber"])
  check(lib.to_string(), ["tostring"])
  check(lib.type_(), ["type"])
  check(lib.unpack(), ["unpack"])
  check(lib.require(), ["require"])
}

pub fn lib_package_test() {
  // luerl:get_table_keys/2 uses ints to index lists
  check(package.preload_searcher(), ["package", "searchers", coerce_string(1)])
  check(package.lua_searcher(), [
    "package",
    "searchers",
    coerce_string(2),
  ])
  check(package.search_path(), ["package", "searchpath"])
}

@external(erlang, "glua_ffi", "coerce")
fn coerce_string(item: Int) -> String

pub fn lib_bit32_test() {
  check(bit32.band(), ["bit32", "band"])
  check(bit32.bnot(), ["bit32", "bnot"])
  check(bit32.bor(), ["bit32", "bor"])
  check(bit32.btest(), ["bit32", "btest"])
  check(bit32.bxor(), ["bit32", "bxor"])
  check(bit32.lshift(), ["bit32", "lshift"])
  check(bit32.rshift(), ["bit32", "rshift"])
  check(bit32.arshift(), ["bit32", "arshift"])
  check(bit32.lrotate(), ["bit32", "lrotate"])
  check(bit32.rrotate(), ["bit32", "rrotate"])
  check(bit32.extract(), ["bit32", "extract"])
  check(bit32.replace(), ["bit32", "replace"])
}

pub fn lib_io_test() {
  check(io.flush(), ["io", "flush"])
  check(io.write(), ["io", "write"])
}

pub fn lib_math_test() {
  check(glua.float(math.huge), ["math", "huge"])
  check(glua.float(math.pi), ["math", "pi"])
  check(glua.int(math.max_integer), ["math", "maxinteger"])
  check(glua.int(math.min_integer), ["math", "mininteger"])
  check(math.abs(), ["math", "abs"])
  check(math.acos(), ["math", "acos"])
  check(math.asin(), ["math", "asin"])
  check(math.atan(), ["math", "atan"])
  check(math.atan2(), ["math", "atan2"])
  check(math.ceil(), ["math", "ceil"])
  check(math.cos(), ["math", "cos"])
  check(math.cosh(), ["math", "cosh"])
  check(math.deg(), ["math", "deg"])
  check(math.exp(), ["math", "exp"])
  check(math.floor(), ["math", "floor"])
  check(math.fmod(), ["math", "fmod"])
  check(math.frexp(), ["math", "frexp"])
  check(math.ldexp(), ["math", "ldexp"])
  check(math.log(), ["math", "log"])
  check(math.log10(), ["math", "log10"])
  check(math.max(), ["math", "max"])
  check(math.min(), ["math", "min"])
  check(math.modf(), ["math", "modf"])
  check(math.pow(), ["math", "pow"])
  check(math.rad(), ["math", "rad"])
  check(math.random(), ["math", "random"])
  check(math.random_seed(), ["math", "randomseed"])
  check(math.sin(), ["math", "sin"])
  check(math.sinh(), ["math", "sinh"])
  check(math.sqrt(), ["math", "sqrt"])
  check(math.tan(), ["math", "tan"])
  check(math.tanh(), ["math", "tanh"])
  check(math.to_integer(), ["math", "tointeger"])
  check(math.type_(), ["math", "type"])
}

pub fn lib_debug_test() {
  check(debug.get_meta_table(), ["debug", "getmetatable"])
  check(debug.get_user_value(), ["debug", "getuservalue"])
  check(debug.set_meta_table(), ["debug", "setmetatable"])
  check(debug.set_user_value(), ["debug", "setuservalue"])
}

pub fn lib_table_test() {
  check(table.concat(), ["table", "concat"])
  check(table.insert(), ["table", "insert"])
  check(table.pack(), ["table", "pack"])
  check(table.remove(), ["table", "remove"])
  check(table.sort(), ["table", "sort"])
  check(table.unpack(), ["table", "unpack"])
}

@external(erlang, "glua_ffi", "coerce")
fn to_string(bit_string: BitArray) -> glua.Value

pub fn lib_utf8_test() {
  check(utf8.charpattern |> to_string, ["utf8", "charpattern"])
  check(utf8.char(), ["utf8", "char"])
  check(utf8.codes(), ["utf8", "codes"])
  check(utf8.codepoint(), ["utf8", "codepoint"])
  check(utf8.len(), ["utf8", "len"])
  check(utf8.offset(), ["utf8", "offset"])
}

pub fn lib_string_test() {
  check(string.byte(), ["string", "byte"])
  check(string.char(), ["string", "char"])
  check(string.dump(), ["string", "dump"])
  check(string.find(), ["string", "find"])
  check(string.format(), ["string", "format"])
  check(string.gmatch(), ["string", "gmatch"])
  check(string.gsub(), ["string", "gsub"])
  check(string.len(), ["string", "len"])
  check(string.lower(), ["string", "lower"])
  check(string.match(), ["string", "match"])
  check(string.rep(), ["string", "rep"])
  check(string.reverse(), ["string", "reverse"])
  check(string.sub(), ["string", "sub"])
  check(string.upper(), ["string", "upper"])
}

pub fn lib_os_test() {
  check(os.clock(), ["os", "clock"])
  check(os.date(), ["os", "date"])
  check(os.difftime(), ["os", "difftime"])
  check(os.execute(), ["os", "execute"])
  check(os.exit(), ["os", "exit"])
  check(os.getenv(), ["os", "getenv"])
  check(os.remove(), ["os", "remove"])
  check(os.rename(), ["os", "rename"])
  check(os.time(), ["os", "time"])
  check(os.tmpname(), ["os", "tmpname"])
}
