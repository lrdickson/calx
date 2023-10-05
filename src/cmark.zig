const std = @import("std");

const c = @cImport({
    @cInclude("cmark.h");
});

pub const Node = struct {
    node: *c.cmark_node,

    pub fn deinit (self: *Node) void {
        c.cmark_node_free(self.node);
    }

    pub fn parse_document(buffer: [*:0]const u8) ?Node {
        var doc = c.cmark_parse_document(
        	buffer, buffer.len, c.CMARK_OPT_DEFAULT)
        	orelse return null;
        return Node{ .node = doc };
    }

    pub fn node_next(self: Node) ?Node {
        var node = c.cmark_node_next(self.node)
            orelse return null;
        return Node{ .node = node };
    }

};
