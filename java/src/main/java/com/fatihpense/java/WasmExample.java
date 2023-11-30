package com.fatihpense.java;

import static io.github.kawamuray.wasmtime.WasmValType.I32;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.Collections;

import io.github.kawamuray.wasmtime.Engine;
import io.github.kawamuray.wasmtime.Func;
import io.github.kawamuray.wasmtime.Instance;
import io.github.kawamuray.wasmtime.Linker;
import io.github.kawamuray.wasmtime.Memory;
import io.github.kawamuray.wasmtime.Store;
import io.github.kawamuray.wasmtime.WasmFunctions;
import io.github.kawamuray.wasmtime.WasmFunctions.Function2;
import io.github.kawamuray.wasmtime.wasi.WasiCtx;
import io.github.kawamuray.wasmtime.wasi.WasiCtxBuilder;
import io.github.kawamuray.wasmtime.Module;
import io.github.kawamuray.wasmtime.Val.Type;
import io.github.kawamuray.wasmtime.Val;

public class WasmExample {

    public static void main(String[] args) throws IOException {

        byte[] book_example_json = Files.readAllBytes(Paths.get("./example.json"));

        WasiCtx wasi = new WasiCtxBuilder().inheritStdout().inheritStderr().build();
        try (Store<Void> store = Store.withoutData(wasi)) {
            // Compile the wasm binary into an in-memory instance of a `Module`.
            System.err.println("Compiling module...");
            try (Engine engine = store.engine();
                    Module module = Module.fromFile(engine, "../wasm.wasm");) {

                Linker linker = new Linker(store.engine());
                WasiCtx.addToLinker(linker);
                linker.module(store, "", module);

                Memory mem = linker.get(store, "", "memory").get().memory();

                Func myAlloc = linker.get(store, "", "_wasm_alloc").get().func();
                Func edit_str_buffer = linker.get(store, "", "edit_str_buffer").get().func();
                Func parse_book_quote = linker.get(store, "", "parse_book_quote").get().func();
                Func get_book_name = linker.get(store, "", "get_book_name").get().func();

                {

                    byte[] test_buffer = "Cello World!".getBytes();
                    Val[] results = myAlloc.call(store, Val.fromI32(test_buffer.length));
                    int str_start = results[0].i32();
                    System.out.println("Allocated Buffer start: " + str_start);
                    ByteBuffer buf = mem.buffer(store);

                    buf.position(str_start);
                    buf.put(test_buffer, 0, test_buffer.length);
                    // more updated java versions have the method: buf.put(str_start, test_buffer);

                    Val[] results2 = edit_str_buffer.call(store, Val.fromI32(str_start),
                            Val.fromI32(test_buffer.length));

                    byte[] data = new byte[test_buffer.length];

                    // we could get result but it is using the same buffer...
                    // int str_start2 = results2[0].i32();
                    // System.out.println("TEST start2: " + str_start2);

                    buf.position(str_start);
                    // ... read!
                    buf.get(data);
                    // Let's encode back to a Java string.
                    String result = new String(data);
                    System.out.println("RESULT: " + result);

                }

                // PARSE JSON and get back STRUCT Pointer
                Val bookquote_struct_pointer = null;
                {
                    Val[] results = myAlloc.call(store, Val.fromI32(book_example_json.length));

                    int str_start = results[0].i32();
                    int str_len = book_example_json.length;
                    System.out.println(str_start);

                    ByteBuffer buf = mem.buffer(store);
                    // buf.put(str_start, book_example_json);
                    buf.position(str_start);
                    buf.put(book_example_json, 0, book_example_json.length);

                    Val[] results2 = parse_book_quote.call(store, Val.fromI32(str_start), Val.fromI32(str_len));
                    bookquote_struct_pointer = results2[0];
                    System.out.println("bookquote struct pointer: " + bookquote_struct_pointer);
                }

                // READ Book name from the parsed Struct

                {
                    // Here we get to reuse our struct inside Zig
                    Val[] results3 = get_book_name.call(store, bookquote_struct_pointer);

                    int temp_ptr_for_result_start_and_length = results3[0].i32();
                    System.out.println("temp_ptr_for_str_start_and_length: " +
                            temp_ptr_for_result_start_and_length);

                    byte[] temp_data = new byte[8];
                    ByteBuffer buf = mem.buffer(store);
                    buf.position(temp_ptr_for_result_start_and_length);
                    buf.get(temp_data);

                    ByteBuffer temp_buf = ByteBuffer.wrap(temp_data);
                    int result_str_start = temp_buf.order(java.nio.ByteOrder.LITTLE_ENDIAN).getInt(0);
                    int result_str_len = temp_buf.order(java.nio.ByteOrder.LITTLE_ENDIAN).getInt(4);

                    byte[] data = new byte[result_str_len];
                    buf.position(result_str_start);
                    buf.get(data);

                    System.out.println("result_start: " + result_str_start);
                    System.out.println("result_len: " + result_str_len);

                    // Let's encode back to a Java string.
                    String result = new String(data);
                    System.out.println("here is Result String in Java");
                    System.out.println(result);
                }
            }
        }
    }
}
