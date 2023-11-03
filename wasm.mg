@intrinsic("data.end")
fn data_end(): usize;

@intrinsic("size_of")
fn size_of<T>(): usize;

@intrinsic("align_of")
fn align_of<T>(): usize;

@intrinsic("memory.size")
fn memory_size(): usize;

@intrinsic("memory.grow")
fn memory_grow(sz: usize): usize;

@intrinsic("unreachable")
fn trap();

@intrinsic("f32.floor")
fn floor_f32(v: f32): f32;

@intrinsic("f32.ceil")
fn ceil_f32(v: f32): f32;

@intrinsic("f64.floor")
fn floor_f64(v: f64): f64;

@intrinsic("f64.ceil")
fn ceil_f64(v: f64): f64;

@intrinsic("table.get")
fn table_get(id: usize): opaque;

@intrinsic("table.set")
fn table_set(id: usize, val: opaque);


