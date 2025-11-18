# Changelog

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

