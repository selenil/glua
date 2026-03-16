# Changelog

## [v2.0.0-rc.1] - 2026-03-16

- [glua] Changed encoders functions to not accept and return a Lua VM when is not needed.
- [glua] Added a `userdata` function to encode arbitary Gleam data into a value that can be passed to the Lua environment.
- [glua] Renamed `LuaError` to `Error`.
- [glua] Changed `Error` to take a type parameter and add a `CustomError` variant.
- [glua] Added an `error` and an `error_with_code` function to call the Lua `error` function from Gleam code.
- [glua] Added a `FileNotFound` variant to `Error`.
- [glua] Renamed `LuaCompilerException` to `LuaCompileFailure` and add the `LuaCompileError` to represent Lua compilation errors.
- [glua] Changed the parameter of the `UnknownError` variant to be of type `dynamic.Dynamic` instead of type `String`.
- [glua] Added a `UndefinedMethod` variant to `LuaRuntimeExceptionKind`.
- [glua] Added a `Badarg` variant to `LuaRuntimeExceptionKind`.
- [glua] Changed `KeyNotFound` variant of `Error` to accept a single parameter of type `List(String)`.
- [glua] Changed `IllegalIndex` variant of `LuaRuntimeExceptionKind` to make its first parameter the `index` and the second the `value`.
- [glua] Changed `ErrorCall` variant of `LuaRuntimeExceptionKind` to accept two parameters, the message and an optional level code.
- [glua] Added a `format_error` function to turn `glua.Error` values into a readable `String`.
- [glua] Removed `ValueRef` type and all functions starting with `ref_`, changed `call_function` to make its second parameter be of type `Value` and removed the `using` parameter from `get` `eval`, `eval_chunk`, `eval_file`, `call_function` and `call_function_by_name` functions and make those function return references to Lua values instead of Gleam values.
- [glua] Added a `dereference` function to turn a reference to a Lua value into type-safe Gleam data.
- [glua/lib] Added a `glua/lib` module with bindings to the global Lua functions.
- [glua/lib/bit32] Added a `glua/lib/bit32` module with bindings to the Lua functions in the `bit32` module.
- [glua/lib/debug] Added a `glua/lib/debug` module with bindings to the Lua functions in the `debug` module.
- [glua/lib/io] Added a `glua/lib/io` module with bindings to the Lua functions in the `io` module.
- [glua/lib/math] Added a `glua/lib/math` module with bindings to the Lua functions and values in the `math` module.
- [glua/lib/os] Added a `glua/lib/os` module with bindings to the Lua functions in the `os` module.
- [glua/lib/package] Added a `glua/lib/package` module with bindings to the Lua functions in the `package` module.
- [glua/lib/string] Added a `glua/lib/string` module with bindings to the Lua functions in the `string` module.
- [glua/lib/table] Added a `glua/lib/table` module with bindings to the Lua functions in the `table` module.
- [glua/lib/utf8] Added a `glua/lib/utf8` module with bindings to the Lua functions and values in the `utf8` module.
- [glua] Added an `Action` type to represent an operation that can be executed within a Lua VM and potentially mutates the Lua state.
- [glua] Changed the return types of the `table` and `userdata` functions to `Action(Value, e)`, the return type of the `get` function to `Action(Value, e)`, the return types of the `set`, `set_api` and `set_lua_paths` functions to `Action(Nil, e)`, the return types of the `load` and `load_file` functions to `Action(Chunk, e)` and the return types of the `eval`, `eval_chunk`, `eval_file`, `call_function` and `call_function_by_name` to `Action(List(Value), e)`.
- [glua] Added a `run` function to execute an `Action` within a given Lua VM and discard the mutated state in case of no errors.
- [glua] Added a `exec` function to execute an `Action` within a given Lua VM and get back both the mutated state and the result value in case of no errors.
- [glua] Added a `then` function to compose `Action`s into a single one, a `map` function to update the return value of an `Action`, a `try` function to run a result-returning function on the return value of an `Action` and a `guard` function to make booleans guards inside an `Action`.
- [glua] Added a `success` function to create an `Action` that always succeeds with the given value and a `failure` function to create an `Action` that always fails with the given value.
- [glua] Added a `returning` and a `returning_multi` function to convert an `Action` that returns one or multiple references to a Lua value into an `Action` that returns one or more type-safe Gleam values.
- [glua] Added a `fold` function to traverse a list and create a single `Action` that returns the accumulation of values 
- [glua] Changed the `function` function to only accept a `fn(List(Value)) -> Action(List(Value), e)` value as a parameter.
- [glua] Added a `function_decoder` function to decode Lua functions into Gleam functions.
- [glua] Added a `index` function to get the value of a field in a Lua table.
- [glua] Added a `new_index` function to set a field on a Lua table.
- [glua] Removed `table_decoder` and `list` functions.
- [glua] Added a `table_list` function to encode a Gleam list as a Lua table.
- [glua] Added a `table_list_decoder` function to decode a Lua table as a Gleam list.

## [v1.1.3] - 2025-11-30

- [glua] Fixed a bug where values returned from `call_function` are not being decoded by `luerl`.

## [v1.1.2] - 2025-11-26

- [glua] Fixed a bug where encoding a table will result in a runtime crash.

## [v1.1.1] - 2025-11-25

- [glua] Fixed wrong label in the `ref_get` function.

## [v1.1.0] - 2025-11-24

- [glua] Added `sandbox` and `new_sandboxed` functions for proper sandboxing of the Lua VM state.

## [v1.0.0] - 2025-11-18

### Added

- [glua] Added `new` function to create new fresh instances of the Lua VM.
- [glua] Added functions to encode Gleam values into Lua values.
- [glua] Added errors type to represent errors on the Lua side.
- [glua] Added `get` and `ref_get` functions for getting values from the Lua environment.
- [glua] Added `set`, `set_api` and `set_lua_paths` functions for setting values in the Lua environment.
- [glua] Added `eval`, `ref_eval`, `eval_file`, `ref_eval_file` functions for evaluating Lua code and files from Gleam.
- [glua] Added `load`, `load_chunk`, `eval_chunk` and `ref_eval_chunk` functions to work with chunks of Lua code.
- [glua] Added `call_function` and `ref_call_function`, `call_function_by_name` and `ref_call_function_by_name` functions to call Lua functions from Gleam.
- [glua] Added `get_private`, `set_private` and `delete_private` functions for working with private values.

