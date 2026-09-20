# The plugin runtime

Plugins are Lua. This records which Lua, why, and the rules the kernel
follows when it runs plugin code. The wrapper is `hexmap/rules/lua_vm.gd`;
the tests are `tests/suites/rules_lua.gd`.

## Decision: Luau, via `luau-gdextension`

Vendored in `addons/luau_gdextension/` (release binaries for macOS arm64,
Windows x86_64, Linux x86_64; MIT; version in `VERSION`). Chosen over
`gilzoide/lua-gdextension` (Lua 5.4/LuaJIT, all platforms) after running
the same scenarios on both (Phase 0 spike, 2026-09-20):

| scenario | Lua 5.4 | Luau |
|---|---|---|
| strip `io os debug load require dofile` | by hand | `sandbox()` also freezes globals and the standard library |
| endless loop | Lua-side count hook + `error()`, 7 ms | per-thread `interrupt` + `break`, 8 ms |
| allocation bomb (64 MB) | 115 ms | slower (a signal per safepoint) but contained; GC returns to 0 |
| runaway recursion | stack overflow error | stack overflow error |
| yield to the host, resume with an answer | ✓ | ✓ |
| 10k calls with nested data in and out | 151 ms with a hand-written deep converter (nested Dictionaries are opaque userdata otherwise) | 54 ms, native; arrays stay arrays |
| platforms | all, including iOS/Android | desktop only |
| Godot 4.7 | clean | one harmless bind warning at load |

Luau is built for untrusted code (read-only globals, safe environments,
no `string.dump`/`loadstring`, no `debug`), its bridge is faster and
cleaner, and the Player never runs plugin code, so desktop-only binaries
are enough. The Lua 5.4 extension is the fallback: it passed the same
spike, and everything above the `LuaVm` wrapper is runtime-agnostic.

Godot logs an error and continues when an extension has no library for the
platform; the mobile export presets exclude the addon directory so phones
do not even log it. `LuaVm.available()` is false there.

## Rules the kernel follows

1. **Data crosses the boundary, never objects.** Arguments and results are
   Dictionaries, Arrays, strings, numbers, booleans. No Godot Object is
   ever pushed into a VM.
2. **Load, then seal.** A plugin's chunks are loaded (`load_chunk`) and
   host functions exposed (`expose`) while the VM is open; `seal()` calls
   `sandbox()`; after that globals are read-only and only calls happen.
   `getfenv`/`setfenv` are removed before sealing.
3. **Every call is a thread.** `call_function` runs in a fresh Lua thread
   (`sandbox_thread()`), so calls in flight do not share state and a call
   may yield.
4. **The only way plugin code waits is `coroutine.yield`.** A host function
   that cannot answer at once (a prompt to a Player) is a Lua-side
   wrapper that yields a request table; the host services it and
   `resume()`s the Call with the answer. Host functions exposed through
   `expose` must return immediately.
5. **Budgets by `break`, never by `error()` from the host.** The VM's
   safepoint interrupts are on for its lifetime; each Call listens on its
   own thread's `interrupt` signal, counts safepoints, checks
   `get_total_bytes`, and stops the thread with `break` when a budget is
   exceeded. Raising a Lua error from inside a Godot signal handler
   unwinds through engine frames and crashes the process (observed).
6. **Collect after failure.** A cut-off or errored call's allocations are
   freed with a full GC before the next call, so one bad call does not
   starve the rest.
7. **Errors are values.** A plugin error becomes `Call.ERROR` with the
   message; it never propagates as an engine error. The kernel logs it
   against the plugin id and fails the hook it was running.

## Numbers (M-series Mac, debug build)

- call with a small nested table in and out: ~0.011 ms
- endless loop cut at 200k safepoints: ~8 ms
- an interrupt fires roughly once per loop iteration or call
