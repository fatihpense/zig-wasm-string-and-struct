# Zig WebAssembly example of passing String and using Struct references in WASM Host language

Here is a Youtube video that explains the example: <https://www.youtube.com/watch?v=dskKJj4qfeo>

The important code and comments reside in `./zig/wasm.zig`

WASM Host (Java) example is in `./java` directory.

## Create WASM bytecode

`ReleaseSafe` for seeing memory errors better. `ReleaseSmall` for getting smaller WASM bytecode.
`build-lib` and `build-exe` both works, `-rdynamic` helps to not specify exported functions again. There are different examples and updates on Zig GitHub issues.

```sh
zig build-lib ./zig/wasm.zig -target wasm32-freestanding -dynamic -rdynamic -O ReleaseSmall
zig build-lib ./zig/wasm.zig -target wasm32-freestanding -dynamic -rdynamic -O ReleaseSafe

zig build-exe ./zig/wasm.zig -target wasm32-freestanding -fno-entry -rdynamic -O ReleaseSafe
```

## Run Java example

```sh
cd java
mvn compile exec:java

...which prints:

Allocated Buffer start: 1114112
RESULT: Hello World!
1310720
bookquote struct pointer: Val(type=I32, value=1441792)
temp_ptr_for_xml_start_and_length: 1966080
result_start: 1572864
result_len: 21
here is Result String in Java
Madonna in a Fur Coat

```

## Credits

Special thanks to Travis in Zig discord: https://github.com/travisstaloch
