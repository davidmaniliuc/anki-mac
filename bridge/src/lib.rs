// C ABI over rslib, mirroring AnkiDroid's rslib-bridge and pylib's rsbridge.
// See include/anki_bridge.h for the contract.

use std::ffi::{c_char, CStr};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::{ptr, slice};

use anki::backend::{init_backend, Backend};
use anki::log::set_global_logger;

#[repr(C)]
pub struct AnkiBuffer {
    ptr: *mut u8,
    len: usize,
    cap: usize,
}

impl AnkiBuffer {
    fn from_vec(vec: Vec<u8>) -> Self {
        let mut vec = std::mem::ManuallyDrop::new(vec);
        AnkiBuffer {
            ptr: vec.as_mut_ptr(),
            len: vec.len(),
            cap: vec.capacity(),
        }
    }
}

unsafe fn input<'a>(ptr: *const u8, len: usize) -> &'a [u8] {
    if ptr.is_null() || len == 0 {
        &[]
    } else {
        slice::from_raw_parts(ptr, len)
    }
}

unsafe fn write_out(out: *mut AnkiBuffer, bytes: Vec<u8>) {
    if !out.is_null() {
        out.write(AnkiBuffer::from_vec(bytes));
    }
}

/// Runs `f`, turning a Rust panic into an error buffer instead of unwinding
/// into Swift (which would abort the process).
fn guarded(f: impl FnOnce() -> Result<Vec<u8>, Vec<u8>>) -> Result<Vec<u8>, Vec<u8>> {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or_else(|panic| {
        let msg = panic
            .downcast_ref::<String>()
            .map(String::as_str)
            .or_else(|| panic.downcast_ref::<&str>().copied())
            .unwrap_or("panic in anki backend");
        Err(format!("panic: {msg}").into_bytes())
    })
}

#[no_mangle]
pub unsafe extern "C" fn anki_open_backend(
    init: *const u8,
    init_len: usize,
    error: *mut AnkiBuffer,
) -> *mut Backend {
    let init = input(init, init_len);
    match catch_unwind(|| init_backend(init)) {
        Ok(Ok(backend)) => Box::into_raw(Box::new(backend)),
        Ok(Err(msg)) => {
            write_out(error, msg.into_bytes());
            ptr::null_mut()
        }
        Err(_) => {
            write_out(error, b"panic while opening backend".to_vec());
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn anki_close_backend(backend: *mut Backend) {
    if !backend.is_null() {
        drop(Box::from_raw(backend));
    }
}

#[no_mangle]
pub unsafe extern "C" fn anki_run_method(
    backend: *const Backend,
    service: u32,
    method: u32,
    input_ptr: *const u8,
    input_len: usize,
    out: *mut AnkiBuffer,
) -> bool {
    let backend = &*backend;
    let input = input(input_ptr, input_len);
    let result = guarded(|| backend.run_service_method(service, method, input));
    let ok = result.is_ok();
    write_out(out, result.unwrap_or_else(|err| err));
    ok
}

#[no_mangle]
pub unsafe extern "C" fn anki_run_db_command(
    backend: *const Backend,
    input_ptr: *const u8,
    input_len: usize,
    out: *mut AnkiBuffer,
) -> bool {
    let backend = &*backend;
    let input = input(input_ptr, input_len);
    let result = guarded(|| backend.run_db_command_bytes(input));
    let ok = result.is_ok();
    write_out(out, result.unwrap_or_else(|err| err));
    ok
}

#[no_mangle]
pub unsafe extern "C" fn anki_init_logging(path: *const c_char) -> bool {
    let path = if path.is_null() {
        None
    } else {
        CStr::from_ptr(path).to_str().ok()
    };
    set_global_logger(path).is_ok()
}

#[no_mangle]
pub unsafe extern "C" fn anki_free_buffer(buffer: AnkiBuffer) {
    if !buffer.ptr.is_null() {
        drop(Vec::from_raw_parts(buffer.ptr, buffer.len, buffer.cap));
    }
}
