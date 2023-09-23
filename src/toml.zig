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
    toml_table,
    // toml_array,
};

pub const TomlType = union(TomlTypeTag) {
    // toml_timestamp,
    toml_string: [*:0]u8,
    toml_bool: bool,
    toml_int: i64,
    toml_float: f64,
    toml_table: Table,

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

pub const TomlError = error{
    ParseError,
    UnknownType,
};

pub const ArrayIter = struct {
    end: i32,
    current: i32,

    pub fn next(it: *ArrayIter) ?i32 {
        if (it.current == it.end) {
            return null;
        }
        const current = it.current;
        it.current = current + 1;
        return current;
    }
};

pub const Array = struct {
    array: *c.toml_array_t,

    pub fn nelem(array: *const Array) i32 {
        return c.toml_array_nelem(array.array);
    }

    pub fn iter(array: *const Array) ArrayIter {
        return ArrayIter{
            .end = array.nelem(),
            .current = 0,
        };
    }

    pub fn string_at(array: *const Array, idx: i32) ?[*:0]u8 {
        var value = c.toml_string_at(array.array, idx);
        if (value.ok == 0) {
            return null;
        }
        return value.u.s;
    }

    pub fn array_at(array: *const Array, idx: i32) ?Array {
        var value = c.toml_array_at(array.array, idx) orelse {
            return null;
        };
        return Array{
            .array = value,
        };
    }

    pub fn table_at(array: *const Array, idx: i32) ?Table {
        var value = c.toml_table_at(array.array, idx) orelse {
            return null;
        };
        return Table{
            .table = value,
        };
    }
};

pub const TableIter = struct {
    table: *const Table,
    current: i32,

    pub fn next(it: *TableIter) ?[*:0]const u8 {
        const key = it.table.key_in(it.current) orelse {
            return null;
        };
        it.current = it.current + 1;
        return key;
    }
};

pub const Table = struct {
    table: *c.toml_table_t,

    pub fn deinit(table: *const Table) void {
        c.toml_free(table.table);
    }

    pub fn toml_parse(conf: [*:0]const u8) !Table {
        const table = c.toml_parse(@ptrCast(@constCast(conf)), &errbuf, errbuf.len) orelse {
            return TomlError.ParseError;
        };
        return Table{
            .table = table,
        };
    }

    pub fn key_in(table: *const Table, keyidx: i32) ?[*:0]const u8 {
        return c.toml_key_in(table.table, @intCast(keyidx));
    }

    pub fn iter(table: *const Table) TableIter {
        return TableIter{
            .table = table,
            .current = 0,
        };
    }

    pub fn string_in(table: *const Table, key: [*:0]const u8) ?[*:0]u8 {
        var value = c.toml_string_in(table.table, key);
        if (value.ok == 0) {
            return null;
        }
        return value.u.s;
    }

    pub fn array_in(table: *const Table, key: [*:0]const u8) ?Array {
        var value = c.toml_array_in(table.table, key) orelse {
            return null;
        };
        return Array{
            .array = value,
        };
    }

    pub fn table_in(table: *const Table, key: [*:0]const u8) ?Table {
        var value = c.toml_table_in(table.table, key) orelse {
            return null;
        };
        return Table{
            .table = value,
        };
    }

    pub fn get(table: *const Table, key: [*:0]const u8) ?TomlType {
        if (table.string_in(key)) |value| {
            return .{ .toml_string = value };
        }
        var value = c.toml_bool_in(table.table, key);
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
        if (table.table_in(key)) |subtable| {
            return .{ .toml_table = subtable };
        }
        return null;
        // c.toml_timestamp_in(tab, key);
        // c.toml_array_in(tab, key);
    }
};

