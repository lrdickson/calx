const std = @import("std");
const ziglua = @import("ziglua");

const yaml = @cImport({
    @cInclude("libfyaml.h");
});

const Allocator = std.mem.Allocator;

const ScriptEngine = struct {
    allocator: Allocator,
    lua: ziglua.Lua,

    pub fn eval(self: *ScriptEngine, str: []const u8) !void {
        // Form a function
        const lua_function = try std.fmt.allocPrintZ(self.allocator, "function eval_script()\n{s}\nend", .{str});
        defer self.allocator.free(lua_function);

        // Compile the function
        try self.lua.doString(lua_function);
        const stack_size = self.lua.getTop();
        const lua_type = try self.lua.getGlobal("eval_script");
        if (lua_type == ziglua.LuaType.function) {
            // TODO: check for errors
            try self.lua.protectedCall(0, ziglua.mult_return, 0);

            // Get each of the returned values
            const num_returns = self.lua.getTop() - stack_size;
            var stdout = std.io.getStdOut().writer();
            try stdout.print("Number of returned values {d}\n",
                .{ num_returns });
            for (0..@intCast(num_returns)) |i| {
                try self.luaReadStack(@intCast(i + 1));
            }
            self.lua.pop(num_returns);
        }
    }

    pub fn luaReadStack(self: *ScriptEngine, index: i32) !void {
        var stdout = std.io.getStdOut().writer();
        if (self.lua.isBoolean(index)) {
            const result = self.lua.toBoolean(index);
            try stdout.print("Lua returned {any}\n", .{ result });
        } else if (self.lua.isInteger(index)) {
            const result = try self.lua.toInteger(index);
            try stdout.print("Lua returned {any}\n", .{ result });
        } else if (self.lua.isString(index)) {
            const result = try self.lua.toString(index);
            try stdout.print("Lua returned {s}\n", .{ result });
        } else if (self.lua.isNumber(index)) {
            const result = try self.lua.toNumber(index);
            try stdout.print("Lua returned {d}\n", .{ result });
        } else if (self.lua.isTable(index)) {
            try stdout.print("Lua returned table\n", .{});
            self.lua.pushNil();
            while(self.lua.next(index)) {
                try stdout.print("Reading next key\n", .{});
                try self.luaReadStack(-2);
                try stdout.print("Reading next value\n", .{});
                try self.luaReadStack(-1);
                self.lua.pop(1);
            }
        } else if (self.lua.isNoneOrNil(index)) {
            try stdout.print("Lua returned nil\n", .{});
        } else {
            try stdout.print("Unknown return type\n", .{});
        }
    }

    pub fn init(allocator: Allocator) !ScriptEngine {
        // Initialize Lua vm
        var lua = try ziglua.Lua.init(allocator);
        lua.openLibs();
        return ScriptEngine{
            .allocator = allocator,
            .lua = lua,
        };
    }

    pub fn deinit(self: *ScriptEngine) void {
        self.lua.deinit();
    }
};

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    var stdout = std.io.getStdOut().writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Run some lua code
    var script_engine = try ScriptEngine.init(allocator);
    defer script_engine.deinit();
    const lua_code = "return 42, 2, 3.14, true, false, 'hello'";
    try script_engine.eval(lua_code);
    try script_engine.eval("return {a = 2}");
    try script_engine.eval("return true, {42, 2}, 'world'");

    try stdout.print("Yaml version {s}\n", .{yaml.fy_library_version()});
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
