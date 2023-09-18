const std = @import("std");

const c = @cImport({
    @cInclude("toml.h");
});

pub const Table = struct {
    table: *c.toml_table_t,

    pub const TomlTableError = error{
        ParseError,
    };

    pub fn toml_parse(conf: [*:0]u8, errbuf: [*:0]u8, errbufsz: i32) !Table {
        const table = c.toml_parse(conf, errbuf, errbufsz) orelse {
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
};

