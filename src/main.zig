const std = @import("std");
const ziglua = @import("ziglua");
const toml = @import("toml.zig");

const Allocator = std.mem.Allocator;

pub fn getScript(string: []const u8) ?[]const u8 {
    const lua_marker = "$Lua";
    if (string.len < lua_marker.len) {
        return null;
    }
    const string_begin = string[0..lua_marker.len];
    if (!std.mem.eql(u8, string_begin, lua_marker)) {
        return null;
    }
    return string[lua_marker.len..];
}

const ScriptEngine = struct {
    allocator: Allocator,
    lua: ziglua.Lua,

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

    pub fn walkTomlArray(self: *ScriptEngine, array: *const toml.Array) anyerror!void {
        // Walk the toml
        var stdout = std.io.getStdOut().writer();
        var array_iter = array.iter();
        while (array_iter.next()) |index| {
            try stdout.print("next index: {d}\n", .{index});
            if (array.string_at(index)) |value| {
                defer toml.string_free(value);
                try stdout.print("Value: {s}\n", .{value});
                const string = value[0..std.mem.len(value)];
                if (getScript(string)) |script| {
                    try self.eval(script);
                }
            }
            else if (array.array_at(index)) |value| {
                try stdout.print("Array found\n", .{});
                try self.walkTomlArray(&value);
            }
            else if (array.table_at(index)) |value| {
                try stdout.print("Table found\n", .{});
                try self.walkTomlTable(&value);
            }
        }
    }

    pub fn walkTomlTable(self: *ScriptEngine, table: *const toml.Table) anyerror!void {
        // Walk the toml
        var stdout = std.io.getStdOut().writer();
        var table_iter = table.iter();
        while (table_iter.next()) |key| {
            try stdout.print("next key: {s}\n", .{key});
            if (table.string_in(key)) |value| {
                defer toml.string_free(value);
                try stdout.print("Value: {s}\n", .{value});
                const string = value[0..std.mem.len(value)];
                if (getScript(string)) |script| {
                    try self.eval(script);
                }
            }
            else if (table.array_in(key)) |value| {
                try stdout.print("Array found\n", .{});
                try self.walkTomlArray(&value);
            }
            else if (table.table_in(key)) |value| {
                try stdout.print("Table found\n", .{});
                try self.walkTomlTable(&value);
            }
        }
    }

};


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

    var script_engine = try ScriptEngine.init(allocator);
    defer script_engine.deinit();

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
        try script_engine.walkTomlTable(&doc);
    }
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
        \\array = [ 1, 2, 3, 4, 5 ]
        \\[sometable]
        \\key3 = 0.14
        \\boolkey = true
    ;
    const doc = try toml.Table.toml_parse(doc_string.ptr);
    defer doc.deinit();

    // Check the parsing results
    if (doc.int_in("somekey")) |value| {
        try std.testing.expect(value == 5);
    } else unreachable;
    if (doc.string_in("asecondkey")) |value| {
        const string = value[0..std.mem.len(value)];
        const result =  std.mem.eql(
            u8,
            string,
            "This is a multiline string\nSecond line");
        try std.testing.expect(result);
    } else unreachable;

    if (doc.array_in("array")) |array| {
        var expected: i64 = 1;
        var it = array.iter();
        while (it.next()) |index| {
            if (array.int_at(index)) |value| {
                try std.testing.expect(value == expected);
            } else unreachable;
            expected = expected + 1;
        }
    } else unreachable;

    if (doc.table_in("sometable")) |tab| {

        if (tab.float_in("key3")) |value| {
            try std.testing.expect(value == 0.14);
        } else unreachable;

        if (tab.bool_in("boolkey")) |value| {
            try std.testing.expect(value == true);
        } else unreachable;

    } else unreachable;
}
