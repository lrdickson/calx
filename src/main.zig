const std = @import("std");
const ziglua = @import("ziglua");
const toml = @import("toml.zig");

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

pub fn walkTomlArray(array: *const toml.Array) anyerror!void {
    // Walk the toml
    var stdout = std.io.getStdOut().writer();
    var array_iter = array.iter();
    while (array_iter.next()) |index| {
        try stdout.print("next index: {d}\n", .{index});
        if (array.string_at(index)) |value| {
            defer toml.string_free(value);
            try stdout.print("Value: {s}\n", .{value});
        }
        else if (array.array_at(index)) |value| {
            try stdout.print("Array found\n", .{});
            try walkTomlArray(&value);
        }
        else if (array.table_at(index)) |value| {
            try stdout.print("Table found\n", .{});
            try walkTomlTable(&value);
        }
    }
}

pub fn walkTomlTable(table: *const toml.Table) anyerror!void {
    // Walk the toml
    var stdout = std.io.getStdOut().writer();
    var table_iter = table.iter();
    while (table_iter.next()) |key| {
        try stdout.print("next key: {s}\n", .{key});
        if (table.string_in(key)) |value| {
            defer toml.string_free(value);
            try stdout.print("Value: {s}\n", .{value});
        }
        else if (table.array_in(key)) |value| {
            try stdout.print("Array found\n", .{});
            try walkTomlArray(&value);
        }
        else if (table.table_in(key)) |value| {
            try stdout.print("Table found\n", .{});
            try walkTomlTable(&value);
        }
    }
}

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    // std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    var stdout = std.io.getStdOut().writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    try stdout.print("Args: {s}\n", .{args});

    if (args.len > 1) {
        // Open the file
        const file = try std.fs.cwd().openFile(args[1], .{});
        defer file.close();
        var contents = std.ArrayList(u8).init(allocator);
        defer contents.deinit();
        try file.reader().readAllArrayList(&contents, 1_000_000_000);
        // Null terminate the string
        try contents.append(0);

        // Parse the file
        var doc = try toml.Table.toml_parse(@ptrCast(contents.items.ptr));
        defer doc.deinit();
        try walkTomlTable(&doc);
    }

    // Run some lua code
    var script_engine = try ScriptEngine.init(allocator);
    defer script_engine.deinit();
    const lua_code = "return 42, 2, 3.14, true, false, 'hello'";
    try script_engine.eval(lua_code);
    try script_engine.eval("return {a = 2}");
    try script_engine.eval("return true, {42, 2}, 'world'");
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "parse toml" {
    const doc_string: [:0]const u8 =
        \\somekey = 5
        \\asecondkey = """
        \\This is a multiline string
        \\Second line"""
        \\[sometable]
        \\key3 = 0.14
        \\boolkey = true
    ;
    const doc = try toml.Table.toml_parse(doc_string.ptr);
    defer doc.deinit();

    if (doc.value_from_key("somekey")) |value| {
        try std.testing.expect(value.toml_int == 5);
    } else unreachable;
}
