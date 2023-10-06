const std = @import("std");

const c = @cImport({
    @cInclude("cmark.h");
});

pub const NodeType = enum(u5) {
  // Error status
  none = c.CMARK_NODE_NONE,

  // Block
  document = c.CMARK_NODE_DOCUMENT,
  block_quote = c.CMARK_NODE_BLOCK_QUOTE,
  list = c.CMARK_NODE_LIST,
  item = c.CMARK_NODE_ITEM,
  code_block = c.CMARK_NODE_CODE_BLOCK,
  html_block = c.CMARK_NODE_HTML_BLOCK,
  custom_block = c.CMARK_NODE_CUSTOM_BLOCK,
  paragraph = c.CMARK_NODE_PARAGRAPH,
  heading = c.CMARK_NODE_HEADING,
  thematic_break = c.CMARK_NODE_THEMATIC_BREAK,

  first_block = c.CMARK_NODE_FIRST_BLOCK,
  last_block = c.CMARK_NODE_LAST_BLOCK,

  // Inline
  text = c.CMARK_NODE_TEXT,
  softbreak = c.CMARK_NODE_SOFTBREAK,
  linebreak = c.CMARK_NODE_LINEBREAK,
  code = c.CMARK_NODE_CODE,
  html_inline = c.CMARK_NODE_HTML_INLINE,
  custom_inline = c.CMARK_NODE_CUSTOM_INLINE,
  emph = c.CMARK_NODE_EMPH,
  strong = c.CMARK_NODE_STRONG,
  link = c.CMARK_NODE_LINK,
  image = c.CMARK_NODE_IMAGE,

  first_inline = c.CMARK_NODE_FIRST_INLINE,
  last_inline = c.CMARK_NODE_LAST_INLINE,
};

pub const ListType = enum(u2) {
  no_list = c.CMARK_NO_LIST,
  bullet_list = c.CMARK_BULLET_LIST,
  ordered_list = c.CMARK_ORDERED_LIST,
};

pub const DelimType = enum(u2) {
  no_delim = c.CMARK_NO_DELIM,
  period_delim = c.CMARK_PERIOD_DELIM,
  paren_delim = c.CMARK_PAREN_DELIM,
};

pub const Node = struct {
    node: *c.cmark_node,

    pub fn deinit (self: *Node) void {
        c.cmark_node_free(self.node);
    }

    pub fn parse_document(buffer: [*:0]const u8) ?Node {
        var doc = c.cmark_parse_document(
                buffer, buffer.len, c.CMARK_OPT_DEFAULT)
                orelse return null;
        return .{ .node = doc };
    }

    pub fn first_child(self: Node) ?Node {
        var node = c.cmark_node_first_child(self.node)
            orelse return null;
        return .{ .node = node };
    }

    pub fn next(self: Node) ?Node {
        var node = c.cmark_node_next(self.node)
            orelse return null;
        return .{ .node = node };
    }

    pub fn get_type(self: Node) NodeType {
        return @enumFromInt(c.cmark_node_get_type(self.node));
    }

    pub fn iter_new(self: Node) ?Iter {
        var iter = c.cmark_iter_new(self.node)
            orelse return null;
        return .{ .iter = iter };
    }
};

pub const Iter = struct {
    iter: *c.cmark_iter,

    pub fn deinit (self: *Iter) void {
        c.cmark_iter_free(self.iter);
    }
};

