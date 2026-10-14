@wasm_import("wasi_snapshot_preview1", "fd_write")
fn fd_write(fd: i32, iovec_addr: **[u8], count: i32, n_written_ptr: *i32): i32;

