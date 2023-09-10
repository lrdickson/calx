const std = @import("std");
const ziglua = @import("ziglua");

const yaml = @cImport({
    @cInclude("libfyaml.h");
});

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    var stdout = std.io.getStdOut().writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Initialize Lua vm
    var lua = try ziglua.Lua.init(allocator);
    defer lua.deinit();

    // Open the Lua standard libraries
    lua.openLibs();

    // Run some lua code
    const lua_code =
        \\function eval_script()
        \\    return 42, 2
        \\end
    ;
    lua.doString(lua_code) catch unreachable;
    const stack_size = lua.getTop();
    const lua_type = try lua.getGlobal("eval_script");
    if (lua_type == ziglua.LuaType.function) {
        try lua.protectedCall(0, ziglua.mult_return, 0);

        // Get each of the returned values
        const num_returns = lua.getTop() - stack_size;
        try stdout.print("Number of returned values {d}\n",
            .{ num_returns });
        for (0..@intCast(num_returns)) |_| {
            if (lua.isInteger(-1)) {
                const result = try lua.toInteger(-1);
                try stdout.print("Lua returned {d}\n", .{ result });
                lua.pop(1);
            }
        }
    }

    try stdout.print("Yaml version {s}\n", .{yaml.fy_library_version()});
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
