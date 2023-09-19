const std = @import("std");

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("toml.h");
});

var errbuf: [200:0]u8 = .{0} ** 200;

const TomlTypeTag = enum {
    // toml_timestamp,
    toml_string,
    toml_bool,
    toml_int,
    toml_float,
};

pub const TomlType = union(TomlTypeTag) {
    // toml_timestamp,
    toml_string: [*:0]u8,
    toml_bool: bool,
    toml_int: i64,
    toml_float: f64,

    pub fn deinit(t: TomlType) void {
            switch (t) {
                TomlType.toml_string => |value| {
                    c.free(value);
                },
            }
    }
};

pub fn string_free(s: [*:0] u8) void {
    c.free(@ptrCast(s));
}

pub const Table = struct {
    table: *c.toml_table_t,

    pub const TomlTableError = error{
        ParseError,
        UnknownType,
    };

    pub fn toml_parse(conf: [*:0]u8) !Table {
        const table = c.toml_parse(conf, &errbuf, errbuf.len) orelse {
            return TomlTableError.ParseError;
        };
        return Table{
            .table = table,
        };
    }

    pub fn key_in(table: *Table, keyidx: i32) ?[*:0]const u8 {
        return c.toml_key_in(table.table, @intCast(keyidx));
    }

    pub fn deinit(table: *Table) void {
        c.toml_free(table.table);
    }

    pub fn value_from_key(table: *Table, key: [*:0]const u8) !TomlType {
        var value = c.toml_string_in(table.table, key);
        if (value.ok != 0) {
            return .{ .toml_string = value.u.s };
        }
        value = c.toml_bool_in(table.table, key);
        if (value.ok != 0) {
            return .{ .toml_bool = value.u.b != 0 };
        }
        value = c.toml_int_in(table.table, key);
        if (value.ok != 0) {
            return .{ .toml_int = value.u.i };
        }
        value = c.toml_double_in(table.table, key);
        if (value.ok != 0) {
            return .{ .toml_float = value.u.d };
        }
        return TomlTableError.UnknownType;
        // c.toml_timestamp_in(tab, key);
        // c.toml_table_in(tab, key);
        // c.toml_array_in(tab, key);
    }
};

