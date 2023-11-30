// This code illustrates:
// 1- Pass String from Java to Zig
// 2- Pass String from Zig to Java
// 3- Keep created structs in Zig memory, and reuse structs from Java.

// Special thanks to Travis in Zig discord: https://github.com/travisstaloch

// Examples I could find always use Null-terminated Strings. This one returns pointer and length to use regular strings.
// Deallocation is not implemented with WASM logic, but you can see examples in the test.  zig test .\zig\wasm.zig

const std = @import("std");

const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
var gpa = GeneralPurposeAllocator(.{}){};
var allocator = gpa.allocator();

// if you use page_allocator, it will get a lot of memory for each allocation
//   and you will hit Web Assembly memory limit. Many small Zig WASM examples use this.
// const allocator = std.heap.page_allocator;

// there is also wasm_allocator, but it says it will be merged into GPA in the future.

// found this on Reddit for error:
// error: struct 'os.system__struct_3524' has no member named 'fd_t'
// pub const fd_t = system.fd_t;

pub const os = struct {
    pub const system = struct {
        pub const fd_t = u8;
        pub const STDERR_FILENO = 1;
        pub const E = std.os.linux.E;

        pub fn getErrno(T: usize) E {
            _ = T;
            return .SUCCESS;
        }

        pub fn write(f: fd_t, ptr: [*]const u8, len: usize) usize {
            _ = ptr;
            _ = f;
            return len;
        }
    };
};

// Enable allocation from host language:
export fn _wasm_alloc(len: usize) [*]const u8 {
    const buf = allocator.alloc(u8, len) catch {
        @panic("failed to allocate memory");
    };
    return buf.ptr;
}

// Alternative you can return 0 and use @intFromPtr
export fn _wasm_alloc_2(len: usize) usize {
    const buf = allocator.alloc(u8, len) catch {
        return 0;
    };
    return @intFromPtr(buf.ptr);
}

// Rust equivalent for this alloc function:
// #[no_mangle]
// pub unsafe fn my_alloc(size: usize) -> *mut u8 {
//     let align = std::mem::align_of::<usize>();
//     let layout = Layout::from_size_align_unchecked(size, align);
//     alloc(layout)
// }

export fn edit_str_buffer(ptr: [*]u8, len: u32) void {
    // alternative get usize and use @ptrFromInt
    // var buf: [*]u8 = @ptrFromInt(ptr);
    var source: []u8 = ptr[0..len];
    source.len = len;
    source[0] = 'H';
}

const BookQuote = struct {
    author: []u8,
    book: []u8,
    quote: []u8,
};

export fn parse_book_quote(ptr: [*]u8, len: u32) usize {
    var source: []u8 = ptr[0..len];
    source.len = len;

    // This is very important! This enables the struct to live in Heap.
    // Otherwise it is created in Stack and you return &local
    const parsed = allocator.create(std.json.Parsed(BookQuote)) catch {
        @panic("failed to allocate memory");
    };

    // : std.json.Parsed(MessageDefinition)
    parsed.* = std.json.parseFromSlice(BookQuote, allocator, source, .{ .ignore_unknown_fields = true }) catch {
        @panic("failed to allocate memory");
    };
    return @intFromPtr(parsed);
    // Rust equivalent
    // Box::into_raw(Box::new(RefCell::new(parsed))) as u32

    // Zig alternative:
    // change function return signature to: *const std.json.Parsed(SegmentDefinitionMap)
    // return parsed;
}

// Again alternatively you can (book_quote_ptr: usize) [*]usize {
// and
// const book_quote_parsed: *const std.json.Parsed(BookQuote) = @ptrFromInt(book_quote_ptr);
export fn get_book_name(book_quote_parsed: *std.json.Parsed(BookQuote)) [*]const usize {

    // I want to use u32 to be specific instead of usize but:
    //@intCast would work in WASM, it will get error on x64 systems. panic: integer cast truncated bits

    var result = std.ArrayList(u8).init(allocator);

    _ = result.writer().write(book_quote_parsed.value.book) catch |err| {
        std.debug.print("{?}: ", .{err});
        @panic("failed to allocate memory");
    };

    std.debug.print("Book name: {s} \n", .{result.items});
    //converting to ownedslice shrinks capacity to len, or we could use shrinkAndFree(len) to reduce memory
    const buffer = result.toOwnedSlice() catch |err| {
        std.debug.print("{?}: ", .{err});
        @panic("failed to allocate memory");
    };
    var myArray2 = allocator.alloc(usize, 2) catch {
        @panic("failed to allocate memory");
    };

    myArray2[0] = @intCast(@intFromPtr(buffer.ptr));
    myArray2[1] = @intCast(buffer.len);

    return myArray2.ptr;

    //Zig alternative:
    // const slice = result.items;
    // var buf2 = std.ArrayList(usize).initCapacity(allocator, 2) catch {
    //     @panic("failed to allocate memory");
    // };
    // buf2.append(@intCast(@intFromPtr(slice.ptr))) catch {
    //     @panic("failed to allocate memory");
    // };
    // buf2.append(@intCast(slice.len)) catch {
    //     @panic("failed to allocate memory");
    // };

    // Rust equivalent:
    // let length = result_data.len();
    // let ptr = result_data.as_mut_ptr() as u32;
    // std::mem::forget(result_data);

    // let mut temp_vector: Vec<u32> = vec![ptr, length.try_into().unwrap()];
    // let temp_ptr = temp_vector.as_mut_ptr() as u32;
    // std::mem::forget(temp_vector);

    // return temp_ptr as *mut u32;

}

test "parse json wasm" {
    //shadow allocator so implicitly functions will also use same allocator
    allocator = std.testing.allocator;
    const file1 = try std.fs.cwd().openFile("./java/example.json", .{});
    defer file1.close();
    const size1 = (try file1.stat()).size;
    const source1 = try file1.reader().readAllAlloc(allocator, size1);
    defer allocator.free(source1);

    const book_quote_parsed_usize: usize = parse_book_quote(@ptrCast(source1), @intCast(size1));

    const str_pos_and_len: [*]const usize = get_book_name(@ptrFromInt(book_quote_parsed_usize));

    const slice1 = str_pos_and_len[0..2];

    allocator.free(@as([*]const u8, @ptrFromInt(slice1[0]))[0..slice1[1]]);
    allocator.free(slice1);
    const book_quote_parsed: *const std.json.Parsed(BookQuote) = @ptrFromInt(book_quote_parsed_usize);
    book_quote_parsed.deinit();
    allocator.destroy(book_quote_parsed);
}
