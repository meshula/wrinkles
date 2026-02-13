const std = @import("std");
const Ast = std.zig.Ast;

const ParentMap = std.AutoHashMapUnmanaged(Ast.Node.Index, Ast.Node.Index);

const LineIndex = struct {
    line_starts: []const usize,

    fn build(
        allocator: std.mem.Allocator,
        source: []const u8,
    ) !LineIndex
    {
        var starts: std.ArrayListUnmanaged(usize) = .{};
        try starts.append(allocator, 0); // line 0 starts at byte 0
        for (source, 0..)
            |c, i|
        {
            if (
                c == '\n'
                and i + 1 < source.len
            )
            {
                try starts.append(allocator, i + 1);
            }
        }
        return .{ .line_starts = try starts.toOwnedSlice(allocator) };
    }

    fn deinit(
        self: *LineIndex,
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.line_starts);
    }

    fn line_of(
        self: LineIndex,
        byte_offset: usize,
    ) usize
    {
        // Binary search: find last line_start <= byte_offset
        var lo: usize = 0;
        var hi: usize = self.line_starts.len;
        while (lo < hi)
        {
            const mid = lo + (hi - lo) / 2;
            if (self.line_starts[mid] <= byte_offset)
            {
                lo = mid + 1;
            }
            else
            {
                hi = mid;
            }
        }
        return lo - 1;
    }

    fn line_start(
        self: LineIndex,
        byte_offset: usize,
    ) usize
    {
        return self.line_starts[self.line_of(byte_offset)];
    }

    fn same_line(
        self: LineIndex,
        a: usize,
        b: usize,
    ) bool
    {
        return self.line_of(a) == self.line_of(b);
    }
};

fn build_lhs_parent_map(
    allocator: std.mem.Allocator,
    ast: *const Ast,
) std.mem.Allocator.Error!ParentMap
{
    var map: ParentMap = .{};
    const tags = ast.nodes.items(.tag);
    const node_data = ast.nodes.items(.data);
    for (0..ast.nodes.len)
        |i|
    {
        const tag = tags[i];
        // Only index nodes whose tags use node_and_node data and are
        // relevant to chain-root lookups (boolean, array_cat, arithmetic).
        if (
            tag != .bool_and
            and tag != .bool_or
            and tag != .array_cat
            and !is_arithmetic_binary_op_tag(tag)
        )
        {
            continue;
        }
        const data = node_data[i];
        const lhs: Ast.Node.Index = data.node_and_node[0];
        if (@intFromEnum(lhs) != 0)
        {
            try map.put(allocator, lhs, @enumFromInt(i));
        }
    }
    return map;
}

pub const FormatError = error{
    ParseError,
    OutOfMemory,
};

/// Maximum allowed line length
pub const MAX_LINE_LENGTH: usize = 78;

/// Information about a line that exceeds the max length
const LongLine = struct {
    line_number: usize, // 0-indexed
    line_start: usize, // byte offset of line start
    line_end: usize, // byte offset of line end (before newline)
    length: usize, // character count
};

const OperatorPosition = struct {
    start: usize, // byte offset in source of the space before op
    end: usize, // byte offset in source after op + trailing space
    keyword: []const u8,
};

const ConditionRange = struct {
    start: usize, // lparen byte offset
    end: usize, // rparen byte offset
    has_boolean_op: bool,
};

const GroupedExprRange = struct {
    start: usize, // lparen byte offset
    end: usize, // rparen byte offset
};

/// Build a sorted array of grouped expression (parenthesized expression) byte
/// ranges from the AST.  Each range records the lparen..rparen byte extent.
fn build_grouped_expr_ranges(
    allocator: std.mem.Allocator,
    ast: *const Ast,
) std.mem.Allocator.Error![]const GroupedExprRange
{
    const tags = ast.nodes.items(.tag);
    const main_tokens = ast.nodes.items(.main_token);
    const node_data = ast.nodes.items(.data);
    const token_starts = ast.tokens.items(.start);

    var ranges: std.ArrayListUnmanaged(GroupedExprRange) = .{};
    errdefer ranges.deinit(allocator);

    for (0..ast.nodes.len)
        |i|
    {
        if (tags[i] != .grouped_expression)
        {
            continue;
        }

        const lparen_tok = main_tokens[i];
        const rparen_tok: Ast.TokenIndex = node_data[i].node_and_token[1];

        try ranges.append(
            allocator,
            .{
                .start = token_starts[lparen_tok],
                .end = token_starts[rparen_tok],
            },
        );
    }

    const items = try ranges.toOwnedSlice(allocator);
    std.mem.sort(
        GroupedExprRange,
        items,
        {},
        struct {
            fn lessThan(
                _: void,
                a: GroupedExprRange,
                b: GroupedExprRange,
            ) bool
            {
                return a.start < b.start;
            }
        }.lessThan,
    );

    return items;
}

/// Build a sorted array of condition ranges from if/while nodes in the AST.
/// Each range records the lparen..rparen byte extent and whether the
/// condition
/// contains a boolean operator (`and`/`or`).
fn build_condition_ranges(
    allocator: std.mem.Allocator,
    ast: *const Ast,
) std.mem.Allocator.Error![]const ConditionRange
{
    const tags = ast.nodes.items(.tag);
    const main_tokens = ast.nodes.items(.main_token);
    const token_tags = ast.tokens.items(.tag);
    const token_starts = ast.tokens.items(.start);

    var ranges: std.ArrayListUnmanaged(ConditionRange) = .{};
    errdefer ranges.deinit(allocator);

    for (0..ast.nodes.len)
        |i|
    {
        const idx: Ast.Node.Index = @enumFromInt(i);
        const tag = tags[@intFromEnum(idx)];

        if (
            tag == .@"if"
            or tag == .if_simple
        )
        {
            const if_info = ast.fullIf(idx) orelse continue;
            const if_token = main_tokens[@intFromEnum(idx)];

            var cond_lparen = if_token + 1;
            while (
                cond_lparen < ast.tokens.len
                and token_tags[cond_lparen] != .l_paren
            )
            {
                cond_lparen += 1;
            }
            if (cond_lparen >= ast.tokens.len)
            {
                continue;
            }

            const cond_last_tok = ast.lastToken(if_info.ast.cond_expr);
            const cond_rparen = cond_last_tok + 1;

            try ranges.append(
                allocator,
                .{
                    .start = token_starts[cond_lparen],
                    .end = token_starts[cond_rparen],
                    .has_boolean_op = condition_contains_boolean_op(
                        ast,
                        token_tags,
                        if_info.ast.cond_expr,
                    ),
                },
            );
        }

        if (
            tag == .@"while"
            or tag == .while_simple
            or tag == .while_cont
        )
        {
            const while_info = ast.fullWhile(idx) orelse continue;
            const while_token = while_info.ast.while_token;

            var cond_lparen = while_token + 1;
            while (
                cond_lparen < ast.tokens.len
                and token_tags[cond_lparen] != .l_paren
            )
            {
                cond_lparen += 1;
            }
            if (cond_lparen >= ast.tokens.len)
            {
                continue;
            }

            const cond_last_tok = ast.lastToken(while_info.ast.cond_expr);
            const cond_rparen = cond_last_tok + 1;

            try ranges.append(
                allocator,
                .{
                    .start = token_starts[cond_lparen],
                    .end = token_starts[cond_rparen],
                    .has_boolean_op = condition_contains_boolean_op(
                        ast,
                        token_tags,
                        while_info.ast.cond_expr,
                    ),
                },
            );
        }
    }

    const items = try ranges.toOwnedSlice(allocator);
    std.mem.sort(
        ConditionRange,
        items,
        {},
        struct {
            fn lessThan(
                _: void,
                a: ConditionRange,
                b: ConditionRange,
            ) bool
            {
                return a.start < b.start;
            }
        }.lessThan,
    );

    return items;
}

fn find_or_and_operators(
    allocator: std.mem.Allocator,
    text: []const u8,
    base_offset: usize,
    positions: *std.ArrayListUnmanaged(OperatorPosition),
) std.mem.Allocator.Error!void
{
    var pos: usize = 0;
    while (pos < text.len)
    {
        const remaining = text[pos..];
        const or_idx = std.mem.indexOf(u8, remaining, " or ");
        const and_idx = std.mem.indexOf(u8, remaining, " and ");

        var found_offset: usize = undefined;
        var found_keyword: []const u8 = undefined;
        var found_pattern_len: usize = undefined;
        var found_any = false;

        if (
            or_idx != null
            and and_idx != null
        )
        {
            if (or_idx.? <= and_idx.?)
            {
                found_offset = pos + or_idx.?;
                found_keyword = "or";
                found_pattern_len = 4;
            }
            else
            {
                found_offset = pos + and_idx.?;
                found_keyword = "and";
                found_pattern_len = 5;
            }
            found_any = true;
        }
        else if (or_idx)
            |idx|
        {
            found_offset = pos + idx;
            found_keyword = "or";
            found_pattern_len = 4;
            found_any = true;
        }
        else if (and_idx)
            |idx|
        {
            found_offset = pos + idx;
            found_keyword = "and";
            found_pattern_len = 5;
            found_any = true;
        }

        if (found_any)
        {
            try positions.append(
                allocator,
                .{
                    .start = base_offset + found_offset,
                    .end = base_offset + found_offset + found_pattern_len,
                    .keyword = found_keyword,
                },
            );
            pos = found_offset + found_pattern_len;
        }
        else
        {
            break;
        }
    }
}

const Edit = struct {
    start_byte: usize,
    end_byte: usize,
    new_text: []const u8,

    fn less_than(
        _: void,
        a: Edit,
        b: Edit,
    ) bool
    {
        return a.start_byte < b.start_byte;
    }
};

fn skip_whitespace_back(
    source: []const u8,
    pos: usize,
) usize
{
    var p = pos;
    while (
        p > 0
        and (
            source[p - 1] == ' '
            or source[p - 1] == '\t'
        )
    )
    {
        p -= 1;
    }
    return p;
}

fn skip_whitespace_fwd(
    source: []const u8,
    pos: usize,
) usize
{
    var p = pos;
    while (
        p < source.len
        and (
            source[p] == ' '
            or source[p] == '\t'
        )
    )
    {
        p += 1;
    }
    return p;
}

fn skip_literal(
    text: []const u8,
    pos: usize,
    quote: u8,
) usize
{
    var i = pos + 1;
    while (i < text.len)
    {
        if (text[i] == '\\')
        {
            i += 2;
        }
        else if (text[i] == quote)
        {
            return i + 1;
        }
        else
        {
            i += 1;
        }
    }
    return i;
}

/// Scan source bytes from `start` to `end` for newlines and re-indent
/// each interior line by prepending `extra_indent` to whatever whitespace
/// already exists.  Empty lines (only whitespace before the next newline)
/// are left untouched.
fn reindent_interior_lines(
    allocator: std.mem.Allocator,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    start: usize,
    end: usize,
    extra_indent: []const u8,
) std.mem.Allocator.Error!void
{
    var pos = start;
    while (pos < end)
    {
        if (source[pos] == '\n')
        {
            const line_start = pos + 1;
            var indent_end = line_start;
            while (
                indent_end < end
                and (
                    source[indent_end] == ' '
                    or source[indent_end] == '\t'
                )
            )
            {
                indent_end += 1;
            }

            // Don't re-indent empty lines
            if (
                indent_end < source.len
                and source[indent_end] != '\n'
            )
            {
                const existing_indent = (source[line_start..indent_end]);
                const new_indent = try std.fmt.allocPrint(
                    allocator,
                    "{s}{s}",
                    .{ existing_indent, extra_indent },
                );
                try edits.append(
                    allocator,
                    .{
                        .start_byte = line_start,
                        .end_byte = indent_end,
                        .new_text = new_indent,
                    },
                );
            }

            pos = indent_end;
        }
        else
        {
            pos += 1;
        }
    }
}

fn collect_depth0_commas(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    open_tok: Ast.TokenIndex,
    close_tok: Ast.TokenIndex,
) std.mem.Allocator.Error!std.ArrayListUnmanaged(usize)
{
    var comma_positions: std.ArrayListUnmanaged(usize) = .{};
    var tok = open_tok + 1;
    var depth: usize = 0;
    while (tok < close_tok)
    {
        const tok_tag = ast.tokens.items(.tag)[tok];
        if (
            tok_tag == .l_paren
            or tok_tag == .l_brace
            or tok_tag == .l_bracket
        )
        {
            depth += 1;
        }
        else if (
            tok_tag == .r_paren
            or tok_tag == .r_brace
            or tok_tag == .r_bracket
        )
        {
            if (depth > 0)
            {
                depth -= 1;
            }
        }
        else if (
            tok_tag == .comma
            and depth == 0
        )
        {
            try comma_positions.append(
                allocator,
                ast.tokens.items(.start)[tok],
            );
        }
        tok += 1;
    }
    return comma_positions;
}

fn find_matching_delimiter(
    ast: *const Ast,
    open_tok: Ast.TokenIndex,
    comptime open_tag: std.zig.Token.Tag,
    comptime close_tag: std.zig.Token.Tag,
) ?Ast.TokenIndex
{
    const token_tags = ast.tokens.items(.tag);
    var depth: usize = 1;
    var tok = open_tok + 1;
    while (tok < ast.tokens.len)
        : (tok += 1)
    {
        const tag = token_tags[tok];
        if (tag == open_tag)
        {
            depth += 1;
        }
        else if (tag == close_tag)
        {
            depth -= 1;
            if (depth == 0)
            {
                return tok;
            }
        }
    }
    return null;
}

fn find_matching_delimiter_rt(
    ast: *const Ast,
    open_tok: Ast.TokenIndex,
    open_tag: std.zig.Token.Tag,
    close_tag: std.zig.Token.Tag,
) ?Ast.TokenIndex
{
    const token_tags = ast.tokens.items(.tag);
    var depth: usize = 1;
    var tok = open_tok + 1;
    while (tok < ast.tokens.len)
        : (tok += 1)
    {
        const tag = token_tags[tok];
        if (tag == open_tag)
        {
            depth += 1;
        }
        else if (tag == close_tag)
        {
            depth -= 1;
            if (depth == 0)
            {
                return tok;
            }
        }
    }
    return null;
}

pub fn format(
    allocator: std.mem.Allocator,
    source: []const u8,
) FormatError![]u8
{
    // Validate that the input parses
    {
        const source_z = try allocator.dupeZ(u8, source);
        defer allocator.free(source_z);

        var ast = try std.zig.Ast.parse(allocator, source_z, .zig);
        defer ast.deinit(allocator);

        if (ast.errors.len > 0)
        {
            return error.ParseError;
        }
    }

    // Iterative formatting loop: each pass may break one nesting level,
    // so we repeat until no more edits are produced (stable) or we hit the
    // limit.
    const max_iterations = 10;
    var current = try allocator.dupe(u8, source);

    var iteration: usize = 0;
    while (iteration < max_iterations)
        : (iteration += 1)
    {
        const current_z = try allocator.dupeZ(u8, current);
        defer allocator.free(current_z);

        var ast = try std.zig.Ast.parse(allocator, current_z, .zig);
        defer ast.deinit(allocator);

        var line_index = try LineIndex.build(allocator, current);
        defer line_index.deinit(allocator);

        var parent_map = try build_lhs_parent_map(allocator, &ast);
        defer parent_map.deinit(allocator);

        const condition_ranges = try build_condition_ranges(allocator, &ast);
        defer allocator.free(condition_ranges);

        const grouped_expr_ranges = try build_grouped_expr_ranges(
            allocator,
            &ast,
        );
        defer allocator.free(grouped_expr_ranges);

        var edits: std.ArrayListUnmanaged(Edit) = .{};
        defer {
            for (edits.items)
                |edit|
            {
                if (
                    edit.new_text.len > 0
                    and !is_static_string(
                            edit.new_text,
                        )
                )
                {
                    allocator.free(edit.new_text);
                }
            }
            edits.deinit(allocator);
        }

        const long_lines = try find_long_lines(allocator, current);
        defer allocator.free(long_lines);

        // Collect all transformation edits against current source
        try collect_trailing_operator_edits(allocator, current, &edits);
        try collect_brace_edits(
            allocator,
            &ast,
            current,
            &edits,
            &line_index,
        );
        try collect_function_signature_edits(
            allocator,
            &ast,
            current,
            &edits,
            &line_index,
        );
        try collect_multiline_structural_edits(
            allocator,
            &ast,
            current,
            &edits,
            &line_index,
        );
        try collect_if_else_expr_edits(
            allocator,
            &ast,
            current,
            &edits,
            long_lines,
            &line_index,
        );
        try collect_line_break_edits(
            allocator,
            &ast,
            current,
            &edits,
            long_lines,
            condition_ranges,
            grouped_expr_ranges,
            &line_index,
            &parent_map,
        );
        try collect_boolean_condition_edits(
            allocator,
            &ast,
            current,
            &edits,
            &line_index,
        );
        try collect_comparison_condition_edits(
            allocator,
            &ast,
            current,
            &edits,
            &line_index,
        );
        try collect_chain_expression_wrap_edits(
            allocator,
            &ast,
            current,
            &edits,
            &parent_map,
            condition_ranges,
            is_bool_chain_tag,
            true,
            &line_index,
        );
        try collect_chain_expression_wrap_edits(
            allocator,
            &ast,
            current,
            &edits,
            &parent_map,
            condition_ranges,
            is_array_cat_tag,
            false,
            &line_index,
        );
        try collect_stacked_paren_edits(
            allocator,
            &ast,
            current,
            &edits,
            &line_index,
        );
        try collect_trailing_comment_edits(
            allocator,
            current,
            &edits,
            long_lines,
        );
        try collect_comment_wrap_edits(
            allocator,
            current,
            &edits,
            long_lines,
        );
        const prior_edits_for_expr_wrap = edits.items.len;
        try collect_simple_expression_wrap_edits(
            allocator,
            current,
            &edits,
            prior_edits_for_expr_wrap,
            long_lines,
        );
        const prior_edits_for_string = edits.items.len;
        try collect_string_literal_break_edits(
            allocator,
            &ast,
            current,
            &edits,
            prior_edits_for_string,
            long_lines,
        );

        // No edits means we've reached a stable state
        if (edits.items.len == 0)
        {
            break;
        }

        // Sort edits by position (ascending)
        std.mem.sort(Edit, edits.items, {}, Edit.less_than);

        // Apply edits to produce next version
        var result: std.ArrayListUnmanaged(u8) = .{};
        errdefer result.deinit(allocator);

        var last_end: usize = 0;
        for (edits.items)
            |edit|
        {
            // Skip overlapping edits
            if (edit.start_byte < last_end)
            {
                continue;
            }
            try result.appendSlice(
                allocator,
                current[last_end..edit.start_byte],
            );
            try result.appendSlice(allocator, edit.new_text);
            last_end = edit.end_byte;
        }
        try result.appendSlice(allocator, current[last_end..]);

        const next = try result.toOwnedSlice(allocator);
        allocator.free(current);
        current = next;
    }

    // Run diagnostics and validate that the final result still parses
    {
        const final_z = try allocator.dupeZ(u8, current);
        defer allocator.free(final_z);

        var final_ast = try std.zig.Ast.parse(allocator, final_z, .zig);
        defer final_ast.deinit(allocator);

        if (final_ast.errors.len > 0)
        {
            std.debug.print(
                "FORMATTER BUG: Output does not parse!\n",
                .{},
            );
            allocator.free(current);
            return error.ParseError;
        }

        var final_line_index = try LineIndex.build(allocator, current);
        defer final_line_index.deinit(allocator);
        check_naming_conventions(&final_ast, current, &final_line_index);
        const final_long_lines = find_long_lines(
            allocator,
            current,
        ) catch &[_]LongLine{};
        defer allocator.free(final_long_lines);
        report_long_lines(final_long_lines);
    }

    return current;
}

fn is_static_string(
    s: []const u8,
) bool
{
    // Check if the string is one of our static strings
    const statics = [_][]const u8{ "\n", " ", "," };
    for (statics)
        |static|
    {
        if (s.ptr == static.ptr)
        {
            return true;
        }
    }
    return false;
}

/// Move trailing `and`/`or` operators to the start of the next line.
/// When a line has a trailing operator, also breaks before any mid-line
/// `or`/`and` operators on the same line so the entire chain is wrapped.
/// Operates purely on text — no AST needed.
fn collect_trailing_operator_edits(
    allocator: std.mem.Allocator,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
) std.mem.Allocator.Error!void
{
    var line_begin: usize = 0;
    while (line_begin < source.len)
    {
        // Find end of current line
        var line_end = line_begin;
        while (
            line_end < source.len
            and source[line_end] != '\n'
        )
        {
            line_end += 1;
        }

        // Skip if this is the last line (no next line to move operator to)
        if (line_end >= source.len)
        {
            break;
        }

        const line = source[line_begin..line_end];

        // Strip trailing whitespace to find the "real" end
        var trimmed_end = line.len;
        while (
            trimmed_end > 0
            and (
                line[trimmed_end - 1] == ' '
                or line[trimmed_end - 1] == '\t'
            )
        )
        {
            trimmed_end -= 1;
        }

        const trimmed = line[0..trimmed_end];

        // Check for trailing ` or` or ` and`
        const has_trailing_or = (
            trimmed.len >= 3
            and std.mem.eql(u8, trimmed[trimmed.len - 3 ..], " or")
        );
        const has_trailing_and = (
            trimmed.len >= 4
            and std.mem.eql(u8, trimmed[trimmed.len - 4 ..], " and")
        );

        if (
            !has_trailing_or
            and !has_trailing_and
        )
        {
            line_begin = line_end + 1;
            continue;
        }

        // Check if line is inside a comment (// appears after indent)
        const indent = get_line_indent(source, line_begin);
        const content_start = indent.len;
        const after_indent = line[content_start..];
        if (std.mem.startsWith(u8, after_indent, "//"))
        {
            line_begin = line_end + 1;
            continue;
        }

        // Skip multi-line string lines (start with \\)
        if (std.mem.startsWith(u8, after_indent, "\\\\"))
        {
            line_begin = line_end + 1;
            continue;
        }

        // Determine the trailing operator keyword
        const trailing_keyword: []const u8 = if (has_trailing_or)
            "or"
        else
            "and";

        // +1 for leading space
        const trailing_op_len: usize = trailing_keyword.len + 1;

        // Collect positions of all mid-line ` or ` / ` and ` occurrences
        // plus the trailing one. We search only within the trimmed part.
        // For mid-line operators we look for ` or ` and ` and ` (with
        // trailing space) to avoid matching inside identifiers.
        var positions: std.ArrayListUnmanaged(OperatorPosition) = .{};
        defer positions.deinit(allocator);

        // Search for mid-line operators (` or ` and ` and `)
        {
            const search_area = line[0 .. trimmed_end - trailing_op_len];
            try find_or_and_operators(
                allocator,
                search_area,
                line_begin,
                &positions,
            );
        }

        // Add the trailing operator
        // Edit region spans from space-before-op through leading
        // whitespace of next line.
        const trailing_start = line_begin + trimmed_end - trailing_op_len;
        const next_line_start = line_end + 1;
        const next_content_start = skip_whitespace_fwd(
            source,
            next_line_start,
        );

        try positions.append(
            allocator,
            .{
                .start = trailing_start,
                .end = next_content_start,
                .keyword = trailing_keyword,
            },
        );

        // Also scan the next line for mid-line operators, since
        // the trailing edit joins the next line's content into the
        // expression chain.
        var next_line_end = next_content_start;
        while (
            next_line_end < source.len
            and source[next_line_end] != '\n'
        )
        {
            next_line_end += 1;
        }
        const next_line_content = source[next_content_start..next_line_end];

        // Search the next line for ` or ` and ` and `
        try find_or_and_operators(
            allocator,
            next_line_content,
            next_content_start,
            &positions,
        );

        // Also check if next line has a trailing operator
        // (outside of what we already found as mid-line)
        {
            var nl_trimmed_end = next_line_content.len;
            while (
                nl_trimmed_end > 0
                and (
                    next_line_content[nl_trimmed_end - 1] == ' '
                    or next_line_content[nl_trimmed_end - 1] == '\t'
                )
            )
            {
                nl_trimmed_end -= 1;
            }
            const nl_trimmed = next_line_content[0..nl_trimmed_end];

            const nl_trailing_or = (
                nl_trimmed.len >= 3
                and std.mem.eql(u8, nl_trimmed[nl_trimmed.len - 3 ..], " or")
            );
            const nl_trailing_and = (
                nl_trimmed.len >= 4
                and std.mem.eql(
                    u8,
                    nl_trimmed[nl_trimmed.len - 4 ..],
                    " and",
                )
            );

            if (
                nl_trailing_or
                or nl_trailing_and
            )
            {
                const nl_kw: []const u8 = (
                    if (nl_trailing_or) "or"
                    else "and"
                );
                const nl_op_len: usize = nl_kw.len + 1;

                const nl_trailing_start =  (
                    next_content_start
                    + nl_trimmed_end
                    - nl_op_len
                );

                // Find the line after the next line
                const line_after_next_start = next_line_end + 1;
                const line_after_content_start = skip_whitespace_fwd(
                    source,
                    line_after_next_start,
                );

                try positions.append(
                    allocator,
                    .{
                        .start = nl_trailing_start,
                        .end = line_after_content_start,
                        .keyword = nl_kw,
                    },
                );

                // Skip past the line after next too
                next_line_end = line_after_content_start;
                while (
                    next_line_end < source.len
                    and source[next_line_end] != '\n'
                )
                {
                    next_line_end += 1;
                }
            }
        }

        // Emit edits for each position (replace with \n{indent}{kw} )
        for (positions.items)
            |p|
        {
            const new_text = try std.fmt.allocPrint(
                allocator,
                "\n{s}{s} ",
                .{ indent, p.keyword },
            );

            try edits.append(
                allocator,
                .{
                    .start_byte = p.start,
                    .end_byte = p.end,
                    .new_text = new_text,
                },
            );
        }

        // Advance past the processed lines
        line_begin = next_line_end;
        if (
            line_begin < source.len
            and source[line_begin] == '\n'
        )
        {
            line_begin += 1;
        }
        continue;
    }
}

fn collect_brace_edits(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const tags = ast.nodes.items(.tag);

    for (0..ast.nodes.len)
        |i|
    {
        const node_index: Ast.Node.Index = @enumFromInt(i);
        switch (tags[@intFromEnum(node_index)]) {
            .@"if", .if_simple => {
                try process_if_statement(
                    allocator,
                    ast,
                    source,
                    edits,
                    node_index,
                    line_index,
                );
            },
            .@"for", .for_simple => {
                try process_for_statement(
                    allocator,
                    ast,
                    source,
                    edits,
                    node_index,
                    line_index,
                );
            },
            .@"while", .while_simple, .while_cont => {
                try process_while_statement(
                    allocator,
                    ast,
                    source,
                    edits,
                    node_index,
                    line_index,
                );
            },
            .test_decl => {
                try process_test_decl(
                    allocator,
                    ast,
                    source,
                    edits,
                    node_index,
                    line_index,
                );
            },
            .fn_decl => {
                try process_fn_decl(
                    allocator,
                    ast,
                    source,
                    edits,
                    node_index,
                    line_index,
                );
            },
            .@"switch", .switch_comma => {
                try process_switch_statement(
                    allocator,
                    ast,
                    source,
                    edits,
                    node_index,
                    line_index,
                );
            },
            .container_decl,
            .container_decl_trailing,
            .container_decl_two,
            .container_decl_two_trailing,
            .container_decl_arg,
            .container_decl_arg_trailing,
            .tagged_union,
            .tagged_union_trailing,
            .tagged_union_two,
            .tagged_union_two_trailing,
            .tagged_union_enum_tag,
            .tagged_union_enum_tag_trailing,
            => {
                try process_container_decl(
                    allocator,
                    ast,
                    source,
                    edits,
                    node_index,
                    line_index,
                );
            },
            .block,
            .block_semicolon,
            .block_two,
            .block_two_semicolon,
            => {
                try process_labeled_block(
                    allocator,
                    ast,
                    source,
                    edits,
                    node_index,
                    line_index,
                );
            },
            else => {},
        }
    }
}

/// Collect edits for function signature breaking (ALWAYS done, not just for
/// long lines)
fn collect_function_signature_edits(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const tags = ast.nodes.items(.tag);
    const node_data = ast.nodes.items(.data);

    for (0..ast.nodes.len)
        |i|
    {
        const tag = tags[i];

        // Handle function declarations - ALWAYS break parameter lists
        if (tag == .fn_decl)
        {
            const data = node_data[i];
            const proto_node: Ast.Node.Index = data.node_and_node[0];
            try break_function_params(
                allocator,
                ast,
                source,
                edits,
                proto_node,
                line_index,
            );
        }
    }
}

/// Collect edits to break long lines (for calls, struct inits, etc.)
fn collect_line_break_edits(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    long_lines: []const LongLine,
    condition_ranges: []const ConditionRange,
    grouped_expr_ranges: []const GroupedExprRange,
    line_index: *const LineIndex,
    parent_map: *const ParentMap,
) std.mem.Allocator.Error!void
{
    const tags = ast.nodes.items(.tag);
    const main_tokens = ast.nodes.items(.main_token);

    // For each long line, try to find appropriate break points.
    // Only break one construct per line per iteration — the iterative loop
    // in format() will handle deeper nesting on subsequent passes.
    //
    // Priority: function calls first, then struct inits, then other
    // constructs.
    // This ensures that when a function call wraps a struct literal (e.g.,
    // addExecutable(.{ ... })), the call is broken before its argument,
    // producing cleaner nested formatting.
    for (long_lines)
        |line|
    {
        const edits_before = edits.items.len;

        // Single pass: collect best candidates for each construct type.
        // Priority order (applied after the loop):
        //   1. Function calls — outermost (earliest source position) first
        //   2. Struct inits — first by node index
        //   3. Arithmetic binary ops / grouped expressions — first by node
        //      index
        var best_call: ?Ast.Node.Index = null;
        var best_call_start: usize = std.math.maxInt(usize);
        var first_struct_init: ?Ast.Node.Index = null;
        var first_binary_op: ?Ast.Node.Index = null;
        var first_grouped: ?Ast.Node.Index = null;
        var first_if_else: ?Ast.Node.Index = null;
        var has_bool_chain: bool = false;

        for (0..ast.nodes.len)
            |i|
        {
            const node_index: Ast.Node.Index = @enumFromInt(i);
            const main_token = main_tokens[@intFromEnum(node_index)];
            const token_start = ast.tokens.items(.start)[main_token];

            if (
                token_start < line.line_start
                or token_start >= line.line_end
            )
            {
                continue;
            }

            const tag = tags[@intFromEnum(node_index)];

            if (
                tag == .bool_and
                or tag == .bool_or
            )
            {
                has_bool_chain = true;
            }

            if (is_call_tag(tag))
            {
                if (token_start < best_call_start)
                {
                    best_call_start = token_start;
                    best_call = node_index;
                }
            }

            if (is_struct_init_tag(tag))
            {
                if (first_struct_init == null)
                {
                    first_struct_init = node_index;
                }
            }

            if (is_arithmetic_binary_op_tag(tag))
            {
                if (first_binary_op == null)
                {
                    first_binary_op = node_index;
                }
            }

            if (tag == .grouped_expression)
            {
                if (first_grouped == null)
                {
                    first_grouped = node_index;
                }
            }

            if (tag == .@"if")
            {
                if (first_if_else == null)
                {
                    first_if_else = node_index;
                }
            }
        }

        // Resolve arithmetic binary op to chain root so we collect all
        // operators in the full chain, not just the inner (first-by-index)
        // node.
        if (first_binary_op)
            |bo|
        {
            first_binary_op = find_chain_root(
                parent_map,
                tags,
                bo,
                is_arithmetic_binary_op_tag,
            );
        }

        // Priority 1: try function calls (outermost first).
        // Skip when the line also contains a boolean chain (bool_and /
        // bool_or) — those lines are handled by
        // collect_boolean_condition_edits /
        // collect_chain_expression_wrap_edits.
        // Breaking a function call here would conflict with those edits.
        if (has_bool_chain)
        {
            best_call = null;
        }

        // Also skip function calls that are inside a grouped
        // expression with a complex inner node (if, while, etc.).
        // Breaking the inner call produces ugly results; the grouped
        // expression handler will break at the outer parens instead.
        if (
            best_call != null
            and first_grouped != null
        )
        {
            const ge = first_grouped.?;
            const ge_main = main_tokens[@intFromEnum(ge)];
            const ge_lparen = ast.tokens.items(.start)[ge_main];
            const ge_data = ast.nodes.items(.data)[
                @intFromEnum(ge)
            ];
            const ge_rparen_tok: Ast.TokenIndex = (
                ge_data.node_and_token[1]
            );
            const ge_rparen = ast.tokens.items(.start)[
                ge_rparen_tok
            ];
            if (
                best_call_start > ge_lparen
                and best_call_start < ge_rparen
            )
            {
                const ge_inner: Ast.Node.Index = (
                    ge_data.node_and_token[0]
                );
                const ge_inner_tag = tags[
                    @intFromEnum(ge_inner)
                ];
                const ge_is_complex = switch (ge_inner_tag) {
                    .@"if",
                    .if_simple,
                    .@"while",
                    .while_simple,
                    .while_cont,
                    .@"for",
                    .for_simple,
                    .bool_and,
                    .bool_or,
                    .@"switch",
                    .switch_comma,
                    => true,
                    else => false,
                };
                if (ge_is_complex)
                {
                    best_call = null;
                }
            }
        }
        // Also skip function calls inside an if/else expression —
        // breaking at the `else` keyword is preferable.
        if (
            best_call != null
            and first_if_else != null
        )
        {
            const ie_first = ast.firstToken(first_if_else.?);
            const ie_last = ast.lastToken(first_if_else.?);
            const ie_start = ast.tokens.items(.start)[ie_first];
            const ie_end = ast.tokens.items(.start)[ie_last];
            if (
                best_call_start > ie_start
                and best_call_start <= ie_end
            )
            {
                best_call = null;
            }
        }
        if (best_call)
            |call_node|
        {
            try break_function_call(
                allocator,
                ast,
                source,
                edits,
                call_node,
                line,
                line_index,
            );
        }

        // Priority 1b: break if/else at the `else` keyword.
        // Skip if the if/else is inside a multiline grouped
        // expression that needs collapsing — that will be handled
        // by break_grouped_expression at priority 3.
        if (
            edits.items.len == edits_before
            and first_if_else != null
        )
        {
            var skip_if_else = false;
            if (first_grouped)
                |ge_node|
            {
                const ge_lparen_tok = (
                    main_tokens[@intFromEnum(ge_node)]
                );
                const ge_data = ast.nodes.items(.data)[
                    @intFromEnum(ge_node)
                ];
                const ge_rparen_tok: Ast.TokenIndex = (
                    ge_data.node_and_token[1]
                );
                const ge_lparen_start = (
                    ast.tokens.items(.start)[ge_lparen_tok]
                );
                const ge_rparen_start = (
                    ast.tokens.items(.start)[ge_rparen_tok]
                );
                // If grouped expression is multiline, let the
                // collapse at priority 3 handle it instead.
                if (
                    !line_index.same_line(
                        ge_lparen_start,
                        ge_rparen_start,
                    )
                )
                {
                    skip_if_else = true;
                }
            }
            if (!skip_if_else)
            {
                try break_if_else_expression(
                    allocator,
                    ast,
                    source,
                    edits,
                    first_if_else.?,
                    line,
                    line_index,
                );
            }
        }

        // Priority 2: try struct inits (only if no call was broken)
        if (edits.items.len == edits_before)
        {
            if (first_struct_init)
                |si_node|
            {
                try break_struct_init(
                    allocator,
                    ast,
                    source,
                    edits,
                    si_node,
                    line_index,
                );
            }
        }

        // Priority 3: try binary ops / grouped expressions (only if
        // nothing was broken yet). Try whichever has the lower node index
        // first, matching the original interleaved iteration order.
        if (edits.items.len == edits_before)
        {
            const bin_idx: usize = (
                if (first_binary_op) |n| @intFromEnum(n)
                else std.math.maxInt(usize)
            );
            const grp_idx: usize = (
                if (first_grouped) |n| @intFromEnum(n)
                else std.math.maxInt(usize)
            );

            if (bin_idx <= grp_idx)
            {
                // Try binary op first (or only)
                if (first_binary_op)
                    |bo_node|
                {
                    try break_binary_expression(
                        allocator,
                        ast,
                        source,
                        edits,
                        bo_node,
                        line,
                        line_index,
                    );
                }

                if (
                    edits.items.len == edits_before
                    and first_grouped != null
                )
                {
                    try break_grouped_expression(
                        allocator,
                        ast,
                        source,
                        edits,
                        condition_ranges,
                        grouped_expr_ranges,
                        first_grouped.?,
                        line,
                        line_index,
                    );
                }
            }
            else
            {
                // Try grouped first
                if (first_grouped)
                    |ge_node|
                {
                    try break_grouped_expression(
                        allocator,
                        ast,
                        source,
                        edits,
                        condition_ranges,
                        grouped_expr_ranges,
                        ge_node,
                        line,
                        line_index,
                    );
                }

                if (
                    edits.items.len == edits_before
                    and first_binary_op != null
                )
                {
                    try break_binary_expression(
                        allocator,
                        ast,
                        source,
                        edits,
                        first_binary_op.?,
                        line,
                        line_index,
                    );
                }
            }
        }

        // Pass 4: try breaking at catch keyword
        if (edits.items.len == edits_before)
        {
            const token_tags = ast.tokens.items(.tag);
            const token_starts = ast.tokens.items(.start);

            for (0..ast.tokens.len)
                |tok_i|
            {
                if (edits.items.len > edits_before)
                {
                    break;
                }

                if (token_tags[tok_i] != .keyword_catch)
                {
                    continue;
                }

                const tok_start = token_starts[tok_i];
                if (
                    tok_start < line.line_start
                    or tok_start >= line.line_end
                )
                {
                    continue;
                }

                const base_indent = get_line_indent(
                    source,
                    line.line_start,
                );

                // Find whitespace before catch
                var ws_start = tok_start;
                while (
                    ws_start > line.line_start
                    and (
                        source[ws_start - 1] == ' '
                        or source[ws_start - 1] == '\t'
                    )
                )
                {
                    ws_start -= 1;
                }

                const indent_text = try std.fmt.allocPrint(
                    allocator,
                    "\n{s}    ",
                    .{base_indent},
                );
                try edits.append(
                    allocator,
                    .{
                        .start_byte = ws_start,
                        .end_byte = tok_start,
                        .new_text = indent_text,
                    },
                );
            }
        }
    }
}

/// Collect edits to ALWAYS break conditions containing boolean operators
/// (and/or)
/// This runs regardless of line length - conditions with boolean ops should
/// always be broken
fn collect_boolean_condition_edits(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const tags = ast.nodes.items(.tag);
    const main_tokens = ast.nodes.items(.main_token);
    const token_tags = ast.tokens.items(.tag);
    const token_starts = ast.tokens.items(.start);

    for (0..ast.nodes.len)
        |i|
    {
        const node_index: Ast.Node.Index = @enumFromInt(i);
        const tag = tags[@intFromEnum(node_index)];

        // Handle if statements
        if (
            tag == .@"if"
            or tag == .if_simple
        )
        {
            const if_info = ast.fullIf(node_index) orelse continue;

            // Check if condition contains boolean operators
            if (
                !condition_contains_boolean_op(
                    ast,
                    token_tags,
                    if_info.ast.cond_expr,
                )
            )
            {
                continue;
            }

            // Get base indentation from the if keyword
            const if_token = main_tokens[@intFromEnum(node_index)];
            const base_indent = get_line_indent(
                source,
                line_index.line_start(token_starts[if_token]),
            );

            // Find the opening paren after 'if'
            var lparen_tok = if_token + 1;
            while (
                lparen_tok < ast.tokens.len
                and token_tags[lparen_tok] != .l_paren
            )
            {
                lparen_tok += 1;
            }
            if (lparen_tok >= ast.tokens.len)
            {
                continue;
            }

            // Find the closing paren of the condition
            const cond_last_tok = ast.lastToken(if_info.ast.cond_expr);
            const rparen_tok = cond_last_tok + 1;

            // Check if already broken (lparen and rparen on different lines)
            if (
                !line_index.same_line(
                    token_starts[lparen_tok],
                    token_starts[rparen_tok],
                )
            )
            {
                continue;
            } // Already multi-line

            // Break the condition hierarchically
            try break_condition_hierarchically(
                allocator,
                ast,
                source,
                edits,
                lparen_tok,
                rparen_tok,
                base_indent,
            );
        }

        // Handle while statements
        if (
            tag == .@"while"
            or tag == .while_simple
            or tag == .while_cont
        )
        {
            const while_info = ast.fullWhile(node_index) orelse continue;

            // Check if condition contains boolean operators
            if (
                !condition_contains_boolean_op(
                    ast,
                    token_tags,
                    while_info.ast.cond_expr,
                )
            )
            {
                continue;
            }

            // Get base indentation from the while keyword
            const while_token = while_info.ast.while_token;
            const base_indent = get_line_indent(
                source,
                line_index.line_start(token_starts[while_token]),
            );

            // Find the opening paren after 'while'
            var lparen_tok = while_token + 1;
            while (
                lparen_tok < ast.tokens.len
                and token_tags[lparen_tok] != .l_paren
            )
            {
                lparen_tok += 1;
            }
            if (lparen_tok >= ast.tokens.len)
            {
                continue;
            }

            // Find the closing paren of the condition
            const cond_last_tok = ast.lastToken(while_info.ast.cond_expr);
            const rparen_tok = cond_last_tok + 1;

            // Check if already broken
            if (
                !line_index.same_line(
                    token_starts[lparen_tok],
                    token_starts[rparen_tok],
                )
            )
            {
                continue;
            }

            try break_condition_hierarchically(
                allocator,
                ast,
                source,
                edits,
                lparen_tok,
                rparen_tok,
                base_indent,
            );
        }

        // Note: For loops in Zig don't have a condition in the same way
        // if/while do
        // They iterate over ranges/slices, so boolean condition breaking
        // doesn't apply
    }
}

/// Return true if the given node tag is a comparison operator.
fn is_comparison_op_tag(
    tag: Ast.Node.Tag,
) bool
{
    return switch (tag) {
        .equal_equal,
        .bang_equal,
        .less_than,
        .greater_than,
        .less_or_equal,
        .greater_or_equal,
        => true,
        else => false,
    };
}

/// Collect edits to break long if/while conditions that contain a
/// single comparison (no boolean operators).  Breaks after `(`,
/// before the comparison operator, and before `)`.
fn collect_comparison_condition_edits(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const tags = ast.nodes.items(.tag);
    const main_tokens = ast.nodes.items(.main_token);
    const token_tags = ast.tokens.items(.tag);
    const token_starts = ast.tokens.items(.start);

    for (0..ast.nodes.len)
        |i|
    {
        const node_index: Ast.Node.Index = @enumFromInt(i);
        const tag = tags[@intFromEnum(node_index)];

        var cond_expr: Ast.Node.Index = undefined;
        var keyword_tok: Ast.TokenIndex = undefined;

        if (
            tag == .@"if"
            or tag == .if_simple
        )
        {
            const if_info = ast.fullIf(node_index) orelse continue;
            cond_expr = if_info.ast.cond_expr;
            keyword_tok = main_tokens[@intFromEnum(node_index)];
        }
        else if (
            tag == .@"while"
            or tag == .while_simple
            or tag == .while_cont
        )
        {
            const while_info = ast.fullWhile(node_index) orelse continue;
            cond_expr = while_info.ast.cond_expr;
            keyword_tok = while_info.ast.while_token;
        }
        else
        {
            continue;
        }

        // Skip if condition contains boolean operators — those
        // are handled by collect_boolean_condition_edits
        if (
            condition_contains_boolean_op(
                ast,
                token_tags,
                cond_expr,
            )
        )
        {
            continue;
        }

        // Only handle conditions whose root is a comparison
        const cond_tag = tags[@intFromEnum(cond_expr)];
        if (!is_comparison_op_tag(cond_tag))
        {
            continue;
        }

        // Find the opening paren after the keyword
        var lparen_tok = keyword_tok + 1;
        while (
            lparen_tok < ast.tokens.len
            and token_tags[lparen_tok] != .l_paren
        )
        {
            lparen_tok += 1;
        }
        if (lparen_tok >= ast.tokens.len)
        {
            continue;
        }

        // Find the closing paren
        const cond_last_tok = ast.lastToken(cond_expr);
        const rparen_tok = cond_last_tok + 1;

        // Check if already broken
        const lparen_byte = token_starts[lparen_tok];
        const rparen_byte = token_starts[rparen_tok];
        if (!line_index.same_line(lparen_byte, rparen_byte))
        {
            continue;
        }

        // Only break if the condition extends past the limit.
        // Check that the line is too long AND the closing ')'
        // is at or past the column limit — if ')' is well within
        // the limit, something else on the line is the problem
        // (e.g. a continue expression), not the condition.
        const lparen_line_start = line_index.line_start(lparen_byte);
        const line_len = compute_line_length(
            source,
            lparen_line_start,
        );
        const rparen_column = rparen_byte - line_index.line_start(
            rparen_byte,
        );
        if (
            line_len <= MAX_LINE_LENGTH
            or rparen_column < MAX_LINE_LENGTH
        )
        {
            continue;
        }

        const base_indent = get_line_indent(
            source,
            lparen_line_start,
        );

        // Find the comparison operator token
        const cmp_main_tok = main_tokens[@intFromEnum(cond_expr)];
        const cmp_start = token_starts[cmp_main_tok];

        // 1. Break after '(' — insert newline + indent
        const lparen_start = token_starts[lparen_tok];
        const lparen_end = lparen_start + 1;
        const ws_after_lparen = skip_whitespace_fwd(source, lparen_end);

        const open_indent = try std.fmt.allocPrint(
            allocator,
            "\n{s}    ",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = lparen_end,
                .end_byte = ws_after_lparen,
                .new_text = open_indent,
            },
        );

        // 2. Break before the comparison operator
        const ws_before_cmp = skip_whitespace_back(source, cmp_start);

        const cmp_indent = try std.fmt.allocPrint(
            allocator,
            "\n{s}    ",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = ws_before_cmp,
                .end_byte = cmp_start,
                .new_text = cmp_indent,
            },
        );

        // 3. Break before ')'
        const rparen_start = token_starts[rparen_tok];
        const ws_before_rparen = skip_whitespace_back(source, rparen_start);

        const close_indent = try std.fmt.allocPrint(
            allocator,
            "\n{s}",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = ws_before_rparen,
                .end_byte = rparen_start,
                .new_text = close_indent,
            },
        );
    }
}

/// Check whether the expression spanning `first_tok`..`last_tok` is
/// immediately enclosed in parentheses (the preceding token is `(` and the
/// following token is `)`).
fn is_already_wrapped_in_parens(
    ast: *const Ast,
    first_tok: Ast.TokenIndex,
    last_tok: Ast.TokenIndex,
) bool
{
    if (first_tok > 0)
    {
        const prev_tag = ast.tokens.items(.tag)[first_tok - 1];
        if (prev_tag == .l_paren)
        {
            if (
                last_tok + 1 < ast.tokens.len
                and ast.tokens.items(.tag)[last_tok + 1] == .r_paren
            )
            {
                return true;
            }
        }
    }
    return false;
}

/// Emit line-break edits before each operator position.
/// Iterates `op_positions` (sorted byte offsets), deduplicates, and for each
/// operator replaces the whitespace preceding it with a newline followed by
/// `base_indent` plus four spaces of extra indentation.
fn emit_operator_breaks(
    allocator: std.mem.Allocator,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    op_positions: *const std.ArrayListUnmanaged(usize),
    base_indent: []const u8,
) std.mem.Allocator.Error!void
{
    var last_pos: ?usize = null;
    for (op_positions.items)
        |op_start|
    {
        if (
            last_pos != null
            and op_start == last_pos.?
        )
        {
            continue;
        }
        last_pos = op_start;

        const ws_start = skip_whitespace_back(source, op_start);

        const indent_text = try std.fmt.allocPrint(
            allocator,
            "\n{s}    ",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = ws_start,
                .end_byte = op_start,
                .new_text = indent_text,
            },
        );
    }
}

/// Collect edits to wrap long boolean and/or chains outside of if/while
/// conditions.
/// For chains that exceed MAX_LINE_LENGTH, wraps them in parentheses and
/// breaks
/// before each operator.
fn collect_chain_expression_wrap_edits(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    parent_map: *const ParentMap,
    condition_ranges: []const ConditionRange,
    comptime is_chain_tag: fn (Ast.Node.Tag) bool,
    check_boolean_condition: bool,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const tags = ast.nodes.items(.tag);

    for (0..ast.nodes.len)
        |i|
    {
        const node_index: Ast.Node.Index = @enumFromInt(i);
        const tag = tags[@intFromEnum(node_index)];

        // Only process nodes matching the chain tag predicate
        if (!is_chain_tag(tag))
        {
            continue;
        }

        // Only process if this is the root of the chain
        if (
            find_chain_root(
                parent_map,
                tags,
                node_index,
                is_chain_tag,
            ) != node_index
        )
        {
            continue;
        }

        // Skip if inside an if/while condition (handled by
        // collect_boolean_condition_edits)
        if (
            check_boolean_condition and is_position_inside_boolean_condition(
                condition_ranges,
                ast.tokens.items(.start)[ast.firstToken(node_index)],
                false,
            )
        )
        {
            continue;
        }

        // Check if already multiline
        const first_tok = ast.firstToken(node_index);
        const last_tok = ast.lastToken(node_index);
        const token_starts = ast.tokens.items(.start);
        const first_byte = token_starts[first_tok];
        const last_byte = token_starts[last_tok];
        const is_multiline = !line_index.same_line(first_byte, last_byte);

        // Check line length
        const l_start = line_index.line_start(first_byte);
        const line_len = compute_line_length(source, l_start);
        if (line_len <= MAX_LINE_LENGTH)
        {
            continue;
        }

        // Get base indentation
        const base_indent = get_line_indent(source, l_start);

        // Check if already wrapped in parentheses (parent is
        // grouped_expression)
        const already_wrapped = is_already_wrapped_in_parens(
            ast,
            first_tok,
            last_tok,
        );

        // Collect all operator positions in the chain
        var op_positions: std.ArrayListUnmanaged(usize) = .{};
        defer op_positions.deinit(allocator);
        try collect_ops_in_chain(
            allocator,
            ast,
            node_index,
            is_chain_tag,
            &op_positions,
        );

        // Sort positions
        std.mem.sort(usize, op_positions.items, {}, std.sort.asc(usize));

        if (op_positions.items.len == 0)
        {
            continue;
        }

        if (
            is_multiline
            and already_wrapped
        )
        {
            // Already multiline and wrapped — but the first line
            // might still be too long (e.g. the whole chain starts
            // on one long line and only subsequent operands are
            // broken).  If the line is within the limit, skip.
            if (line_len <= MAX_LINE_LENGTH)
            {
                continue;
            }
            // Otherwise fall through to break at operators.
        }

        if (
            is_multiline
            and !already_wrapped
        )
        {
            if (!check_boolean_condition)
            {
                // For non-boolean chains (e.g. array_cat), skip
                // multiline expressions that aren't wrapped — no
                // special handling needed.
                continue;
            }

            // Already multiline (operators on separate lines) but
            // not wrapped in parens — add outer parens so the first
            // operand moves to its own line.
            const expr_start = ast.tokens.items(.start)[first_tok];

            const open_text = try std.fmt.allocPrint(
                allocator,
                "(\n{s}    ",
                .{base_indent},
            );
            try edits.append(
                allocator,
                .{
                    .start_byte = expr_start,
                    .end_byte = expr_start,
                    .new_text = open_text,
                },
            );

            // Find end of last token using tokenSlice for
            // accuracy
            const last_tok_start = ast.tokens.items(.start)[last_tok];
            const last_tok_slice = ast.tokenSlice(last_tok);
            const last_tok_end = last_tok_start + last_tok_slice.len;

            // Consume any trailing whitespace/newlines between
            // the last token and the terminator (;,) etc)
            var insert_pos = last_tok_end;
            while (
                insert_pos < source.len
                and (
                    source[insert_pos] == ' '
                    or source[insert_pos] == '\t'
                    or source[insert_pos] == '\n'
                )
            )
            {
                insert_pos += 1;
            }

            const close_text = try std.fmt.allocPrint(
                allocator,
                "\n{s})",
                .{base_indent},
            );
            try edits.append(
                allocator,
                .{
                    .start_byte = last_tok_end,
                    .end_byte = insert_pos,
                    .new_text = close_text,
                },
            );

            continue;
        }

        if (!already_wrapped)
        {
            // Single-line, not wrapped: add parens and break at
            // operators
            const expr_start = ast.tokens.items(.start)[first_tok];

            const open_text = try std.fmt.allocPrint(
                allocator,
                "(\n{s}    ",
                .{base_indent},
            );
            try edits.append(
                allocator,
                .{
                    .start_byte = expr_start,
                    .end_byte = expr_start,
                    .new_text = open_text,
                },
            );

            // Break before each operator (skip duplicates)
            try emit_operator_breaks(
                allocator,
                source,
                edits,
                &op_positions,
                base_indent,
            );

            // Insert closing paren after the last token.
            // Use tokenSlice to get the true token length — the
            // character-scanning approach breaks on string
            // literals which contain spaces/newlines internally.
            const last_tok_start = ast.tokens.items(.start)[last_tok];
            const last_tok_slice = ast.tokenSlice(last_tok);
            const last_tok_end = last_tok_start + last_tok_slice.len;

            const close_text = try std.fmt.allocPrint(
                allocator,
                "\n{s})",
                .{base_indent},
            );
            try edits.append(
                allocator,
                .{
                    .start_byte = last_tok_end,
                    .end_byte = last_tok_end,
                    .new_text = close_text,
                },
            );
        }
        else
        {
            // Already wrapped in parens, just break before each
            // operator
            try emit_operator_breaks(
                allocator,
                source,
                edits,
                &op_positions,
                base_indent,
            );
        }
    }
}

/// Find the root of a boolean operator chain by walking up through left
/// children.
/// In Zig's AST, `a and b and c` is `bool_and(bool_and(a, b), c)`
/// (left-associative),
/// so the root is the outermost bool_and/bool_or whose parent's left child is
/// NOT
/// also a bool_and/bool_or.
fn is_bool_chain_tag(
    tag: Ast.Node.Tag,
) bool
{
    return tag == .bool_and or tag == .bool_or;
}

fn is_array_cat_tag(
    tag: Ast.Node.Tag,
) bool
{
    return tag == .array_cat;
}

fn find_chain_root(
    parent_map: *const ParentMap,
    tags: []const Ast.Node.Tag,
    node_index: Ast.Node.Index,
    comptime is_chain_tag: fn (Ast.Node.Tag) bool,
) Ast.Node.Index
{
    if (!is_chain_tag(tags[@intFromEnum(node_index)]))
    {
        return node_index;
    }
    var current = node_index;
    while (parent_map.get(current))
        |parent|
    {
        if (!is_chain_tag(tags[@intFromEnum(parent)]))
        {
            break;
        }
        current = parent;
    }
    return current;
}

/// Check if a boolean operator node is inside an if/while condition.
fn is_position_inside_boolean_condition(
    condition_ranges: []const ConditionRange,
    byte_offset: usize,
    require_boolean_op: bool,
) bool
{
    if (condition_ranges.len == 0)
    {
        return false;
    }

    // Binary search: find the rightmost range whose start < byte_offset.
    // All ranges that could contain byte_offset must have start < byte_offset
    // (the original check was strict: byte_offset > lparen_start).
    var lo: usize = 0;
    var hi: usize = condition_ranges.len;
    while (lo < hi)
    {
        const mid = lo + (hi - lo) / 2;
        if (condition_ranges[mid].start < byte_offset)
        {
            lo = mid + 1;
        }
        else
        {
            hi = mid;
        }
    }
    // lo is now the count of ranges with start < byte_offset.
    // Scan backward from lo-1 to check if any range contains byte_offset.
    // Because ranges can be nested, we check all candidates whose start
    // is less than byte_offset; we stop early when a range's end is too
    // small and start is far before byte_offset (outer ranges have smaller
    // start but larger end, so we keep scanning).
    var idx = lo;
    while (idx > 0)
    {
        idx -= 1;
        const r = condition_ranges[idx];
        // Original semantics: byte_offset > start and byte_offset < end
        if (
            byte_offset > r.start
            and byte_offset < r.end
        )
        {
            if (
                !require_boolean_op
                or r.has_boolean_op
            )
            {
                return true;
            }
        }
    }

    return false;
}

/// Recursively collect byte positions of bool_and/bool_or operators in a
/// chain.
fn collect_ops_in_chain(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    node_index: Ast.Node.Index,
    comptime is_chain_tag: fn (Ast.Node.Tag) bool,
    positions: *std.ArrayListUnmanaged(usize),
) std.mem.Allocator.Error!void
{
    const tags = ast.nodes.items(.tag);
    const main_tokens = ast.nodes.items(.main_token);
    const node_data = ast.nodes.items(.data);

    const tag = tags[@intFromEnum(node_index)];
    if (!is_chain_tag(tag))
    {
        return;
    }

    const op_token = main_tokens[@intFromEnum(node_index)];
    const op_start = ast.tokens.items(.start)[op_token];
    try positions.append(allocator, op_start);

    const data = node_data[@intFromEnum(node_index)];
    const lhs: Ast.Node.Index = data.node_and_node[0];
    const rhs: Ast.Node.Index = data.node_and_node[1];

    if (@intFromEnum(lhs) != 0)
    {
        try collect_ops_in_chain(
            allocator,
            ast,
            lhs,
            is_chain_tag,
            positions,
        );
    }
    if (@intFromEnum(rhs) != 0)
    {
        try collect_ops_in_chain(
            allocator,
            ast,
            rhs,
            is_chain_tag,
            positions,
        );
    }
}

/// Collect edits to wrap long array_cat (++) chains.
/// For chains that exceed MAX_LINE_LENGTH, wraps them in parentheses and
/// breaks before each operator.
/// Collect edits to fix stacked closing parens in multi-line if/while
/// conditions.
/// When a condition contains a multi-line expression (e.g. a function call
/// with
/// already-broken arguments), the outer condition parens need to be properly
/// broken
/// so that each closing paren is on its own line rather than stacked like
/// `))`.
fn collect_stacked_paren_edits(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const tags = ast.nodes.items(.tag);
    const main_tokens = ast.nodes.items(.main_token);
    const token_tags = ast.tokens.items(.tag);
    const token_starts = ast.tokens.items(.start);

    for (0..ast.nodes.len)
        |i|
    {
        const node_index: Ast.Node.Index = @enumFromInt(i);
        const tag = tags[@intFromEnum(node_index)];

        var lparen_tok: Ast.TokenIndex = undefined;
        var rparen_tok: Ast.TokenIndex = undefined;
        var base_indent: []const u8 = undefined;

        if (
            tag == .@"if"
            or tag == .if_simple
        )
        {
            const if_info = ast.fullIf(node_index) orelse continue;

            const if_token = main_tokens[@intFromEnum(node_index)];
            base_indent = get_line_indent(
                source,
                line_index.line_start(token_starts[if_token]),
            );

            // Find the opening paren after 'if'
            lparen_tok = if_token + 1;
            while (
                lparen_tok < ast.tokens.len
                and token_tags[lparen_tok] != .l_paren
            )
            {
                lparen_tok += 1;
            }
            if (lparen_tok >= ast.tokens.len)
            {
                continue;
            }

            // Find the closing paren of the condition
            const cond_last_tok = ast.lastToken(if_info.ast.cond_expr);
            rparen_tok = cond_last_tok + 1;
        }
        else if (
            tag == .@"while"
            or tag == .while_simple
            or tag == .while_cont
        )
        {
            const while_info = ast.fullWhile(node_index) orelse continue;

            const while_token = while_info.ast.while_token;
            base_indent = get_line_indent(
                source,
                line_index.line_start(token_starts[while_token]),
            );

            // Find the opening paren after 'while'
            lparen_tok = while_token + 1;
            while (
                lparen_tok < ast.tokens.len
                and token_tags[lparen_tok] != .l_paren
            )
            {
                lparen_tok += 1;
            }
            if (lparen_tok >= ast.tokens.len)
            {
                continue;
            }

            // Find the closing paren of the condition
            const cond_last_tok = ast.lastToken(while_info.ast.cond_expr);
            rparen_tok = cond_last_tok + 1;
        }
        else
        {
            continue;
        }

        // Verify rparen is actually a r_paren
        if (
            rparen_tok >= ast.tokens.len
            or token_tags[rparen_tok] != .r_paren
        )
        {
            continue;
        }

        // Check if condition spans multiple lines
        if (
            line_index.same_line(
                token_starts[lparen_tok],
                token_starts[rparen_tok],
            )
        )
        {
            continue;
        } // Single-line, skip

        // Check if the first non-whitespace token after outer '(' is on the
        // same line
        // If it's already on a different line, the outer paren is already
        // properly broken
        const lparen_end = token_starts[lparen_tok] + 1; // byte after '('
        const next_tok = lparen_tok + 1;
        if (next_tok >= ast.tokens.len)
        {
            continue;
        }
        const next_tok_start = token_starts[next_tok];

        if (
            !line_index.same_line(
                token_starts[next_tok],
                token_starts[lparen_tok],
            )
        )
        {
            continue;
        } // Already broken after '(' — skip

        // The content after '(' is on the same line as '(' but the ')' is on
        // a different line.
        // This means we have stacked parens that need fixing.

        // Edit A: After outer '(' — replace trailing whitespace/content-gap
        // with newline + indent
        const inner_indent = try std.fmt.allocPrint(
            allocator,
            "\n{s}    ",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = lparen_end,
                .end_byte = next_tok_start,
                .new_text = inner_indent,
            },
        );

        const rparen_start = token_starts[rparen_tok];

        // Edit B: Re-indent all interior lines between outer '(' and outer
        // ')' by adding 4 extra spaces of indentation.
        try reindent_interior_lines(
            allocator,
            source,
            edits,
            lparen_end,
            rparen_start,
            "    ",
        );

        // Edit C: Before outer ')' — put it on its own line at base_indent
        // Find the whitespace before the outer rparen
        const ws_before_rparen = skip_whitespace_back(source, rparen_start);

        // Check if the rparen already starts its own line
        if (
            ws_before_rparen > 0
            and source[ws_before_rparen - 1] == '\n'
        )
        {
            // Already on its own line, just fix indentation
            const rparen_indent = try std.fmt.allocPrint(
                allocator,
                "{s}",
                .{base_indent},
            );
            try edits.append(
                allocator,
                .{
                    .start_byte = ws_before_rparen,
                    .end_byte = rparen_start,
                    .new_text = rparen_indent,
                },
            );
        }
        else
        {
            // Not on its own line — need to split it
            const rparen_indent = try std.fmt.allocPrint(
                allocator,
                "\n{s}",
                .{base_indent},
            );
            try edits.append(
                allocator,
                .{
                    .start_byte = ws_before_rparen,
                    .end_byte = rparen_start,
                    .new_text = rparen_indent,
                },
            );
        }
    }
}

/// Collect edits for multiline function calls and struct inits that are not
/// properly structured. When a call/struct-init already spans multiple lines
/// (e.g. because an inner struct was broken), normalize it: opening delimiter
/// followed by newline, content indented, trailing comma, closing delimiter
/// on
/// its own line. Processes outermost (earliest source position) first and
/// emits
/// at most one edit set per pass — the iterative loop handles deeper
/// nesting.
fn collect_multiline_structural_edits(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const tags = ast.nodes.items(.tag);
    const main_tokens = ast.nodes.items(.main_token);
    const token_tags = ast.tokens.items(.tag);
    const token_starts = ast.tokens.items(.start);

    // We want to find the outermost (earliest source position) construct that
    // needs structural fixing. Track the best candidate.
    var best_open_pos: usize = std.math.maxInt(usize);
    var best_node: ?Ast.Node.Index = null;
    var best_is_call: bool = false;

    for (0..ast.nodes.len)
        |i|
    {
        const node_index: Ast.Node.Index = @enumFromInt(i);
        const tag = tags[@intFromEnum(node_index)];

        var is_call = false;
        var is_struct_init = false;

        if (is_call_tag(tag))
        {
            is_call = true;
        }
        else if (is_struct_init_tag(tag))
        {
            is_struct_init = true;
        }

        if (
            !is_call
            and !is_struct_init
        )
        {
            continue;
        }

        const main_tok = main_tokens[@intFromEnum(node_index)];

        // For calls, main_token is lparen; for struct inits, it's lbrace
        const open_tag = (
            if (is_call) std.zig.Token.Tag.l_paren
                else std.zig.Token.Tag.l_brace
        );
        const close_tag = (
            if (is_call) std.zig.Token.Tag.r_paren
                else std.zig.Token.Tag.r_brace
        );

        if (token_tags[main_tok] != open_tag)
        {
            continue;
        }

        const open_start = token_starts[main_tok];

        // Find the matching close delimiter
        const close_tok = find_matching_delimiter_rt(
            ast,
            main_tok,
            open_tag,
            close_tag,
        ) orelse continue;

        // Only process multiline constructs
        if (
            line_index.same_line(
                token_starts[main_tok],
                token_starts[close_tok],
            )
        )
        {
            continue;
        }

        // Skip if the opening line is too long — collect_line_break_edits
        // handles that
        const opening_line_len = compute_line_length(
            source,
            line_index.line_start(token_starts[main_tok]),
        );
        if (opening_line_len > MAX_LINE_LENGTH)
        {
            continue;
        }

        const close_start_pos = token_starts[close_tok];

        // Check if already properly structured:
        // 1. Character immediately after open delimiter (skipping
        // spaces/tabs) is '\n'
        const open_end = open_start + 1;
        const after_open = skip_whitespace_fwd(source, open_end);
        const opening_already_broken = (
            after_open < source.len
            and source[after_open] == '\n'
        );

        // 2. Character immediately before close delimiter (skipping
        // spaces/tabs) is '\n'
        const before_close = skip_whitespace_back(source, close_start_pos);
        const closing_on_own_line = (
            before_close > 0
            and source[before_close - 1] == '\n'
        );

        // 3. Last non-whitespace char before the '\n' before close delimiter
        // is ','
        var trailing_comma_present = false;
        if (closing_on_own_line)
        {
            var check = before_close - 1; // the '\n'
            if (check > 0)
            {
                check -= 1;
                while (
                    check > 0
                    and (
                        source[check] == ' '
                        or source[check] == '\t'
                    )
                )
                {
                    check -= 1;
                }
                trailing_comma_present = source[check] == ',';
            }
        }

        if (
            opening_already_broken
            and closing_on_own_line
            and trailing_comma_present
        )
        {
            continue;
        }

        // This construct needs fixing — track if it's the earliest
        if (open_start < best_open_pos)
        {
            best_open_pos = open_start;
            best_node = node_index;
            best_is_call = is_call;
        }
    }

    // Process the best candidate
    const node_index = best_node orelse return;
    const main_tok = main_tokens[@intFromEnum(node_index)];
    const open_tag = (
        if (best_is_call) std.zig.Token.Tag.l_paren
            else std.zig.Token.Tag.l_brace
    );
    const close_tag = (
        if (best_is_call) std.zig.Token.Tag.r_paren
            else std.zig.Token.Tag.r_brace
    );
    const open_start = token_starts[main_tok];
    const base_indent = get_line_indent(
        source,
        line_index.line_start(token_starts[main_tok]),
    );

    // Find the matching close delimiter again
    const close_tok = find_matching_delimiter_rt(
        ast,
        main_tok,
        open_tag,
        close_tag,
    ) orelse return;
    const close_start = token_starts[close_tok];

    // Edit A: After opening delimiter — replace whitespace with newline +
    // indent
    const open_end = open_start + 1;
    const after_open = skip_whitespace_fwd(source, open_end);
    if (
        after_open >= source.len
        or source[after_open] != '\n'
    )
    {
        const inner_indent = try std.fmt.allocPrint(
            allocator,
            "\n{s}    ",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = open_end,
                .end_byte = after_open,
                .new_text = inner_indent,
            },
        );
    }

    // Edit A2: Break after depth-0 commas that are on the same line as the
    // opener
    {
        var tok = main_tok + 1;
        var comma_depth: usize = 0;
        while (tok < close_tok)
        {
            const tok_tag = token_tags[tok];
            if (
                tok_tag == .l_paren
                or tok_tag == .l_brace
                or tok_tag == .l_bracket
            )
            {
                comma_depth += 1;
            }
            else if (
                tok_tag == .r_paren
                or tok_tag == .r_brace
                or tok_tag == .r_bracket
            )
            {
                if (comma_depth > 0)
                {
                    comma_depth -= 1;
                }
            }
            else if (
                tok_tag == .comma
                and comma_depth == 0
            )
            {
                const comma_pos = token_starts[tok];
                const comma_end = comma_pos + 1;
                const ws_end = skip_whitespace_fwd(source, comma_end);
                // Only break if not already followed by newline
                if (
                    ws_end < source.len
                    and source[ws_end] != '\n'
                )
                {
                    const arg_indent = try std.fmt.allocPrint(
                        allocator,
                        "\n{s}    ",
                        .{base_indent},
                    );
                    try edits.append(
                        allocator,
                        .{
                            .start_byte = comma_end,
                            .end_byte = ws_end,
                            .new_text = arg_indent,
                        },
                    );
                }
            }
            tok += 1;
        }
    }

    // Edit B: Re-indent interior lines between open and close delimiters
    try reindent_interior_lines(
        allocator,
        source,
        edits,
        open_end,
        close_start,
        "    ",
    );

    // Edit C: Add trailing comma if needed, and put close delimiter on own
    // line
    const ws_before_close = skip_whitespace_back(source, close_start);

    // Determine if trailing comma is already present
    var need_comma = true;
    if (
        ws_before_close > 0
        and source[ws_before_close - 1] == '\n'
    )
    {
        const check = skip_whitespace_back(source, ws_before_close - 1);
        if (
            check > 0
            and source[check - 1] == ','
        )
        {
            need_comma = false;
        }
    }
    else
    {
        if (
            ws_before_close > 0
            and source[ws_before_close - 1] == ','
        )
        {
            need_comma = false;
        }
    }

    const comma_str: []const u8 = if (need_comma) "," else "";

    if (
        ws_before_close > 0
        and source[ws_before_close - 1] == '\n'
    )
    {
        // Already on its own line, fix indentation (and possibly add comma)
        if (need_comma)
        {
            // before the '\n'
            const insert_pos = skip_whitespace_back(
                source,
                ws_before_close - 1,
            );
            try edits.append(
                allocator,
                .{
                    .start_byte = insert_pos,
                    .end_byte = insert_pos,
                    .new_text = ",",
                },
            );
        }
        // Fix indentation of the close delimiter line
        const close_indent = try std.fmt.allocPrint(
            allocator,
            "{s}",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = ws_before_close,
                .end_byte = close_start,
                .new_text = close_indent,
            },
        );
    }
    else
    {
        // Not on its own line — put it on one
        const close_indent = try std.fmt.allocPrint(
            allocator,
            "{s}\n{s}",
            .{ comma_str, base_indent },
        );
        try edits.append(
            allocator,
            .{
                .start_byte = ws_before_close,
                .end_byte = close_start,
                .new_text = close_indent,
            },
        );
    }
}

/// Check if a condition expression contains boolean operators (and/or)
fn condition_contains_boolean_op(
    ast: *const Ast,
    token_tags: []const std.zig.Token.Tag,
    cond_expr: Ast.Node.Index,
) bool
{
    const first_tok = ast.firstToken(cond_expr);
    const last_tok = ast.lastToken(cond_expr);

    // Scan tokens in the condition for boolean operators
    var tok = first_tok;
    while (tok <= last_tok)
    {
        if (
            token_tags[tok] == .keyword_and
            or token_tags[tok] == .keyword_or
        )
        {
            return true;
        }
        tok += 1;
    }

    return false;
}

/// Broad binary-op superset including arithmetic, boolean, comparison, and
/// array_cat tags.  Used by `collect_binary_ops_on_line` to collect ALL
/// operators in a mixed expression once the root node has been identified.
fn is_binary_op_tag(
    tag: Ast.Node.Tag,
) bool
{
    return switch (tag) {
        .add,
        .sub,
        .mul,
        .div,
        .mod,
        .bool_and,
        .bool_or,
        .bit_and,
        .bit_or,
        .bit_xor,
        .shl,
        .shr,
        .equal_equal,
        .bang_equal,
        .less_than,
        .greater_than,
        .less_or_equal,
        .greater_or_equal,
        .array_cat,
        => true,
        else => false,
    };
}

/// Narrower arithmetic/bitwise subset of binary operators.  Used by
/// `collect_line_break_edits` to identify nodes that should be broken at
/// arithmetic operators.  Excludes boolean, comparison, and array_cat tags
/// which are handled by separate wrapping passes.
fn is_arithmetic_binary_op_tag(
    tag: Ast.Node.Tag,
) bool
{
    return switch (tag) {
        .add,
        .sub,
        .mul,
        .div,
        .mod,
        .bit_and,
        .bit_or,
        .bit_xor,
        .shl,
        .shr,
        => true,
        else => false,
    };
}

/// Break an if/else expression before the `else` keyword.
fn break_if_else_expression(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    node_index: Ast.Node.Index,
    line: LongLine,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const token_starts = ast.tokens.items(.start);

    // Get the if info — only handle full if (with else)
    const if_info = ast.fullIf(node_index) orelse return;
    if (if_info.ast.else_expr == .none)
    {
        return;
    }

    const else_token = if_info.else_token;
    const else_start = token_starts[else_token];

    // Only break if the else is on the same line as the if
    const if_start = token_starts[ast.firstToken(node_index)];
    if (!line_index.same_line(if_start, else_start))
    {
        return;
    }

    // Only break if the if is on the target long line
    if (
        if_start < line.line_start
        or if_start >= line.line_end
    )
    {
        return;
    }

    // Indent the `else` to the same column as the `if` keyword.
    const if_line_start = line_index.line_start(if_start);
    const if_column = if_start - if_line_start;

    // Insert newline before `else`
    const ws_start = skip_whitespace_back(source, else_start);

    var indent_buf: std.ArrayListUnmanaged(u8) = .{};
    try indent_buf.append(allocator, '\n');
    for (0..if_column)
        |_|
    {
        try indent_buf.append(allocator, ' ');
    }
    const indent_text = try indent_buf.toOwnedSlice(allocator);
    try edits.append(
        allocator,
        .{
            .start_byte = ws_start,
            .end_byte = else_start,
            .new_text = indent_text,
        },
    );
}

/// Break binary expressions across multiple lines
fn break_binary_expression(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    node_index: Ast.Node.Index,
    line: LongLine,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const main_tokens = ast.nodes.items(.main_token);
    const token_starts = ast.tokens.items(.start);

    // Only process if this is a "top-level" binary expression in a chain
    // (i.e., its parent is not also a binary op on the same line)
    // We find this by checking if we're the rightmost/outermost operator
    const op_token = main_tokens[@intFromEnum(node_index)];
    const op_line = line_index.line_of(token_starts[op_token]);

    // Skip if not on the target line
    if (op_line != line.line_number)
    {
        return;
    }

    // Get indentation from line start
    const base_indent = get_line_indent(source, line.line_start);

    // Collect all binary operators in this expression chain that are on the
    // same line
    var op_positions: std.ArrayListUnmanaged(usize) = .{};
    defer op_positions.deinit(allocator);

    // Walk the binary expression tree to collect all operators on this line
    try collect_binary_ops_on_line(
        allocator,
        ast,
        node_index,
        line.line_number,
        &op_positions,
        line_index,
    );

    // Sort positions (they might be out of order due to tree structure)
    std.mem.sort(usize, op_positions.items, {}, std.sort.asc(usize));

    // Remove duplicates
    var unique_positions: std.ArrayListUnmanaged(usize) = .{};
    defer unique_positions.deinit(allocator);

    var last_pos: ?usize = null;
    for (op_positions.items)
        |pos|
    {
        if (
            last_pos == null
            or pos != last_pos.?
        )
        {
            try unique_positions.append(allocator, pos);
            last_pos = pos;
        }
    }

    // Need at least 2 operators to break a chain
    if (unique_positions.items.len <= 1)
    {
        return;
    }

    // Determine if the expression is already wrapped in parentheses.
    // When wrapped, we break before ALL operators (including the first)
    // since the paren already provides visual grouping.
    const first_tok = ast.firstToken(node_index);
    const wrapped_in_parens = (
        first_tok > 0
        and ast.tokens.items(.tag)[first_tok - 1] == .l_paren
    );

    if (!wrapped_in_parens)
    {
        // Wrap the entire expression in parens and break at ALL
        // operators so the result looks like:
        //     const x = (
        //         a
        //         + b
        //         - c
        //     );
        const first_byte = token_starts[first_tok];
        const last_tok = ast.lastToken(node_index);
        const last_tok_start = token_starts[last_tok];
        const last_tok_slice = ast.tokenSlice(last_tok);
        const last_tok_end = last_tok_start + last_tok_slice.len;

        // Opening paren + newline + indent before first operand
        const open_text = try std.fmt.allocPrint(
            allocator,
            "(\n{s}    ",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = first_byte,
                .end_byte = first_byte,
                .new_text = open_text,
            },
        );

        // Break before each operator
        for (unique_positions.items)
            |op_start|
        {
            const ws_start = skip_whitespace_back(
                source,
                op_start,
            );
            const indent_text = try std.fmt.allocPrint(
                allocator,
                "\n{s}    ",
                .{base_indent},
            );
            try edits.append(
                allocator,
                .{
                    .start_byte = ws_start,
                    .end_byte = op_start,
                    .new_text = indent_text,
                },
            );
        }

        // Closing paren after last operand
        const close_text = try std.fmt.allocPrint(
            allocator,
            "\n{s})",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = last_tok_end,
                .end_byte = last_tok_end,
                .new_text = close_text,
            },
        );
    }
    else
    {
        // Already wrapped — break before ALL operators (including
        // the first) since the paren provides visual grouping.
        for (unique_positions.items)
            |op_start|
        {
            const ws_start = skip_whitespace_back(
                source,
                op_start,
            );
            const indent_text = try std.fmt.allocPrint(
                allocator,
                "\n{s}    ",
                .{base_indent},
            );
            try edits.append(
                allocator,
                .{
                    .start_byte = ws_start,
                    .end_byte = op_start,
                    .new_text = indent_text,
                },
            );
        }
    }
}

/// Recursively collect byte positions of binary operators on the given line
fn collect_binary_ops_on_line(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    node_index: Ast.Node.Index,
    target_line: usize,
    positions: *std.ArrayListUnmanaged(usize),
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const tags = ast.nodes.items(.tag);
    const main_tokens = ast.nodes.items(.main_token);
    const node_data = ast.nodes.items(.data);
    const token_starts = ast.tokens.items(.start);

    const tag = tags[@intFromEnum(node_index)];
    if (!is_binary_op_tag(tag))
    {
        return;
    }

    const op_token = main_tokens[@intFromEnum(node_index)];

    if (line_index.line_of(token_starts[op_token]) == target_line)
    {
        try positions.append(allocator, token_starts[op_token]);
    }

    // Recurse into left and right children
    const data = node_data[@intFromEnum(node_index)];
    const lhs: Ast.Node.Index = data.node_and_node[0];
    const rhs: Ast.Node.Index = data.node_and_node[1];

    if (@intFromEnum(lhs) != 0)
    {
        try collect_binary_ops_on_line(
            allocator,
            ast,
            lhs,
            target_line,
            positions,
            line_index,
        );
    }
    if (@intFromEnum(rhs) != 0)
    {
        try collect_binary_ops_on_line(
            allocator,
            ast,
            rhs,
            target_line,
            positions,
            line_index,
        );
    }
}

/// Break a condition expression hierarchically with proper indentation
fn break_condition_hierarchically(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    lparen_tok: Ast.TokenIndex,
    rparen_tok: Ast.TokenIndex,
    base_indent: []const u8,
) std.mem.Allocator.Error!void
{
    const token_tags = ast.tokens.items(.tag);
    const token_starts = ast.tokens.items(.start);

    const lparen_start = token_starts[lparen_tok];
    const rparen_start = token_starts[rparen_tok];

    // First, insert newline after opening paren
    const lparen_end = lparen_start + 1;
    const ws_after_lparen = skip_whitespace_fwd(source, lparen_end);

    const first_indent = try std.fmt.allocPrint(
        allocator,
        "\n{s}    ",
        .{base_indent},
    );
    try edits.append(
        allocator,
        .{
            .start_byte = lparen_end,
            .end_byte = ws_after_lparen,
            .new_text = first_indent,
        },
    );

    // Find all binary operators and nested parens at each depth level
    // depth 0 = inside the if(), depth 1 = inside first nested (), etc.
    var tok = lparen_tok + 1;
    var depth: usize = 0;

    while (tok < rparen_tok)
    {
        const tag = token_tags[tok];
        const tok_start = token_starts[tok];

        if (tag == .l_paren)
        {
            depth += 1;

            // Only break grouping parens (preceded by and/or), not
            // function call parens (preceded by identifier/rparen/etc).
            const is_grouping_paren = tok > 0
                and (token_tags[tok - 1] == .keyword_and
                or token_tags[tok - 1] == .keyword_or);
            if (is_grouping_paren)
            {
                const paren_end = tok_start + 1;
                const ws_after = skip_whitespace_fwd(
                    source,
                    paren_end,
                );

                if (
                    tok + 1 < ast.tokens.len
                    and token_tags[tok + 1] != .r_paren
                )
                {
                    const nested_indent = try alloc_indent(
                        allocator,
                        base_indent,
                        depth + 1,
                    );
                    try edits.append(
                        allocator,
                        .{
                            .start_byte = paren_end,
                            .end_byte = ws_after,
                            .new_text = nested_indent,
                        },
                    );
                }
            }
        }
        else if (tag == .r_paren)
        {
            if (depth > 0)
            {
                // Check if this rparen matches a grouping lparen
                // by looking up the matching lparen. Walk backwards
                // tracking depth to find the corresponding lparen.
                const is_grouping_rparen = blk: {
                    var inner_depth: usize = 0;
                    var scan = tok;
                    while (scan > lparen_tok)
                    {
                        scan -= 1;
                        const scan_tag = token_tags[scan];
                        if (scan_tag == .r_paren)
                        {
                            inner_depth += 1;
                        }
                        else if (scan_tag == .l_paren)
                        {
                            if (inner_depth == 0)
                            {
                                // Found matching lparen
                                break :blk scan > 0
                                    and (token_tags[scan - 1]
                                    == .keyword_and
                                    or token_tags[scan - 1]
                                    == .keyword_or);
                            }
                            inner_depth -= 1;
                        }
                    }
                    break :blk false;
                };
                if (is_grouping_rparen)
                {
                    const ws_before = skip_whitespace_back(
                        source,
                        tok_start,
                    );
                    const close_indent = try alloc_indent(
                        allocator,
                        base_indent,
                        depth,
                    );
                    try edits.append(
                        allocator,
                        .{
                            .start_byte = ws_before,
                            .end_byte = tok_start,
                            .new_text = close_indent,
                        },
                    );
                }

                depth -= 1;
            }
        }
        else if (
            tag == .keyword_and
            or tag == .keyword_or
        )
        {
            // Binary operator - add newline before it
            // Same indentation as the first operand at this depth level
            const ws_before = skip_whitespace_back(source, tok_start);

            const op_indent = try alloc_indent(
                allocator,
                base_indent,
                depth + 1,
            );
            try edits.append(
                allocator,
                .{
                    .start_byte = ws_before,
                    .end_byte = tok_start,
                    .new_text = op_indent,
                },
            );
        }

        tok += 1;
    }

    // Finally, insert newline before closing paren
    const ws_before_rparen = skip_whitespace_back(source, rparen_start);

    const close_indent = try std.fmt.allocPrint(
        allocator,
        "\n{s}",
        .{base_indent},
    );
    try edits.append(
        allocator,
        .{
            .start_byte = ws_before_rparen,
            .end_byte = rparen_start,
            .new_text = close_indent,
        },
    );
}

/// Allocate an indentation string with the given base plus extra levels
fn alloc_indent(
    allocator: std.mem.Allocator,
    base_indent: []const u8,
    levels: usize,
) std.mem.Allocator.Error![]u8
{
    var indent_buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer indent_buf.deinit(allocator);

    try indent_buf.append(allocator, '\n');
    try indent_buf.appendSlice(allocator, base_indent);
    for (0..levels)
        |_|
    {
        try indent_buf.appendSlice(allocator, "    ");
    }

    return indent_buf.toOwnedSlice(allocator);
}

/// Break grouped expression (parenthesized expression) when it contains
/// complex content
fn break_grouped_expression(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    condition_ranges: []const ConditionRange,
    grouped_expr_ranges: []const GroupedExprRange,
    node_index: Ast.Node.Index,
    _: LongLine,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const main_tokens = ast.nodes.items(.main_token);
    const node_data = ast.nodes.items(.data);
    const tags = ast.nodes.items(.tag);
    const token_starts = ast.tokens.items(.start);

    // grouped_expression main token is the lparen
    const lparen_tok = main_tokens[@intFromEnum(node_index)];
    const lparen_start = token_starts[lparen_tok];

    // Get the base line indentation
    const base_indent = get_line_indent(
        source,
        line_index.line_start(lparen_start),
    );

    // Count how many grouped_expression nodes contain this one (for nesting
    // depth)
    const nesting_depth = count_containing_grouped_expressions(
        grouped_expr_ranges,
        lparen_start,
    );

    // Get the inner expression
    const data = node_data[@intFromEnum(node_index)];
    const inner_node: Ast.Node.Index = data.node_and_token[0];
    const inner_tag = tags[@intFromEnum(inner_node)];

    // Only break if inner expression is complex (if, while, binary op, etc.)
    const is_complex = switch (inner_tag) {
        .@"if",
        .if_simple,
        .@"while",
        .while_simple,
        .while_cont,
        .@"for",
        .for_simple,
        .bool_and,
        .bool_or,
        .@"switch",
        .switch_comma,
        => true,
        else => is_arithmetic_binary_op_tag(inner_tag),
    };

    if (!is_complex)
    {
        return;
    }

    // For arithmetic inner expressions, only break if the closing
    // paren lands past the line-length limit.  Short sub-expressions
    // like (rbrace_start - lbrace_start) shouldn't be broken just
    // because they sit on a long line.
    if (is_arithmetic_binary_op_tag(inner_tag))
    {
        const rparen_tok_arith: Ast.TokenIndex = (
            data.node_and_token[1]
        );
        const rparen_col = (
            token_starts[rparen_tok_arith]
            - line_index.line_start(
                token_starts[rparen_tok_arith],
            )
        );
        if (rparen_col < MAX_LINE_LENGTH)
        {
            return;
        }
    }

    // Skip if this grouped expression is inside an if/while condition with
    // boolean operators - those are handled by
    // collect_boolean_condition_edits
    if (
        is_position_inside_boolean_condition(
            condition_ranges,
            ast.tokens.items(.start)[lparen_tok],
            true,
        )
    )
    {
        return;
    }

    // Find the closing paren
    const rparen_tok: Ast.TokenIndex = data.node_and_token[1];

    const rparen_start = token_starts[rparen_tok];
    const already_multiline = !line_index.same_line(
        lparen_start,
        rparen_start,
    );

    if (already_multiline)
    {
        // Expression is already multiline (e.g. a prior pass broke
        // an inner function call).  If the first line is within the
        // limit, nothing to do.
        const grp_line_start = line_index.line_start(lparen_start);
        const grp_line_len = compute_line_length(
            source,
            grp_line_start,
        );
        if (grp_line_len <= MAX_LINE_LENGTH)
        {
            return;
        }

        // First line is still too long.  Collapse the inner content
        // to a single line (joining newlines→spaces, dropping
        // trailing commas before ')') and re-wrap properly.
        var collapsed: std.ArrayListUnmanaged(u8) = .{};
        defer collapsed.deinit(allocator);

        var last_end: ?usize = null;
        var tok = lparen_tok + 1;
        while (tok < rparen_tok)
        {
            const tok_tag = ast.tokens.items(.tag)[tok];

            // Skip trailing commas: comma whose next token is )
            if (
                tok_tag == .comma
                and tok + 1 < ast.tokens.len
                and ast.tokens.items(.tag)[
                    tok + 1
                ] == .r_paren
            )
            {
                tok += 1;
                continue;
            }

            // Inter-token spacing: use original source but collapse
            // any newline run to a single space.  Omit the space
            // when the previous token is ( or current is ) to avoid
            // producing "fn( arg )" style spacing.
            if (last_end)
                |prev_end|
            {
                const this_start = token_starts[tok];
                if (this_start > prev_end)
                {
                    const between = source[prev_end..this_start];
                    var has_nl = false;
                    for (between)
                        |bc|
                    {
                        if (bc == '\n')
                        {
                            has_nl = true;
                            break;
                        }
                    }
                    if (has_nl)
                    {
                        // Don't add a space right after ( or
                        // right before )
                        const after_open = (
                            collapsed.items.len > 0
                            and collapsed.items[
                                collapsed.items.len - 1
                            ] == '('
                        );
                        const before_close = (
                            tok_tag == .r_paren
                        );
                        if (
                            !after_open
                            and !before_close
                        )
                        {
                            try collapsed.append(
                                allocator,
                                ' ',
                            );
                        }
                    }
                    else
                    {
                        try collapsed.appendSlice(
                            allocator,
                            between,
                        );
                    }
                }
            }

            const slice = ast.tokenSlice(tok);
            try collapsed.appendSlice(allocator, slice);
            last_end = token_starts[tok] + slice.len;
            tok += 1;
        }

        // Build replacement: (\n{indent}collapsed\n{base_indent})
        const open_indent = try alloc_indent(
            allocator,
            base_indent,
            nesting_depth + 1,
        );
        defer allocator.free(open_indent);
        const close_indent = try alloc_indent(
            allocator,
            base_indent,
            nesting_depth,
        );
        defer allocator.free(close_indent);
        const replacement = try std.fmt.allocPrint(
            allocator,
            "({s}{s}{s})",
            .{ open_indent, collapsed.items, close_indent },
        );

        try edits.append(
            allocator,
            .{
                .start_byte = lparen_start,
                .end_byte = rparen_start + 1,
                .new_text = replacement,
            },
        );
        return;
    }

    // Single-line case: insert newline after ( and before )
    const lparen_end = lparen_start + 1;
    const ws_after = skip_whitespace_fwd(source, lparen_end);

    // Content inside gets base + (nesting_depth + 1) levels
    const open_indent = try alloc_indent(
        allocator,
        base_indent,
        nesting_depth + 1,
    );
    try edits.append(
        allocator,
        .{
            .start_byte = lparen_end,
            .end_byte = ws_after,
            .new_text = open_indent,
        },
    );

    // Insert newline before closing paren - at base + nesting_depth level
    const ws_before = skip_whitespace_back(source, rparen_start);

    const close_indent = try alloc_indent(
        allocator,
        base_indent,
        nesting_depth,
    );
    try edits.append(
        allocator,
        .{
            .start_byte = ws_before,
            .end_byte = rparen_start,
            .new_text = close_indent,
        },
    );
}

/// Count how many grouped_expression nodes contain the given node
/// Count how many pre-computed grouped-expression ranges strictly contain
/// the byte position `target_start`.  The ranges slice is sorted by start
/// offset, so we can skip past ranges that start at or after the target.
fn count_containing_grouped_expressions(
    ranges: []const GroupedExprRange,
    target_start: usize,
) usize
{
    var count: usize = 0;
    for (ranges)
        |r|
    {
        // Ranges are sorted by start; once a range starts at or past the
        // target there can be no further containing ranges.
        if (r.start >= target_start)
        {
            break;
        }
        if (
            target_start > r.start
            and target_start < r.end
        )
        {
            count += 1;
        }
    }
    return count;
}

/// Collect edits to break long if-else expression assignments.
/// Transforms: `const x = if (cond) expr_a else expr_b;`
/// Into:
///     const x = (
///         if (cond) expr_a
///         else expr_b
///     );
fn collect_if_else_expr_edits(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    long_lines: []const LongLine,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const tags = ast.nodes.items(.tag);
    const main_tokens = ast.nodes.items(.main_token);
    const token_starts = ast.tokens.items(.start);
    for (long_lines)
        |line|
    {
        for (0..ast.nodes.len)
            |i|
        {
            const node_index: Ast.Node.Index = @enumFromInt(i);
            const tag = tags[@intFromEnum(node_index)];

            // Only full if (has else clause), not if_simple
            if (tag != .@"if")
            {
                continue;
            }

            const if_token = main_tokens[@intFromEnum(node_index)];
            const if_start = token_starts[if_token];

            // Must be on the target line
            if (
                if_start < line.line_start
                or if_start >= line.line_end
            )
            {
                continue;
            }

            const if_info = ast.fullIf(node_index) orelse continue;

            // Must have else clause (expression form)
            const else_expr = if_info.ast.else_expr.unwrap() orelse continue;

            // Skip if then/else branches are blocks
            // (those are statement if-else, not expression)
            const then_expr = if_info.ast.then_expr;
            const then_tag = tags[@intFromEnum(then_expr)];
            const else_tag = tags[@intFromEnum(else_expr)];

            if (
                then_tag == .block
                or then_tag == .block_two
                or then_tag == .block_two_semicolon
                or then_tag == .block_semicolon
            )
            {
                continue;
            }

            if (
                else_tag == .block
                or else_tag == .block_two
                or else_tag == .block_two_semicolon
                or else_tag == .block_semicolon
            )
            {
                continue;
            }

            // Skip if already multi-line
            const then_first = ast.firstToken(then_expr);
            const else_last = ast.lastToken(else_expr);
            if (
                !line_index.same_line(
                    token_starts[then_first],
                    token_starts[else_last],
                )
            )
            {
                continue;
            }

            // Skip if already parenthesized: check for
            // `= (` before the `if` keyword
            if (if_token >= 2)
            {
                var check = if_start;
                // Skip whitespace before `if`
                while (
                    check > 0
                    and (
                        source[check - 1] == ' '
                        or source[check - 1] == '\t'
                        or source[check - 1] == '\n'
                    )
                )
                {
                    check -= 1;
                }
                // Check for `(`
                if (
                    check > 0
                    and source[check - 1] == '('
                )
                {
                    continue;
                }
            }

            // Get base indent
            const base_indent = get_line_indent(
                source,
                line.line_start,
            );

            // Edit 1: Before `if` keyword, replace
            // preceding whitespace with ` (\n{indent}    `
            var ws_before_if = if_start;
            while (
                ws_before_if > line.line_start
                and (
                    source[ws_before_if - 1] == ' '
                    or source[ws_before_if - 1] == '\t'
                )
            )
            {
                ws_before_if -= 1;
            }

            const open_paren_text = try std.fmt.allocPrint(
                allocator,
                " (\n{s}    ",
                .{base_indent},
            );
            try edits.append(
                allocator,
                .{
                    .start_byte = ws_before_if,
                    .end_byte = if_start,
                    .new_text = open_paren_text,
                },
            );

            // Edit 2: Before `else` keyword, replace
            // preceding whitespace with newline+indent
            // Walk the else-if chain to find the
            // outermost else token
            var cur_else_expr = else_expr;
            var cur_else_token = if_info.else_token;
            while (true)
            {
                const else_kw_start = token_starts[
                    cur_else_token
                ];

                const ws_before_else = skip_whitespace_back(
                    source,
                    else_kw_start,
                );

                const else_indent = try std.fmt.allocPrint(
                    allocator,
                    "\n{s}    ",
                    .{base_indent},
                );
                try edits.append(
                    allocator,
                    .{
                        .start_byte = ws_before_else,
                        .end_byte = else_kw_start,
                        .new_text = else_indent,
                    },
                );

                // If the else branch is another if,
                // continue the chain
                const cur_else_tag = tags[
                    @intFromEnum(cur_else_expr)
                ];
                if (cur_else_tag == .@"if")
                {
                    const nested = ast.fullIf(
                        cur_else_expr,
                    ) orelse break;
                    const nested_else = nested
                        .ast
                        .else_expr
                        .unwrap() orelse break;
                    cur_else_token = nested.else_token;
                    cur_else_expr = nested_else;
                }
                else
                {
                    break;
                }
            }

            // Edit 3: Find the `;` after the final
            // else_expr and replace whitespace+`;` with
            // `\n{base_indent});`
            const final_last = ast.lastToken(
                cur_else_expr,
            );
            const final_last_end = token_starts[
                final_last
            ] + ast.tokenSlice(final_last).len;

            // Scan for the semicolon after the last token
            var semi_pos = final_last_end;
            while (
                semi_pos < source.len
                and source[semi_pos] != ';'
            )
            {
                semi_pos += 1;
            }

            if (
                semi_pos < source.len
                and source[semi_pos] == ';'
            )
            {
                // Find start of whitespace before `;`
                var ws_before_semi = semi_pos;
                while (
                    ws_before_semi > final_last_end
                    and (
                        source[ws_before_semi - 1] == ' '
                        or source[ws_before_semi - 1] == '\t'
                    )
                )
                {
                    ws_before_semi -= 1;
                }

                const close_paren_text =
                    try std.fmt.allocPrint(
                        allocator,
                        "\n{s});",
                        .{base_indent},
                    );
                try edits.append(
                    allocator,
                    .{
                        .start_byte = ws_before_semi,
                        .end_byte = semi_pos + 1,
                        .new_text = close_paren_text,
                    },
                );
            }

            // Only break one if-else per line
            break;
        }
    }
}

/// Break function parameters across multiple lines (ALWAYS - not just for
/// long lines)
fn break_function_params(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    node_index: Ast.Node.Index,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    // Get the function prototype info
    var buf: [1]Ast.Node.Index = undefined;
    const fn_proto = ast.fullFnProto(&buf, node_index) orelse return;

    // Get base indentation from the fn keyword
    const fn_token = fn_proto.ast.fn_token;
    const base_indent = get_line_indent(
        source,
        line_index.line_start(ast.tokens.items(.start)[fn_token]),
    );

    // Find the opening paren
    var lparen_tok = fn_token + 1;
    while (
        lparen_tok < ast.tokens.len and ast.tokens.items(
            .tag,
        )[lparen_tok] != .l_paren
    )
    {
        lparen_tok += 1;
    }
    if (lparen_tok >= ast.tokens.len)
    {
        return;
    }

    // Find the closing paren by scanning for matching paren
    const rparen_tok = find_matching_delimiter(
        ast,
        lparen_tok,
        .l_paren,
        .r_paren,
    ) orelse return;

    const token_starts = ast.tokens.items(.start);
    const lparen_start = token_starts[lparen_tok];
    const rparen_start = token_starts[rparen_tok];

    // Check if already multi-line (lparen and rparen on different lines)
    if (!line_index.same_line(lparen_start, rparen_start))
    {
        return;
    } // Already multi-line

    // Find all commas between the parens to identify parameter boundaries
    var comma_positions = try collect_depth0_commas(
        allocator,
        ast,
        lparen_tok,
        rparen_tok,
    );
    defer comma_positions.deinit(allocator);

    // Check if there are any parameters (anything between lparen and rparen
    // besides whitespace)
    const has_params = comma_positions.items.len > 0 or blk: {
        // Check if there's content between ( and )
        var check_tok = lparen_tok + 1;
        while (check_tok < rparen_tok)
        {
            const tag = ast.tokens.items(.tag)[check_tok];
            if (tag != .invalid)
            {
                break :blk true;
            }
            check_tok += 1;
        }
        break :blk false;
    };

    if (has_params)
    {
        // Function has parameters - break after ( and before each param
        const lparen_end = lparen_start + 1;
        // Skip any whitespace after lparen
        const ws_after_lparen = skip_whitespace_fwd(source, lparen_end);

        const first_param_indent = try std.fmt.allocPrint(
            allocator,
            "\n{s}    ",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = lparen_end,
                .end_byte = ws_after_lparen,
                .new_text = first_param_indent,
            },
        );

        // Insert newline after each comma
        for (comma_positions.items)
            |comma_pos|
        {
            const comma_end = comma_pos + 1;
            // Skip whitespace after comma
            const ws_end = skip_whitespace_fwd(source, comma_end);

            const param_indent = try std.fmt.allocPrint(
                allocator,
                "\n{s}    ",
                .{base_indent},
            );
            try edits.append(
                allocator,
                .{
                    .start_byte = comma_end,
                    .end_byte = ws_end,
                    .new_text = param_indent,
                },
            );
        }

        // Insert trailing comma and newline before closing paren
        const ws_before_rparen = skip_whitespace_back(source, rparen_start);

        const rparen_indent = try std.fmt.allocPrint(
            allocator,
            ",\n{s}",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = ws_before_rparen,
                .end_byte = rparen_start,
                .new_text = rparen_indent,
            },
        );
    }
    else
    {
        // Empty parameter list: fn foo() -> fn foo(\n)
        const lparen_end = lparen_start + 1;
        const newline_indent = try std.fmt.allocPrint(
            allocator,
            "\n{s}",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = lparen_end,
                .end_byte = rparen_start,
                .new_text = newline_indent,
            },
        );
    }
}

/// Break function call arguments across multiple lines
fn break_function_call(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    node_index: Ast.Node.Index,
    line: LongLine,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const main_tokens = ast.nodes.items(.main_token);
    const token_starts = ast.tokens.items(.start);

    // The main token of a call is the lparen
    const lparen_tok = main_tokens[@intFromEnum(node_index)];
    if (ast.tokens.items(.tag)[lparen_tok] != .l_paren)
    {
        return;
    }

    // Get the location for indentation
    const lparen_byte = token_starts[lparen_tok];
    const lparen_line_start = line_index.line_start(lparen_byte);
    const lparen_line = line_index.line_of(lparen_byte);
    const base_indent = get_line_indent(source, lparen_line_start);

    // Find the closing paren
    const rparen_tok = find_matching_delimiter(
        ast,
        lparen_tok,
        .l_paren,
        .r_paren,
    ) orelse return;

    const lparen_start = lparen_byte;
    const rparen_start = token_starts[rparen_tok];

    const already_multiline = !line_index.same_line(
        lparen_byte,
        rparen_start,
    );

    if (already_multiline)
    {
        // Already multi-line: only re-break if the opening line is still too
        // long
        const opening_line_len = compute_line_length(
            source,
            lparen_line_start,
        );
        if (opening_line_len <= MAX_LINE_LENGTH)
        {
            return;
        }

        // Check if content right after '(' is already on the next line
        const lparen_end = lparen_start + 1;
        const after_lparen = skip_whitespace_fwd(source, lparen_end);
        if (
            after_lparen < source.len
            and source[after_lparen] == '\n'
        )
        {
            return;
        }
    }
    else
    {
        // Single-line: skip if the whole line (not just the call
        // span) actually fits. This accounts for characters after
        // the closing paren such as `;`.
        if (line.length <= MAX_LINE_LENGTH)
        {
            return;
        }
    }

    // Find commas at depth 0 (only on the first line for multi-line, all for
    // single-line)
    var comma_positions = try collect_depth0_commas(
        allocator,
        ast,
        lparen_tok,
        rparen_tok,
    );
    defer comma_positions.deinit(allocator);

    // If there are no commas and no content between parens, nothing to break
    if (comma_positions.items.len == 0)
    {
        // Check if there's actual content between the parens
        var has_content = false;
        var check_pos = lparen_start + 1;
        while (check_pos < rparen_start)
        {
            if (
                source[check_pos] != ' '
                and source[check_pos] != '\t'
                and source[check_pos] != '\n'
            )
            {
                has_content = true;
                break;
            }
            check_pos += 1;
        }
        if (!has_content)
        {
            return;
        }
    }

    // Insert newline after opening paren (replacing any whitespace before the
    // first token)
    const lparen_end = lparen_start + 1;

    // Find the start of the first argument token after '('
    const first_arg_start = skip_whitespace_fwd(source, lparen_end);

    // Only insert if there isn't already a newline
    if (
        first_arg_start >= source.len
        or source[first_arg_start] != '\n'
    )
    {
        const first_arg_indent = try std.fmt.allocPrint(
            allocator,
            "\n{s}    ",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = lparen_end,
                .end_byte = first_arg_start,
                .new_text = first_arg_indent,
            },
        );
    }

    // Insert newline after each comma (only for commas on the opening line in
    // multi-line case)
    for (comma_positions.items)
        |comma_pos|
    {
        // For multi-line constructs, only break commas that are on the same
        // line as the lparen
        if (already_multiline)
        {
            if (line_index.line_of(comma_pos) != lparen_line)
            {
                continue;
            }
        }

        const comma_end = comma_pos + 1;
        const ws_end = skip_whitespace_fwd(source, comma_end);
        // If there's already a newline after the comma, skip
        if (
            ws_end < source.len
            and source[ws_end] == '\n'
        )
        {
            continue;
        }

        const arg_indent = try std.fmt.allocPrint(
            allocator,
            "\n{s}    ",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = comma_end,
                .end_byte = ws_end,
                .new_text = arg_indent,
            },
        );
    }

    if (already_multiline)
    {
        // Re-indent all interior lines between '(' and ')' by adding 4 spaces
        try reindent_interior_lines(
            allocator,
            source,
            edits,
            lparen_end,
            rparen_start,
            "    ",
        );

        // Put closing ')' on its own line with trailing comma and re-indent
        const ws_before_rparen = skip_whitespace_back(source, rparen_start);

        // Check if there's already a trailing comma
        var need_comma = false;
        if (
            ws_before_rparen > 0
            and source[ws_before_rparen - 1] == '\n'
        )
        {
            // Look at the non-whitespace character before the newline
            const check = skip_whitespace_back(source, ws_before_rparen - 1);
            if (
                check > 0
                and source[check - 1] != ','
            )
            {
                need_comma = true;
            }
        }
        else
        {
            if (
                ws_before_rparen > 0
                and source[ws_before_rparen - 1] != ','
            )
            {
                need_comma = true;
            }
        }

        const comma_str: []const u8 = if (need_comma) "," else "";

        if (
            ws_before_rparen > 0
            and source[ws_before_rparen - 1] == '\n'
        )
        {
            // Already on its own line, re-indent
            const rparen_indent = try std.fmt.allocPrint(
                allocator,
                "{s}{s}\n{s}",
                .{ comma_str, base_indent, base_indent },
            );
            try edits.append(
                allocator,
                .{
                    .start_byte = ws_before_rparen,
                    .end_byte = rparen_start,
                    .new_text = rparen_indent,
                },
            );
        }
        else
        {
            const rparen_indent = try std.fmt.allocPrint(
                allocator,
                "{s}\n{s}",
                .{ comma_str, base_indent },
            );
            try edits.append(
                allocator,
                .{
                    .start_byte = ws_before_rparen,
                    .end_byte = rparen_start,
                    .new_text = rparen_indent,
                },
            );
        }
    }
    else
    {
        // Single-line: insert newline before closing paren with trailing
        // comma
        const ws_before_rparen = skip_whitespace_back(source, rparen_start);

        const rparen_indent = try std.fmt.allocPrint(
            allocator,
            ",\n{s}",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = ws_before_rparen,
                .end_byte = rparen_start,
                .new_text = rparen_indent,
            },
        );
    }
}

/// Break struct initialization across multiple lines
fn break_struct_init(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    node_index: Ast.Node.Index,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const main_tokens = ast.nodes.items(.main_token);
    const token_starts = ast.tokens.items(.start);

    // The main token is the lbrace
    const lbrace_tok = main_tokens[@intFromEnum(node_index)];
    if (ast.tokens.items(.tag)[lbrace_tok] != .l_brace)
    {
        return;
    }

    const lbrace_byte = token_starts[lbrace_tok];
    const lbrace_line_start = line_index.line_start(lbrace_byte);
    const lbrace_line = line_index.line_of(lbrace_byte);
    const base_indent = get_line_indent(source, lbrace_line_start);

    // Find the closing brace
    const rbrace_tok = find_matching_delimiter(
        ast,
        lbrace_tok,
        .l_brace,
        .r_brace,
    ) orelse return;

    const lbrace_start = lbrace_byte;
    const rbrace_start = token_starts[rbrace_tok];

    const already_multiline = !line_index.same_line(
        lbrace_byte,
        rbrace_start,
    );

    if (already_multiline)
    {
        // Already multi-line: only re-break if the opening line is still too
        // long
        const opening_line_len = compute_line_length(
            source,
            lbrace_line_start,
        );
        if (opening_line_len <= MAX_LINE_LENGTH)
        {
            return;
        }

        // Check if content right after '{' is already on the next line
        const lbrace_end = lbrace_start + 1;
        const after_lbrace = skip_whitespace_fwd(source, lbrace_end);
        if (
            after_lbrace < source.len
            and source[after_lbrace] == '\n'
        )
        {
            return;
        }
    }
    else
    {
        // Single-line: check if the full line exceeds the limit
        const line_len = compute_line_length(
            source,
            lbrace_line_start,
        );
        if (line_len <= MAX_LINE_LENGTH)
        {
            return;
        }
    }

    // Find commas at depth 0
    var comma_positions = try collect_depth0_commas(
        allocator,
        ast,
        lbrace_tok,
        rbrace_tok,
    );
    defer comma_positions.deinit(allocator);

    if (comma_positions.items.len == 0)
    {
        return;
    }

    // Insert newline after opening brace (removing any whitespace after {)
    const lbrace_end = lbrace_start + 1;
    const ws_after_lbrace = skip_whitespace_fwd(source, lbrace_end);
    // If there's already a newline, don't insert another one
    if (
        ws_after_lbrace < source.len
        and source[ws_after_lbrace] == '\n'
    )
    {
        // Already broken after opening brace — skip this edit
    }
    else
    {
        const first_field_indent = try std.fmt.allocPrint(
            allocator,
            "\n{s}    ",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = lbrace_end,
                .end_byte = ws_after_lbrace,
                .new_text = first_field_indent,
            },
        );
    }

    // Insert newline after each comma
    for (comma_positions.items)
        |comma_pos|
    {
        // For multi-line constructs, only break commas that are on the same
        // line as the lbrace
        if (already_multiline)
        {
            if (line_index.line_of(comma_pos) != lbrace_line)
            {
                continue;
            }
        }

        const comma_end = comma_pos + 1;
        const ws_end = skip_whitespace_fwd(source, comma_end);
        // If there's already a newline after the comma, skip
        if (
            ws_end < source.len
            and source[ws_end] == '\n'
        )
        {
            continue;
        }

        const field_indent = try std.fmt.allocPrint(
            allocator,
            "\n{s}    ",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = comma_end,
                .end_byte = ws_end,
                .new_text = field_indent,
            },
        );
    }

    if (already_multiline)
    {
        // Re-indent all interior lines between '{' and '}' by adding 4 spaces
        try reindent_interior_lines(
            allocator,
            source,
            edits,
            lbrace_start + 1,
            rbrace_start,
            "    ",
        );

        // Put closing '}' on its own line and re-indent
        const ws_before_rbrace = skip_whitespace_back(source, rbrace_start);

        if (
            ws_before_rbrace > 0
            and source[ws_before_rbrace - 1] == '\n'
        )
        {
            // Already on its own line, re-indent to base + 4
            const rbrace_indent = try std.fmt.allocPrint(
                allocator,
                "{s}    ",
                .{base_indent},
            );
            try edits.append(
                allocator,
                .{
                    .start_byte = ws_before_rbrace,
                    .end_byte = rbrace_start,
                    .new_text = rbrace_indent,
                },
            );
        }
        else
        {
            const rbrace_indent = try std.fmt.allocPrint(
                allocator,
                "\n{s}",
                .{base_indent},
            );
            try edits.append(
                allocator,
                .{
                    .start_byte = ws_before_rbrace,
                    .end_byte = rbrace_start,
                    .new_text = rbrace_indent,
                },
            );
        }
    }
    else
    {
        // Single-line: insert newline before closing brace with trailing
        // comma
        const ws_before_rbrace = skip_whitespace_back(source, rbrace_start);

        const rbrace_indent = try std.fmt.allocPrint(
            allocator,
            ",\n{s}",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = ws_before_rbrace,
                .end_byte = rbrace_start,
                .new_text = rbrace_indent,
            },
        );
    }
}

fn process_if_statement(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    node_index: Ast.Node.Index,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const tags = ast.nodes.items(.tag);

    // Get the full if statement info
    const if_info = ast.fullIf(node_index) orelse return;

    // Check if this is block form (has braces) vs expression form
    // Expression form: const x = if (cond) a else b;
    // Block form: if (cond) { ... }
    const then_node = if_info.ast.then_expr;
    const then_tag = tags[@intFromEnum(then_node)];

    // Check if then_expr is a block
    if (!is_block_tag(then_tag))
    {
        // Only wrap statement-form ifs: if_simple has no else, always a
        // statement
        const tag = tags[@intFromEnum(node_index)];
        if (tag != .if_simple)
        {
            return;
        }

        // Get the base indentation from the if keyword
        const if_token = ast.nodes.items(
            .main_token,
        )[@intFromEnum(node_index)];
        const base_indent = get_line_indent(
            source,
            line_index.line_start(ast.tokens.items(.start)[if_token]),
        );

        // Find the rparen: token before the then_expr's first token
        const then_first_tok = ast.firstToken(then_node);
        const then_last_tok = ast.lastToken(then_node);

        // The rparen is the token just before the then body
        const rparen_tok = then_first_tok - 1;
        const rparen_end = ast.tokens.items(.start)[rparen_tok] + 1;
        const then_start = ast.tokens.items(.start)[then_first_tok];

        // The semicolon follows the then_expr's last token
        const semi_tok = then_last_tok + 1;
        const semi_start = ast.tokens.items(.start)[semi_tok];
        const semi_end = semi_start + 1;

        // Check if already wrapped (then_expr already starts on a new line
        // with brace)
        // If there's already a newline between rparen and then_expr, skip
        var already_has_brace = false;
        for (source[rparen_end..then_start])
            |c|
        {
            if (c == '{')
            {
                already_has_brace = true;
                break;
            }
        }
        if (already_has_brace)
        {
            return;
        }

        // Replace whitespace between ) and then_expr with
        // "\n{base_indent}{\n{base_indent} "
        const open_text = try std.fmt.allocPrint(
            allocator,
            "\n{s}{{\n{s}    ",
            .{ base_indent, base_indent },
        );
        try edits.append(
            allocator,
            .{
                .start_byte = rparen_end,
                .end_byte = then_start,
                .new_text = open_text,
            },
        );

        // Replace the semicolon with ";\n{base_indent}}"
        const close_text = try std.fmt.allocPrint(
            allocator,
            ";\n{s}}}",
            .{base_indent},
        );
        try edits.append(
            allocator,
            .{
                .start_byte = semi_start,
                .end_byte = semi_end,
                .new_text = close_text,
            },
        );

        return;
    }

    // Get the base indentation from the if keyword
    const if_token = ast.nodes.items(.main_token)[@intFromEnum(node_index)];
    const base_indent = get_line_indent(
        source,
        line_index.line_start(ast.tokens.items(.start)[if_token]),
    );

    // Process the condition -> opening brace transition
    try process_condition_to_brace(
        allocator,
        ast,
        source,
        edits,
        if_info,
        base_indent,
        line_index,
    );

    // Process else clause if present
    if (if_info.ast.else_expr != .none)
    {
        try process_else_clause(
            allocator,
            ast,
            source,
            edits,
            if_info,
            base_indent,
            line_index,
        );
    }
}

fn emit_capture_placement_edit(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    edits: *std.ArrayListUnmanaged(Edit),
    rparen_tok: Ast.TokenIndex,
    payload_tok: Ast.TokenIndex,
    is_multiline_condition: bool,
    base_indent: []const u8,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const token_starts = ast.tokens.items(.start);
    const rparen_same_line = line_index.same_line(
        token_starts[rparen_tok],
        token_starts[payload_tok],
    );

    if (is_multiline_condition)
    {
        // Multi-line condition: capture should stay on same line as )
        // If capture is NOT on same line as rparen, move it there
        if (!rparen_same_line)
        {
            const pipe_start = ast.tokens.items(
                .start,
            )[payload_tok - 1]; // Opening |
            const rparen_end = ast.tokens.items(.start)[rparen_tok] + 1;

            // Replace whitespace between ) and | with single space
            try edits.append(
                allocator,
                .{
                    .start_byte = rparen_end,
                    .end_byte = pipe_start,
                    .new_text = " ",
                },
            );
        }
    }
    else
    {
        // Single-line condition: capture should be on its own indented
        // line
        if (rparen_same_line)
        {
            const pipe_start = ast.tokens.items(
                .start,
            )[payload_tok - 1]; // Opening |
            const rparen_end = ast.tokens.items(.start)[rparen_tok] + 1;

            const indent_text = try std.fmt.allocPrint(
                allocator,
                "\n{s}    ",
                .{base_indent},
            );

            try edits.append(
                allocator,
                .{
                    .start_byte = rparen_end,
                    .end_byte = pipe_start,
                    .new_text = indent_text,
                },
            );
        }
    }
}

fn emit_else_clause_edits(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    then_rbrace: Ast.TokenIndex,
    else_token: Ast.TokenIndex,
    else_expr: Ast.Node.Index,
    base_indent: []const u8,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const tags = ast.nodes.items(.tag);
    const main_tokens = ast.nodes.items(.main_token);
    const token_starts = ast.tokens.items(.start);

    // Sub-pattern 1: Move } and else to separate lines
    if (
        line_index.same_line(
            token_starts[then_rbrace],
            token_starts[else_token],
        )
    )
    {
        const rbrace_end = token_starts[then_rbrace] + 1;
        const else_start = token_starts[else_token];

        const indent_text = try std.fmt.allocPrint(
            allocator,
            "\n{s}",
            .{base_indent},
        );

        try edits.append(
            allocator,
            .{
                .start_byte = rbrace_end,
                .end_byte = else_start,
                .new_text = indent_text,
            },
        );
    }

    // Sub-pattern 2: Move else { brace to new line
    const else_tag = tags[@intFromEnum(else_expr)];
    if (is_block_tag(else_tag))
    {
        const else_lbrace = main_tokens[@intFromEnum(else_expr)];

        if (
            line_index.same_line(
                token_starts[else_token],
                token_starts[else_lbrace],
            )
        )
        {
            const brace_start = token_starts[else_lbrace];

            const ws_start = skip_whitespace_back(source, brace_start);

            const indent_text = try std.fmt.allocPrint(
                allocator,
                "\n{s}",
                .{base_indent},
            );

            try edits.append(
                allocator,
                .{
                    .start_byte = ws_start,
                    .end_byte = brace_start,
                    .new_text = indent_text,
                },
            );
        }
    }
}

fn process_condition_to_brace(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    if_info: Ast.full.If,
    base_indent: []const u8,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const then_node = if_info.ast.then_expr;
    const main_tokens = ast.nodes.items(.main_token);
    const token_starts = ast.tokens.items(.start);
    const then_lbrace = main_tokens[@intFromEnum(then_node)];

    // Determine if condition spans multiple lines
    // Get the opening paren (token after 'if') and closing paren
    const if_token = main_tokens[@intFromEnum(if_info.ast.cond_expr)];
    // Find the lparen - it's the first lparen after the if keyword
    var lparen_tok = if_token;
    while (
        lparen_tok > 0 and ast.tokens.items(
            .tag,
        )[lparen_tok] != .l_paren
    )
    {
        lparen_tok -= 1;
    }
    const cond_last_tok = ast.lastToken(if_info.ast.cond_expr);
    // The rparen is after the condition
    const rparen_tok = cond_last_tok + 1;

    const is_multiline_condition = !line_index.same_line(
        token_starts[lparen_tok],
        token_starts[rparen_tok],
    );

    // Find where the brace transition should happen
    var transition_end_token: Ast.TokenIndex = undefined;

    if (if_info.payload_token)
        |payload_tok|
    {
        // Has a capture like |value|
        // Find the closing pipe of the capture
        var tok = payload_tok;
        while (ast.tokens.items(.tag)[tok] != .pipe)
        {
            tok += 1;
        }
        transition_end_token = tok;

        // Capture placement depends on condition being single or multi-line
        try emit_capture_placement_edit(
            allocator,
            ast,
            edits,
            rparen_tok,
            payload_tok,
            is_multiline_condition,
            base_indent,
            line_index,
        );
    }
    else
    {
        // No capture - transition is right after condition's closing paren
        transition_end_token = rparen_tok;
    }

    // Check if this is a labeled block - if so, don't move the brace
    // (labeled blocks keep brace on same line as the label)
    if (is_labeled_block(ast, then_lbrace))
    {
        return;
    }

    // Check if opening brace is on same line as transition point
    if (
        line_index.same_line(
            token_starts[transition_end_token],
            token_starts[then_lbrace],
        )
    )
    {
        // Need to insert newline before brace
        const brace_start = token_starts[then_lbrace];

        // Find where whitespace before brace starts
        const ws_start = skip_whitespace_back(source, brace_start);

        const indent_text = try std.fmt.allocPrint(
            allocator,
            "\n{s}",
            .{base_indent},
        );

        try edits.append(
            allocator,
            .{
                .start_byte = ws_start,
                .end_byte = brace_start,
                .new_text = indent_text,
            },
        );
    }
}

fn process_else_clause(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    if_info: Ast.full.If,
    base_indent: []const u8,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const else_token = if_info.else_token;
    const else_expr_opt = if_info.ast.else_expr;
    const else_expr = else_expr_opt.unwrap() orelse return;
    const tags = ast.nodes.items(.tag);
    const main_tokens = ast.nodes.items(.main_token);
    const token_starts = ast.tokens.items(.start);

    // Find the closing brace of the then block
    const then_node = if_info.ast.then_expr;
    const then_rbrace = ast.lastToken(then_node);

    // Check if else is followed by another if (else if chain)
    const else_tag = tags[@intFromEnum(else_expr)];
    if (
        else_tag == .@"if"
        or else_tag == .if_simple
    )
    {
        // For else-if: emit_else_clause_edits handles sub-pattern 1
        // (separate } and else); sub-pattern 2 is a no-op since
        // if nodes are not block tags.
        try emit_else_clause_edits(
            allocator,
            ast,
            source,
            edits,
            then_rbrace,
            else_token,
            else_expr,
            base_indent,
            line_index,
        );
        // This is an else-if, recurse
        try process_if_statement(
            allocator,
            ast,
            source,
            edits,
            else_expr,
            line_index,
        );
    }
    else if (is_block_tag(else_tag))
    {
        // Plain else with block
        // Check for error capture: else |err| {
        // Error captures go on their own indented line (else is like
        // single-line "condition")
        if (if_info.error_token)
            |err_tok|
        {
            // Error capture path: handle } / else separation inline
            // (cannot use helper because error capture needs custom
            // brace placement from capture end, not from else keyword)
            if (
                line_index.same_line(
                    token_starts[then_rbrace],
                    token_starts[else_token],
                )
            )
            {
                const rbrace_end = token_starts[then_rbrace] + 1;
                const else_start = token_starts[else_token];

                const indent_text = try std.fmt.allocPrint(
                    allocator,
                    "\n{s}",
                    .{base_indent},
                );

                try edits.append(
                    allocator,
                    .{
                        .start_byte = rbrace_end,
                        .end_byte = else_start,
                        .new_text = indent_text,
                    },
                );
            }

            // Error capture should be on its own indented line after else
            if (
                line_index.same_line(
                    token_starts[else_token],
                    token_starts[err_tok],
                )
            )
            {
                const else_end = token_starts[else_token] + 4; // "else"
                const pipe_start = token_starts[err_tok - 1]; // Opening |

                const indent_text = try std.fmt.allocPrint(
                    allocator,
                    "\n{s}    ",
                    .{base_indent},
                );

                try edits.append(
                    allocator,
                    .{
                        .start_byte = else_end,
                        .end_byte = pipe_start,
                        .new_text = indent_text,
                    },
                );
            }

            // Find closing pipe of error capture
            var tok = err_tok;
            while (ast.tokens.items(.tag)[tok] != .pipe)
            {
                tok += 1;
            }
            const else_lbrace = main_tokens[@intFromEnum(else_expr)];

            if (
                line_index.same_line(
                    token_starts[tok],
                    token_starts[else_lbrace],
                )
            )
            {
                // Need newline before brace
                const brace_start = token_starts[else_lbrace];
                const ws_start = skip_whitespace_back(source, brace_start);

                const indent_text = try std.fmt.allocPrint(
                    allocator,
                    "\n{s}",
                    .{base_indent},
                );

                try edits.append(
                    allocator,
                    .{
                        .start_byte = ws_start,
                        .end_byte = brace_start,
                        .new_text = indent_text,
                    },
                );
            }
        }
        else
        {
            // No error capture: use helper for both sub-patterns
            try emit_else_clause_edits(
                allocator,
                ast,
                source,
                edits,
                then_rbrace,
                else_token,
                else_expr,
                base_indent,
                line_index,
            );
        }
    }
}

fn process_for_statement(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    node_index: Ast.Node.Index,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const tags = ast.nodes.items(.tag);
    const main_tokens = ast.nodes.items(.main_token);
    const token_starts = ast.tokens.items(.start);

    // Get the full for statement info
    const for_info = ast.fullFor(node_index) orelse return;

    // Check if this is block form (has braces) vs expression form
    const then_node = for_info.ast.then_expr;
    const then_tag = tags[@intFromEnum(then_node)];

    // Only process block form (where then_expr is a block)
    if (!is_block_tag(then_tag))
    {
        return;
    }

    // Get the base indentation from the for keyword
    const for_token = for_info.ast.for_token;
    const base_indent = get_line_indent(
        source,
        line_index.line_start(token_starts[for_token]),
    );

    // Determine if condition spans multiple lines
    // Find the lparen after 'for'
    var lparen_tok = for_token + 1;
    while (ast.tokens.items(.tag)[lparen_tok] != .l_paren)
    {
        lparen_tok += 1;
    }

    // Find the rparen before the payload capture
    // The payload token points to the first identifier in |...|
    // So rparen is payload_token - 2 (before the opening |)
    const payload_token = for_info.payload_token;
    const rparen_tok = payload_token - 2;

    const is_multiline_condition = !line_index.same_line(
        token_starts[lparen_tok],
        token_starts[rparen_tok],
    );

    // Find the closing pipe of the payload capture
    var capture_end_tok = payload_token;
    while (ast.tokens.items(.tag)[capture_end_tok] != .pipe)
    {
        capture_end_tok += 1;
    }

    // Handle capture placement based on condition length
    try emit_capture_placement_edit(
        allocator,
        ast,
        edits,
        rparen_tok,
        payload_token,
        is_multiline_condition,
        base_indent,
        line_index,
    );

    // Get the opening brace of the body
    const then_lbrace = main_tokens[@intFromEnum(then_node)];

    // Check if this is a labeled block - if so, don't move the brace
    if (!is_labeled_block(ast, then_lbrace))
    {
        // Check if opening brace is on same line as capture end
        if (
            line_index.same_line(
                token_starts[capture_end_tok],
                token_starts[then_lbrace],
            )
        )
        {
            // Need to insert newline before brace
            const brace_start = token_starts[then_lbrace];

            // Find where whitespace before brace starts
            const ws_start = skip_whitespace_back(source, brace_start);

            const indent_text = try std.fmt.allocPrint(
                allocator,
                "\n{s}",
                .{base_indent},
            );

            try edits.append(
                allocator,
                .{
                    .start_byte = ws_start,
                    .end_byte = brace_start,
                    .new_text = indent_text,
                },
            );
        }
    }

    // Process else clause if present
    if (for_info.ast.else_expr != .none)
    {
        const else_token = for_info.else_token orelse return;
        const else_expr = for_info.ast.else_expr.unwrap() orelse return;
        const then_rbrace = ast.lastToken(then_node);

        try emit_else_clause_edits(
            allocator,
            ast,
            source,
            edits,
            then_rbrace,
            else_token,
            else_expr,
            base_indent,
            line_index,
        );
    }
}

fn process_while_statement(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    node_index: Ast.Node.Index,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const tags = ast.nodes.items(.tag);
    const main_tokens = ast.nodes.items(.main_token);
    const token_starts = ast.tokens.items(.start);

    // Get the full while statement info
    const while_info = ast.fullWhile(node_index) orelse return;

    // Check if this is block form (has braces) vs expression form
    const then_node = while_info.ast.then_expr;
    const then_tag = tags[@intFromEnum(then_node)];

    // Only process block form (where then_expr is a block)
    if (!is_block_tag(then_tag))
    {
        return;
    }

    // Get the base indentation from the while keyword
    const while_token = while_info.ast.while_token;
    const base_indent = get_line_indent(
        source,
        line_index.line_start(token_starts[while_token]),
    );

    // Determine if condition spans multiple lines
    // Find the lparen after 'while'
    var lparen_tok = while_token + 1;
    while (ast.tokens.items(.tag)[lparen_tok] != .l_paren)
    {
        lparen_tok += 1;
    }

    // Find the rparen - it's after the condition expression
    const cond_last_tok = ast.lastToken(while_info.ast.cond_expr);
    const rparen_tok = cond_last_tok + 1;

    const rparen_line = line_index.line_of(token_starts[rparen_tok]);
    const is_multiline_condition = !line_index.same_line(
        token_starts[lparen_tok],
        token_starts[rparen_tok],
    );

    // Handle continue expression placement (only while loops have these)
    // Skip if body is a labeled block (continue expr stays on same line)
    const then_lbrace = main_tokens[@intFromEnum(then_node)];
    const has_labeled_body = is_labeled_block(ast, then_lbrace);

    if (while_info.ast.cont_expr.unwrap())
        |cont_expr|
    {
        if (!has_labeled_body)
        {
            // Token layout: ) : ( <cont_expr tokens> )
            const colon_tok = rparen_tok + 1;
            const colon_line = line_index.line_of(token_starts[colon_tok]);
            const rparen_end = token_starts[rparen_tok] + 1;
            const colon_start = token_starts[colon_tok];

            if (is_multiline_condition)
            {
                // Multi-line condition: continue expr stays on same line as )
                if (rparen_line != colon_line)
                {
                    try edits.append(
                        allocator,
                        .{
                            .start_byte = rparen_end,
                            .end_byte = colon_start,
                            .new_text = " ",
                        },
                    );
                }
            }
            else
            {
                if (rparen_line == colon_line)
                {
                    // Single-line condition: continue expr goes on its own
                    // indented line
                    const indent_text = try std.fmt.allocPrint(
                        allocator,
                        "\n{s}    ",
                        .{base_indent},
                    );

                    try edits.append(
                        allocator,
                        .{
                            .start_byte = rparen_end,
                            .end_byte = colon_start,
                            .new_text = indent_text,
                        },
                    );
                }
                else
                {
                    // Continue expr is already on its own line — check if
                    // it needs
                    // to be broken open: `: (\n        content\n    )`
                    const cont_lparen_tok = rparen_tok + 2; // the ( after :
                    const cont_last_tok = ast.lastToken(cont_expr);
                    // the ) closing the continue expr
                    const cont_rparen_tok = cont_last_tok + 1;
                    const cont_lparen_line = line_index.line_of(
                        token_starts[cont_lparen_tok],
                    );
                    const cont_rparen_line = line_index.line_of(
                        token_starts[cont_rparen_tok],
                    );
                    const cont_first_tok = cont_lparen_tok + 1;
                    const cont_first_line = line_index.line_of(
                        token_starts[cont_first_tok],
                    );

                    // Check if content is NOT already on its own line after (
                    const needs_break = (
                        cont_lparen_line == cont_first_line
                        and (
                            cont_lparen_line != cont_rparen_line
                            or compute_line_length(
                                source,
                                line_index.line_start(
                                    token_starts[colon_tok],
                                ),
                            ) > MAX_LINE_LENGTH
                        )
                    );

                    if (needs_break)
                    {
                        const cont_lparen_end = (
                            token_starts[cont_lparen_tok] + 1
                        );
                        const cont_first_start = token_starts[cont_first_tok];

                        // After (: insert newline + base_indent + 8 spaces
                        const inner_indent = try std.fmt.allocPrint(
                            allocator,
                            "\n{s}        ",
                            .{base_indent},
                        );

                        try edits.append(
                            allocator,
                            .{
                                .start_byte = cont_lparen_end,
                                .end_byte = cont_first_start,
                                .new_text = inner_indent,
                            },
                        );

                        // Before ): insert newline + base_indent + 4 spaces
                        const cont_rparen_start = (
                            token_starts[cont_rparen_tok]
                        );
                        const ws_before_rparen = skip_whitespace_back(
                            source,
                            cont_rparen_start,
                        );

                        const closing_indent = try std.fmt.allocPrint(
                            allocator,
                            "\n{s}    ",
                            .{base_indent},
                        );

                        try edits.append(
                            allocator,
                            .{
                                .start_byte = ws_before_rparen,
                                .end_byte = cont_rparen_start,
                                .new_text = closing_indent,
                            },
                        );
                    }
                }
            }
        }
    }

    // Find the transition point (after condition or after payload capture)
    var transition_end_token: Ast.TokenIndex = undefined;

    if (while_info.payload_token)
        |payload_tok|
    {
        // Has a capture like |value|
        var tok = payload_tok;
        while (ast.tokens.items(.tag)[tok] != .pipe)
        {
            tok += 1;
        }
        transition_end_token = tok;

        // Handle capture placement based on condition length
        try emit_capture_placement_edit(
            allocator,
            ast,
            edits,
            rparen_tok,
            payload_tok,
            is_multiline_condition,
            base_indent,
            line_index,
        );
    }
    else
    {
        // No capture - check for continue expression to set transition point
        if (while_info.ast.cont_expr.unwrap())
            |cont_expr|
        {
            // Transition is after the continue expression's closing paren
            transition_end_token = ast.lastToken(cont_expr) + 1;
        }
        else
        {
            transition_end_token = rparen_tok;
        }
    }

    // Check if this is a labeled block - if so, don't move the brace
    if (!has_labeled_body)
    {
        // Check if opening brace is on same line as transition point
        if (
            line_index.same_line(
                token_starts[transition_end_token],
                token_starts[then_lbrace],
            )
        )
        {
            // Need to insert newline before brace
            const brace_start = token_starts[then_lbrace];

            // Find where whitespace before brace starts
            const ws_start = skip_whitespace_back(source, brace_start);

            const indent_text = try std.fmt.allocPrint(
                allocator,
                "\n{s}",
                .{base_indent},
            );

            try edits.append(
                allocator,
                .{
                    .start_byte = ws_start,
                    .end_byte = brace_start,
                    .new_text = indent_text,
                },
            );
        }
    }

    // Process else clause if present
    if (while_info.ast.else_expr != .none)
    {
        const else_token = while_info.else_token;
        const else_expr = while_info.ast.else_expr.unwrap() orelse return;
        const then_rbrace = ast.lastToken(then_node);

        try emit_else_clause_edits(
            allocator,
            ast,
            source,
            edits,
            then_rbrace,
            else_token,
            else_expr,
            base_indent,
            line_index,
        );
    }
}

fn process_switch_statement(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    node_index: Ast.Node.Index,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    // Get the full switch info
    const switch_info = ast.fullSwitch(node_index) orelse return;
    const token_starts = ast.tokens.items(.start);

    // Get the switch keyword token for indentation
    const switch_token = switch_info.ast.switch_token;
    const base_indent = get_line_indent(
        source,
        line_index.line_start(token_starts[switch_token]),
    );

    // Find the lparen after 'switch'
    var lparen_tok = switch_token + 1;
    while (
        lparen_tok < ast.tokens.len and ast.tokens.items(
            .tag,
        )[lparen_tok] != .l_paren
    )
    {
        lparen_tok += 1;
    }

    // Find the opening brace of the switch body
    // The brace comes after the condition's closing paren
    const cond_node = switch_info.ast.condition;
    const cond_last_token = ast.lastToken(cond_node);

    // The rparen is right after the condition
    const rparen_tok = cond_last_token + 1;

    // Determine if condition spans multiple lines
    const is_multiline_condition = !line_index.same_line(
        token_starts[lparen_tok],
        token_starts[rparen_tok],
    );

    // Find the opening brace
    var brace_token = rparen_tok + 1;
    while (
        brace_token < ast.tokens.len and ast.tokens.items(
            .tag,
        )[brace_token] != .l_brace
    )
    {
        brace_token += 1;
    }
    // Safety limit
    if (brace_token >= ast.tokens.len)
    {
        return;
    }

    const brace_start = token_starts[brace_token];

    if (is_multiline_condition)
    {
        // Multi-line condition: brace should be on its own line
        if (
            line_index.same_line(
                token_starts[rparen_tok],
                token_starts[brace_token],
            )
        )
        {
            // Need to insert newline before brace
            const ws_start = skip_whitespace_back(source, brace_start);

            const indent_text = try std.fmt.allocPrint(
                allocator,
                "\n{s}",
                .{base_indent},
            );

            try edits.append(
                allocator,
                .{
                    .start_byte = ws_start,
                    .end_byte = brace_start,
                    .new_text = indent_text,
                },
            );
        }
    }
    else
    {
        // Single-line condition: brace should be on same line as )
        if (
            !line_index.same_line(
                token_starts[rparen_tok],
                token_starts[brace_token],
            )
        )
        {
            // Brace is on different line - move it to same line
            const rparen_start = token_starts[rparen_tok];
            const rparen_end = rparen_start + 1; // ) is 1 char

            // Replace everything between ) and { with single space
            try edits.append(
                allocator,
                .{
                    .start_byte = rparen_end,
                    .end_byte = brace_start,
                    .new_text = " ",
                },
            );
        }
    }
}

fn process_container_decl(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    node_index: Ast.Node.Index,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const main_tokens = ast.nodes.items(.main_token);

    // Get the main token (struct, enum, union, opaque keyword)
    const main_token = main_tokens[@intFromEnum(node_index)];

    // Find the opening brace by scanning tokens after the main token
    // For simple containers: struct { ... }
    // For parameterized: struct(arg) { ... }
    // For tagged unions: union(enum) { ... } or union(enum(arg)) { ... }
    var brace_token = main_token + 1;
    while (
        brace_token < ast.tokens.len and ast.tokens.items(
            .tag,
        )[brace_token] != .l_brace
    )
    {
        brace_token += 1;
    }

    // Safety check
    if (brace_token >= ast.tokens.len)
    {
        return;
    }

    // Get the token before the brace (struct/enum/union keyword or closing
    // paren)
    const prev_tok = brace_token - 1;
    const token_starts = ast.tokens.items(.start);

    // Rule: struct/enum/union opening brace should be on SAME line as keyword
    if (
        !line_index.same_line(
            token_starts[prev_tok],
            token_starts[brace_token],
        )
    )
    {
        // Brace is on different line - move it to same line
        const brace_start = token_starts[brace_token];

        // Find the end of the previous token
        const prev_start = token_starts[prev_tok];
        var prev_end = prev_start;
        while (
            prev_end < source.len
            and source[prev_end] != ' '
            and source[prev_end] != '\t'
            and source[prev_end] != '\n'
        )
        {
            prev_end += 1;
        }

        // Replace everything between prev token end and brace with single
        // space
        try edits.append(
            allocator,
            .{
                .start_byte = prev_end,
                .end_byte = brace_start,
                .new_text = " ",
            },
        );
    }
}

fn process_labeled_block(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    _: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    node_index: Ast.Node.Index,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const main_tokens = ast.nodes.items(.main_token);
    const token_tags = ast.tokens.items(.tag);
    const token_starts = ast.tokens.items(.start);

    // The main token of a block is the opening brace
    const lbrace_token = main_tokens[@intFromEnum(node_index)];

    // Check if the token before the brace is a colon (indicating a label)
    if (lbrace_token == 0)
    {
        return;
    }

    // Look for the pattern: identifier colon lbrace
    // The colon should be the token immediately before the lbrace
    const prev_token = lbrace_token - 1;
    if (token_tags[prev_token] != .colon)
    {
        return;
    }

    // This is a labeled block - ensure brace is on same line as colon
    if (
        !line_index.same_line(
            token_starts[prev_token],
            token_starts[lbrace_token],
        )
    )
    {
        // Brace is on different line - move it to same line as colon
        const colon_start = token_starts[prev_token];
        const colon_end = colon_start + 1; // colon is 1 char
        const brace_start = token_starts[lbrace_token];

        // Replace whitespace between colon and brace with single space
        try edits.append(
            allocator,
            .{
                .start_byte = colon_end,
                .end_byte = brace_start,
                .new_text = " ",
            },
        );
    }
}

fn process_fn_decl(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    node_index: Ast.Node.Index,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const main_tokens = ast.nodes.items(.main_token);
    const node_data = ast.nodes.items(.data);
    const tags = ast.nodes.items(.tag);
    const token_starts = ast.tokens.items(.start);

    // Get the fn_decl data
    const data = node_data[@intFromEnum(node_index)];

    // data.node_and_node[0] is the fn_proto
    // data.node_and_node[1] is the body block
    const body_node: Ast.Node.Index = data.node_and_node[1];
    const body_tag = tags[@intFromEnum(body_node)];

    // Only process if body is a block
    if (!is_block_tag(body_tag))
    {
        return;
    }

    // Get the fn keyword token for indentation
    const fn_token = main_tokens[@intFromEnum(node_index)];
    const base_indent = get_line_indent(
        source,
        line_index.line_start(token_starts[fn_token]),
    );

    // Get the opening brace of the body
    const body_lbrace = main_tokens[@intFromEnum(body_node)];

    // Find the last token before the brace (the return type or closing paren)
    // We need to look at the token just before the brace
    const brace_start = token_starts[body_lbrace];

    // Find what's before the brace by looking at previous tokens
    const prev_tok = body_lbrace - 1;

    if (
        line_index.same_line(
            token_starts[prev_tok],
            token_starts[body_lbrace],
        )
    )
    {
        // Need to insert newline before brace
        // Find where whitespace before brace starts
        const ws_start = skip_whitespace_back(source, brace_start);

        const indent_text = try std.fmt.allocPrint(
            allocator,
            "\n{s}",
            .{base_indent},
        );

        try edits.append(
            allocator,
            .{
                .start_byte = ws_start,
                .end_byte = brace_start,
                .new_text = indent_text,
            },
        );
    }
}

fn process_test_decl(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    node_index: Ast.Node.Index,
    line_index: *const LineIndex,
) std.mem.Allocator.Error!void
{
    const main_tokens = ast.nodes.items(.main_token);
    const node_data = ast.nodes.items(.data);
    const tags = ast.nodes.items(.tag);
    const token_starts = ast.tokens.items(.start);

    // Get the test keyword token
    const test_token = main_tokens[@intFromEnum(node_index)];

    // Get the block node (the body of the test)
    const data = node_data[@intFromEnum(node_index)];
    const block_node: Ast.Node.Index = data.opt_token_and_node[1];
    const block_tag = tags[@intFromEnum(block_node)];

    // Only process if it's a block
    if (!is_block_tag(block_tag))
    {
        return;
    }

    // Get the opening brace of the block
    const block_lbrace = main_tokens[@intFromEnum(block_node)];

    // Find what comes before the brace - either the test name or the test
    // keyword
    // test "name" { ... } or test { ... }
    const name_token_opt: Ast.OptionalTokenIndex = data.opt_token_and_node[0];

    var last_token_before_brace: Ast.TokenIndex = undefined;
    if (name_token_opt != .none)
    {
        // Has a name - the last token is the closing quote of the string
        last_token_before_brace = @intFromEnum(name_token_opt);
    }
    else
    {
        // No name - just "test { }"
        last_token_before_brace = test_token;
    }

    // Get the base indentation from the test keyword
    const base_indent = get_line_indent(
        source,
        line_index.line_start(token_starts[test_token]),
    );

    // Check if opening brace is on same line as the last token
    if (
        line_index.same_line(
            token_starts[last_token_before_brace],
            token_starts[block_lbrace],
        )
    )
    {
        // Need to insert newline before brace
        const brace_start = token_starts[block_lbrace];

        // Find where whitespace before brace starts
        const ws_start = skip_whitespace_back(source, brace_start);

        const indent_text = try std.fmt.allocPrint(
            allocator,
            "\n{s}",
            .{base_indent},
        );

        try edits.append(
            allocator,
            .{
                .start_byte = ws_start,
                .end_byte = brace_start,
                .new_text = indent_text,
            },
        );
    }
}

fn is_block_tag(
    tag: Ast.Node.Tag,
) bool
{
    return (
        tag == .block
        or tag == .block_two
        or tag == .block_two_semicolon
        or tag == .block_semicolon
    );
}

fn is_call_tag(
    tag: Ast.Node.Tag,
) bool
{
    return (
        tag == .call
        or tag == .call_comma
        or tag == .call_one
        or tag == .call_one_comma
    );
}

fn is_struct_init_tag(
    tag: Ast.Node.Tag,
) bool
{
    return (
        tag == .struct_init
        or tag == .struct_init_comma
        or tag == .struct_init_one
        or tag == .struct_init_one_comma
        or tag == .struct_init_dot
        or tag == .struct_init_dot_comma
        or tag == .struct_init_dot_two
        or tag == .struct_init_dot_two_comma
    );
}

/// Check if a block is labeled (has a colon token before the brace)
fn is_labeled_block(
    ast: *const Ast,
    lbrace_token: Ast.TokenIndex,
) bool
{
    if (lbrace_token == 0)
    {
        return false;
    }
    const token_tags = ast.tokens.items(.tag);
    return token_tags[lbrace_token - 1] == .colon;
}

fn get_line_indent(
    source: []const u8,
    line_start: usize,
) []const u8
{
    const end = skip_whitespace_fwd(source, line_start);
    return source[line_start..end];
}

/// Compute the length of the line starting at the given byte offset
/// (line_start).
fn compute_line_length(
    source: []const u8,
    line_start: usize,
) usize
{
    var end = line_start;
    while (
        end < source.len
        and source[end] != '\n'
    )
    {
        end += 1;
    }
    return end - line_start;
}

/// Check naming conventions and emit warnings
fn check_naming_conventions(
    ast: *const Ast,
    source: []const u8,
    line_index: *const LineIndex,
) void
{
    const tags = ast.nodes.items(.tag);
    const main_tokens = ast.nodes.items(.main_token);
    const token_tags = ast.tokens.items(.tag);

    for (0..ast.nodes.len)
        |i|
    {
        const node_index: Ast.Node.Index = @enumFromInt(i);
        const tag = tags[@intFromEnum(node_index)];

        // Check function declarations
        if (tag == .fn_decl)
        {
            // The function name is the token after 'fn'
            const fn_token = main_tokens[@intFromEnum(node_index)];

            // Find the identifier token (function name)
            var name_token = fn_token + 1;
            while (
                name_token < ast.tokens.len
                and token_tags[name_token] != .identifier
            )
            {
                name_token += 1;
            }

            if (name_token < ast.tokens.len)
            {
                const name_start = ast.tokens.items(.start)[name_token];
                const name_end = blk: {
                    if (name_token + 1 < ast.tokens.len)
                    {
                        break :blk ast.tokens.items(.start)[name_token + 1];
                    }
                    break :blk source.len;
                };

                // Trim whitespace to get just the identifier
                var end = name_end;
                while (
                    end > name_start
                    and (
                        source[end - 1] == ' '
                        or source[end - 1] == '\t'
                        or source[end - 1] == '\n'
                        or source[end - 1] == '('
                    )
                )
                {
                    end -= 1;
                }

                const fn_name = source[name_start..end];

                if (!is_snake_case(fn_name))
                {
                    std.debug.print(
                        ("warning: line {d}: function '{s}' is not "
                            ++ "snake_case\n"),
                        .{ line_index.line_of(
                            ast.tokens.items(.start)[name_token],
                        ) + 1, fn_name },
                    );
                }
            }
        }
    }
}

/// Check if a string follows snake_case convention
/// snake_case: lowercase letters, numbers, and underscores only
/// No leading/trailing underscores, no consecutive underscores
fn is_snake_case(
    name: []const u8,
) bool
{
    if (name.len == 0)
    {
        return true;
    }

    // Must start with lowercase letter
    if (!std.ascii.isLower(name[0]))
    {
        return false;
    }

    // Must end with lowercase letter or digit
    if (
        !std.ascii.isLower(
            name[name.len - 1],
        ) and !std.ascii.isDigit(
            name[name.len - 1],
        )
    )
    {
        return false;
    }

    var prev_underscore = false;
    for (name)
        |c|
    {
        if (c == '_')
        {
            // No consecutive underscores
            if (prev_underscore)
            {
                return false;
            }
            prev_underscore = true;
        }
        else if (
            std.ascii.isLower(
                c,
            ) or std.ascii.isDigit(
                c,
            )
        )
        {
            prev_underscore = false;
        }
        else
        {
            // Uppercase letters or other chars not allowed
            return false;
        }
    }

    return true;
}

/// Find all lines in the source that exceed MAX_LINE_LENGTH
fn find_long_lines(
    allocator: std.mem.Allocator,
    source: []const u8,
) ![]LongLine
{
    var long_lines: std.ArrayListUnmanaged(LongLine) = .{};
    errdefer long_lines.deinit(allocator);

    var line_start: usize = 0;
    var line_number: usize = 0;

    for (source, 0..)
        |c, i|
    {
        if (c == '\n')
        {
            const line_end = i;
            const line_length = line_end - line_start;

            if (line_length > MAX_LINE_LENGTH)
            {
                try long_lines.append(
                    allocator,
                    .{
                        .line_number = line_number,
                        .line_start = line_start,
                        .line_end = line_end,
                        .length = line_length,
                    },
                );
            }

            line_start = i + 1;
            line_number += 1;
        }
    }

    // Handle last line if it doesn't end with newline
    if (line_start < source.len)
    {
        const line_length = source.len - line_start;
        if (line_length > MAX_LINE_LENGTH)
        {
            try long_lines.append(
                allocator,
                .{
                    .line_number = line_number,
                    .line_start = line_start,
                    .line_end = source.len,
                    .length = line_length,
                },
            );
        }
    }

    return long_lines.toOwnedSlice(allocator);
}

/// Find the byte offset of a trailing `//` comment on a line,
/// skipping over `//` that appears inside string literals or
/// character literals.  Returns null if no trailing comment is
/// found (i.e. the line is a comment-only line or has no comment).
fn find_trailing_comment(
    line_text: []const u8,
) ?usize
{
    // Find indent end
    var indent_end: usize = 0;
    while (
        indent_end < line_text.len
        and (
            line_text[indent_end] == ' '
            or line_text[indent_end] == '\t'
        )
    )
    {
        indent_end += 1;
    }

    // If line starts with // it's a comment-only line, not trailing
    if (
        indent_end + 1 < line_text.len
        and line_text[indent_end] == '/'
        and line_text[indent_end + 1] == '/'
    )
    {
        return null;
    }

    var i: usize = indent_end;
    while (i < line_text.len)
    {
        const c = line_text[i];

        // Skip string and character literals
        if (c == '"')
        {
            i = skip_literal(line_text, i, '"');
            continue;
        }
        if (c == '\'')
        {
            i = skip_literal(line_text, i, '\'');
            continue;
        }

        // Check for //
        if (
            c == '/'
            and i + 1 < line_text.len
            and line_text[i + 1] == '/'
        )
        {
            return i;
        }

        i += 1;
    }

    return null;
}

/// Collect edits to move trailing comments (that push a line over
/// the length limit) to the line above.  The comment keeps the
/// same indentation as the code line, and trailing whitespace is
/// stripped from the remaining code.
/// Works on raw source text — no AST needed.
fn collect_trailing_comment_edits(
    allocator: std.mem.Allocator,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    long_lines: []const LongLine,
) std.mem.Allocator.Error!void
{
    for (long_lines)
        |line|
    {
        const line_text = source[line.line_start..line.line_end];

        const comment_offset = find_trailing_comment(
            line_text,
        ) orelse continue;

        // Extract the pieces
        const indent = get_line_indent(source, line.line_start);
        const comment = line_text[comment_offset..];

        // Trim trailing whitespace from the code portion
        var code_end = comment_offset;
        while (
            code_end > 0
            and (
                line_text[code_end - 1] == ' '
                or line_text[code_end - 1] == '\t'
            )
        )
        {
            code_end -= 1;
        }
        const code = line_text[0..code_end];

        // Build replacement: {indent}{comment}\n{code}
        const replacement = std.fmt.allocPrint(
            allocator,
            "{s}{s}\n{s}",
            .{ indent, comment, code },
        ) catch return;

        try edits.append(
            allocator,
            .{
                .start_byte = line.line_start,
                .end_byte = line.line_end,
                .new_text = replacement,
            },
        );
    }
}

/// Collect edits to wrap long comments at word boundaries.
/// Works on raw source text — no AST needed.
fn collect_comment_wrap_edits(
    allocator: std.mem.Allocator,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    long_lines: []const LongLine,
) std.mem.Allocator.Error!void
{
    for (long_lines)
        |line|
    {
        const line_text = source[line.line_start..line.line_end];

        // Find the indent
        var indent_end: usize = 0;
        while (
            indent_end < line_text.len
            and (
                line_text[indent_end] == ' '
                or line_text[indent_end] == '\t'
            )
        )
        {
            indent_end += 1;
        }

        // Check if line starts with a comment prefix
        const after_indent = line_text[indent_end..];
        var prefix_len: usize = 0;
        if (std.mem.startsWith(u8, after_indent, "/// "))
        {
            prefix_len = 4;
        }
        else if (std.mem.startsWith(u8, after_indent, "// "))
        {
            prefix_len = 3;
        }
        else
        {
            continue;
        }

        const indent = line_text[0..indent_end];
        const prefix = after_indent[0..prefix_len];
        const content = after_indent[prefix_len..];

        // Skip if content contains a URL
        if (
            std.mem.indexOf(
                u8,
                content,
                "http://",
            ) != null or std.mem.indexOf(
                u8,
                content,
                "https://",
            ) != null
        )
        {
            continue;
        }

        const max_width = if (MAX_LINE_LENGTH > indent_end + prefix_len)
            MAX_LINE_LENGTH - indent_end - prefix_len
        else
            continue;

        // Skip if the first word alone exceeds max width
        var first_word_end: usize = 0;
        while (
            first_word_end < content.len
            and content[first_word_end] != ' '
        )
        {
            first_word_end += 1;
        }
        if (first_word_end > max_width)
        {
            continue;
        }

        // Word-wrap the content
        var wrapped: std.ArrayListUnmanaged(u8) = .{};
        defer wrapped.deinit(allocator);

        var col: usize = 0;
        var first_line = true;
        var i: usize = 0;
        while (i < content.len)
        {
            // Find next word
            var word_start = i;
            while (
                word_start < content.len
                and content[word_start] == ' '
            )
            {
                word_start += 1;
            }
            if (word_start >= content.len)
            {
                break;
            }

            var word_end = word_start;
            // Handle backtick-quoted spans
            if (content[word_end] == '`')
            {
                word_end += 1;
                while (
                    word_end < content.len
                    and content[word_end] != '`'
                )
                {
                    word_end += 1;
                }
                if (word_end < content.len)
                {
                    word_end += 1;
                }
                // Include trailing non-space chars
                // (e.g. punctuation)
                while (
                    word_end < content.len
                    and content[word_end] != ' '
                )
                {
                    word_end += 1;
                }
            }
            else
            {
                while (
                    word_end < content.len
                    and content[word_end] != ' '
                )
                {
                    word_end += 1;
                }
            }

            const word = content[word_start..word_end];

            if (
                !first_line
                and col + 1 + word.len > max_width
            )
            {
                // Start a new comment line
                try wrapped.appendSlice(allocator, "\n");
                try wrapped.appendSlice(allocator, indent);
                try wrapped.appendSlice(allocator, prefix);
                try wrapped.appendSlice(allocator, word);
                col = word.len;
            }
            else if (col == 0)
            {
                try wrapped.appendSlice(allocator, word);
                col = word.len;
            }
            else
            {
                try wrapped.append(allocator, ' ');
                try wrapped.appendSlice(allocator, word);
                col += 1 + word.len;
            }

            first_line = false;
            i = word_end;
        }

        // Only create edit if wrapping actually happened
        const wrapped_text = wrapped.items;
        if (std.mem.indexOf(u8, wrapped_text, "\n") == null)
        {
            continue;
        }

        // Build the full replacement (indent + prefix + wrapped)
        const full_text = std.fmt.allocPrint(
            allocator,
            "{s}{s}{s}",
            .{ indent, prefix, wrapped_text },
        ) catch return;

        try edits.append(
            allocator,
            .{
                .start_byte = line.line_start,
                .end_byte = line.line_end,
                .new_text = full_text,
            },
        );
    }
}

/// Return the byte length of the escape sequence starting at
/// `content[pos]` where `content[pos] == '\\'`.
fn escape_sequence_length(
    content: []const u8,
    pos: usize,
) usize
{
    if (pos + 1 >= content.len)
    {
        return 1;
    }
    return switch (content[pos + 1]) {
        'x' => 4, // \xNN
        'u' => blk: {
            // \u{...}
            if (
                pos + 2 < content.len
                and content[pos + 2] == '{'
            )
            {
                var end = pos + 3;
                while (
                    end < content.len
                    and content[end] != '}'
                )
                {
                    end += 1;
                }
                if (end < content.len)
                {
                    // include the closing '}'
                    break :blk end + 1 - pos;
                }
            }
            break :blk 2;
        },
        '0', 'n', 't', 'r', '\\', '\'', '"' => 2,
        else => 2,
    };
}

/// Find a split point in string content at a space boundary within
/// the given budget. Returns the byte offset *after* the space
/// (start of the next word), or null if no suitable split exists.
fn find_string_split_point(
    content: []const u8,
    budget: usize,
) ?usize
{
    var i: usize = 0;
    var last_split: ?usize = null;

    while (
        i < content.len
        and i < budget
    )
    {
        if (content[i] == '\\')
        {
            const esc_len = escape_sequence_length(content, i);
            if (i + esc_len > budget)
            {
                break;
            }
            i += esc_len;
        }
        else if (content[i] == ' ')
        {
            last_split = i + 1;
            i += 1;
        }
        else
        {
            i += 1;
        }
    }

    // Don't split if the split is at the very start or end
    if (last_split)
        |sp|
    {
        if (
            sp == 0
            or sp >= content.len
        )
        {
            return null;
        }
    }

    return last_split;
}

/// Find the position of an assignment `= ` on a line, skipping
/// occurrences inside string/char literals and ensuring it is not
/// part of `==`, `!=`, `<=`, `>=`, `=>`.  Returns the byte offset
/// (relative to `line_text`) of the `=`, or null.
fn find_assignment_eq(
    line_text: []const u8,
) ?usize
{
    var i: usize = 0;
    while (i < line_text.len)
    {
        const c = line_text[i];

        // Skip string and character literals
        if (c == '"')
        {
            i = skip_literal(line_text, i, '"');
            continue;
        }
        if (c == '\'')
        {
            i = skip_literal(line_text, i, '\'');
            continue;
        }

        if (c == '=')
        {
            // Skip ==, =>, and check for !=, <=, >=
            if (
                i + 1 < line_text.len
                and (
                    line_text[i + 1] == '='
                    or line_text[i + 1] == '>'
                )
            )
            {
                i += 2;
                continue;
            }
            if (
                i > 0
                and (
                    line_text[i - 1] == '!'
                    or line_text[i - 1] == '<'
                    or line_text[i - 1] == '>'
                )
            )
            {
                i += 1;
                continue;
            }
            // Must be followed by a space to be an assignment
            if (
                i + 1 < line_text.len
                and line_text[i + 1] == ' '
            )
            {
                // Skip struct field init: .field = value
                // Walk backwards past space before '=' to find
                // the identifier, then check for '.'
                var j = i;
                // Skip space before '='
                while (
                    j > 0
                    and (
                        line_text[j - 1] == ' '
                        or line_text[j - 1] == '\t'
                    )
                )
                {
                    j -= 1;
                }
                // Skip identifier
                while (
                    j > 0 and (std.ascii.isAlphanumeric(
                        line_text[j - 1],
                    ) or line_text[j - 1] == '_')
                )
                {
                    j -= 1;
                }
                // If we hit a '.', this is a struct field init
                if (
                    j > 0
                    and line_text[j - 1] == '.'
                )
                {
                    i += 1;
                    continue;
                }
                return i;
            }
        }

        i += 1;
    }
    return null;
}

/// Find the position of `return ` at the start of a line (after
/// indentation).  Returns the byte offset (relative to
/// `line_text`) just after "return ", or null.
fn find_return_keyword(
    line_text: []const u8,
) ?usize
{
    // Skip leading whitespace
    var indent_end: usize = 0;
    while (
        indent_end < line_text.len
        and (
            line_text[indent_end] == ' '
            or line_text[indent_end] == '\t'
        )
    )
    {
        indent_end += 1;
    }

    const after_indent = line_text[indent_end..];
    if (std.mem.startsWith(u8, after_indent, "return "))
    {
        return indent_end + 7; // "return " is 7 bytes
    }
    return null;
}

/// Collect edits to wrap the right-hand side of assignments or
/// return values in parentheses when the line is too long and no
/// other rule has handled it.  This is a near-last-resort rule.
fn collect_simple_expression_wrap_edits(
    allocator: std.mem.Allocator,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    prior_edit_count: usize,
    long_lines: []const LongLine,
) std.mem.Allocator.Error!void
{
    for (long_lines)
        |line|
    {
        // Last-resort check: skip if any prior edit targets this
        // line
        var already_handled = false;
        for (edits.items[0..prior_edit_count])
            |edit|
        {
            if (
                edit.start_byte >= line.line_start
                and edit.start_byte < line.line_end
            )
            {
                already_handled = true;
                break;
            }
        }
        if (already_handled)
        {
            continue;
        }

        const line_text = source[line.line_start..line.line_end];
        const base_indent = get_line_indent(source, line.line_start);

        // Try assignment `= expr;` first, then `return expr;`
        var expr_start_rel: usize = 0;
        if (find_assignment_eq(line_text))
            |eq_pos|
        {
            // RHS starts after "= "
            expr_start_rel = eq_pos + 2;
        }
        else if (find_return_keyword(line_text))
            |ret_end|
        {
            expr_start_rel = ret_end;
        }
        else
        {
            continue;
        }

        // Find trailing semicolon
        var semi_rel = line_text.len;
        while (
            semi_rel > expr_start_rel
            and line_text[semi_rel - 1] != ';'
        )
        {
            semi_rel -= 1;
        }
        if (
            semi_rel <= expr_start_rel
            or line_text[semi_rel - 1] != ';'
        )
        {
            continue;
        }
        // semi_rel points one past the ';', back up to point at it
        semi_rel -= 1;

        // Trim trailing whitespace before the semicolon
        var expr_end_rel = semi_rel;
        while (
            expr_end_rel > expr_start_rel
            and (
                line_text[expr_end_rel - 1] == ' '
                or line_text[expr_end_rel - 1] == '\t'
            )
        )
        {
            expr_end_rel -= 1;
        }

        if (expr_end_rel <= expr_start_rel)
        {
            continue;
        }

        const rhs = line_text[expr_start_rel..expr_end_rel];

        // Skip if RHS is a string literal — the string literal
        // breaker handles those
        if (rhs[0] == '"')
        {
            continue;
        }

        // Skip if RHS is a struct literal — the struct init
        // breaker handles those
        if (std.mem.startsWith(u8, rhs, ".{"))
        {
            continue;
        }

        // Check if already wrapped in parentheses
        if (
            rhs[0] == '('
            and rhs[rhs.len - 1] == ')'
        )
        {
            std.debug.print(
                ("warning: line {d} exceeds {d} characters"
                    ++ " ({d} chars) and needs to be"
                    ++ " hand-broken\n"),
                .{
                    line.line_number + 1,
                    MAX_LINE_LENGTH,
                    line.length,
                },
            );
            continue;
        }

        // Build replacement: (\n{indent}    expr\n{indent})
        const replacement = std.fmt.allocPrint(
            allocator,
            "(\n{s}    {s}\n{s})",
            .{ base_indent, rhs, base_indent },
        ) catch return;

        const expr_start_abs = line.line_start + expr_start_rel;
        const expr_end_abs = line.line_start + expr_end_rel;

        try edits.append(
            allocator,
            .{
                .start_byte = expr_start_abs,
                .end_byte = expr_end_abs,
                .new_text = replacement,
            },
        );
    }
}

/// Collect edits to break long string literals into parenthesized
/// `++` concatenations at word boundaries. This is a last-resort
/// rule — it only fires when no other rule has already produced
/// edits for the line.
fn collect_string_literal_break_edits(
    allocator: std.mem.Allocator,
    ast: *const Ast,
    source: []const u8,
    edits: *std.ArrayListUnmanaged(Edit),
    prior_edit_count: usize,
    long_lines: []const LongLine,
) std.mem.Allocator.Error!void
{
    const token_tags = ast.tokens.items(.tag);
    const token_starts = ast.tokens.items(.start);

    for (long_lines)
        |line|
    {
        // Last-resort check: skip if any prior edit targets this
        // line
        var already_handled = false;
        for (edits.items[0..prior_edit_count])
            |edit|
        {
            if (
                edit.start_byte >= line.line_start
                and edit.start_byte < line.line_end
            )
            {
                already_handled = true;
                break;
            }
        }
        if (already_handled)
        {
            continue;
        }

        // Find base indentation for this line
        const base_indent = get_line_indent(source, line.line_start);

        // Scan tokens on this line for a string_literal
        for (0..ast.tokens.len)
            |tok_i_usize|
        {
            const tok_i: Ast.TokenIndex = @intCast(tok_i_usize);
            const tok_start = token_starts[tok_i];

            if (tok_start < line.line_start)
            {
                continue;
            }
            if (tok_start >= line.line_end)
            {
                break;
            }

            if (token_tags[tok_i] != .string_literal)
            {
                continue;
            }

            // Get the full token slice (includes quotes)
            const str_slice = ast.tokenSlice(tok_i);
            if (str_slice.len < 3)
            {
                // Empty or trivially short string
                continue;
            }

            // Extract inner content (without quotes)
            const inner = str_slice[1 .. str_slice.len - 1];

            // Budget: how many content bytes fit in the first
            // fragment on the indented line
            // Layout: {indent}    "first_part"
            const overhead = base_indent.len + 4 + 2;
            if (overhead >= MAX_LINE_LENGTH)
            {
                continue;
            }
            const budget = MAX_LINE_LENGTH - overhead;

            const split_point = find_string_split_point(
                inner,
                budget,
            ) orelse continue;

            const first_part = inner[0..split_point];
            const second_part = inner[split_point..];

            // Build replacement:
            // (\n{indent}    "first_part"\n{indent}    ++ "second"
            // \n{indent})
            const replacement = std.fmt.allocPrint(
                allocator,
                "(\n{s}    \"{s}\"\n{s}    ++ \"{s}\"\n{s})",
                .{
                    base_indent,
                    first_part,
                    base_indent,
                    second_part,
                    base_indent,
                },
            ) catch return;

            const str_start = token_starts[tok_i];
            const str_end = str_start + str_slice.len;

            try edits.append(
                allocator,
                .{
                    .start_byte = str_start,
                    .end_byte = str_end,
                    .new_text = replacement,
                },
            );

            // Only handle one string per line per iteration
            break;
        }
    }
}

/// Report long lines as warnings (for now, until line breaking is
/// implemented)
fn report_long_lines(
    long_lines: []const LongLine,
) void
{
    for (long_lines)
        |line|
    {
        std.debug.print(
            "warning: line {d} exceeds {d} characters ({d} chars)\n",
            .{ line.line_number + 1, MAX_LINE_LENGTH, line.length },
        );
    }
}

// Tests
test "format simple if"
{
    const allocator = std.testing.allocator;

    const input =
        \\pub fn check(x: i32) bool {
        \\    if (x > 0) {
        \\        return true;
        \\    }
        \\    return false;
        \\}
    ;

    const expected =
        \\pub fn check(
        \\    x: i32,
        \\) bool
        \\{
        \\    if (x > 0)
        \\    {
        \\        return true;
        \\    }
        \\    return false;
        \\}
    ;

    const result = try format(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(expected, result);
}

test "format if-else"
{
    const allocator = std.testing.allocator;

    const input =
        \\pub fn check(x: i32) i32 {
        \\    if (x > 0) {
        \\        return 1;
        \\    } else {
        \\        return -1;
        \\    }
        \\}
    ;

    const expected =
        \\pub fn check(
        \\    x: i32,
        \\) i32
        \\{
        \\    if (x > 0)
        \\    {
        \\        return 1;
        \\    }
        \\    else
        \\    {
        \\        return -1;
        \\    }
        \\}
    ;

    const result = try format(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(expected, result);
}

test "format if-else-if"
{
    const allocator = std.testing.allocator;

    const input =
        \\pub fn check(x: i32) i32 {
        \\    if (x > 0) {
        \\        return 1;
        \\    } else if (x < 0) {
        \\        return -1;
        \\    } else {
        \\        return 0;
        \\    }
        \\}
    ;

    const expected =
        \\pub fn check(
        \\    x: i32,
        \\) i32
        \\{
        \\    if (x > 0)
        \\    {
        \\        return 1;
        \\    }
        \\    else if (x < 0)
        \\    {
        \\        return -1;
        \\    }
        \\    else
        \\    {
        \\        return 0;
        \\    }
        \\}
    ;

    const result = try format(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(expected, result);
}

test "idempotent - already formatted"
{
    const allocator = std.testing.allocator;

    const input =
        \\pub fn check(
        \\    x: i32,
        \\) bool
        \\{
        \\    if (x > 0)
        \\    {
        \\        return true;
        \\    }
        \\    return false;
        \\}
    ;

    const result = try format(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(input, result);
}

test "expression form unchanged"
{
    const allocator = std.testing.allocator;

    const input =
        \\pub fn check(x: i32) i32 {
        \\    const y = if (x > 0) x else -x;
        \\    return y;
        \\}
    ;

    const expected =
        \\pub fn check(
        \\    x: i32,
        \\) i32
        \\{
        \\    const y = if (x > 0) x else -x;
        \\    return y;
        \\}
    ;

    const result = try format(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(expected, result);
}

test "single statement unchanged"
{
    const allocator = std.testing.allocator;

    const input =
        \\pub fn check(x: i32) i32 {
        \\    if (x > 0) return x;
        \\    return 0;
        \\}
    ;

    const expected =
        \\pub fn check(
        \\    x: i32,
        \\) i32
        \\{
        \\    if (x > 0)
        \\    {
        \\        return x;
        \\    }
        \\    return 0;
        \\}
    ;

    const result = try format(allocator, input);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(expected, result);
}

test "find_long_lines"
{
    const allocator = std.testing.allocator;

    // Create lines of specific lengths
    // 78 chars exactly (should NOT trigger)
    const line_78 = "x" ** 78;
    // 79 chars (should trigger)
    const line_79 = "y" ** 79;
    // 80 chars (should trigger)
    const line_80 = "z" ** 80;

    const source = ("short\n"
        ++ line_78
        ++ "\n"
        ++ line_79
        ++ "\n"
        ++ line_80
        ++ "\n");

    const long_lines = try find_long_lines(allocator, source);
    defer allocator.free(long_lines);

    // Should find the 79-char and 80-char lines (lines 2 and 3, 0-indexed)
    try std.testing.expectEqual(@as(usize, 2), long_lines.len);
    try std.testing.expectEqual(@as(usize, 2), long_lines[0].line_number);
    try std.testing.expectEqual(@as(usize, 79), long_lines[0].length);
    try std.testing.expectEqual(@as(usize, 3), long_lines[1].line_number);
    try std.testing.expectEqual(@as(usize, 80), long_lines[1].length);
}

test "escape_sequence_length"
{
    // Simple two-byte escapes
    try std.testing.expectEqual(
        @as(usize, 2),
        escape_sequence_length("\\n", 0),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        escape_sequence_length("\\t", 0),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        escape_sequence_length("\\\\", 0),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        escape_sequence_length("\\\"", 0),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        escape_sequence_length("\\'", 0),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        escape_sequence_length("\\r", 0),
    );
    try std.testing.expectEqual(
        @as(usize, 2),
        escape_sequence_length("\\0", 0),
    );

    // Hex escape: \xNN = 4 bytes
    try std.testing.expectEqual(
        @as(usize, 4),
        escape_sequence_length("\\x1F", 0),
    );

    // Unicode escape: \u{NNNN} = variable
    // \u{1F600} = \ u { 1 F 6 0 0 } = 9 bytes
    try std.testing.expectEqual(
        @as(usize, 9),
        escape_sequence_length("\\u{1F600}", 0),
    );
    // \u{A} = \ u { A } = 5 bytes
    try std.testing.expectEqual(
        @as(usize, 5),
        escape_sequence_length("\\u{A}", 0),
    );

    // Escape at end of string (truncated)
    try std.testing.expectEqual(
        @as(usize, 1),
        escape_sequence_length("\\", 0),
    );
}

test "find_string_split_point basic"
{
    // Simple split at word boundary
    const result = find_string_split_point("hello world", 8);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 6), result.?);

    // Budget too small for any word
    const no_space = find_string_split_point("helloworld", 8);
    try std.testing.expect(no_space == null);

    // Exact budget hit
    const exact = find_string_split_point("ab cd ef", 5);
    try std.testing.expect(exact != null);
    try std.testing.expectEqual(@as(usize, 3), exact.?);
}

test "find_string_split_point with escapes"
{
    // Escape sequences are atomic — don't split in the middle
    // "abc\\ndef ghi" = a b c \ n d e f ' ' g h i (12 bytes)
    // With budget 10, we can reach the space at pos 8
    const esc = find_string_split_point("abc\\ndef ghi", 10);
    try std.testing.expect(esc != null);
    try std.testing.expectEqual(@as(usize, 9), esc.?);

    // Hex escape near budget
    // "a\\x1F b" = a \ x 1 F ' ' b (7 bytes)
    // With budget 7, after 'a'(0), \x1F takes 4 bytes (pos 1-4),
    // then ' '(5) → last_split=6, 'b'(6)
    const hex = find_string_split_point("a\\x1F b", 7);
    try std.testing.expect(hex != null);
    try std.testing.expectEqual(@as(usize, 6), hex.?);
}

test "find_string_split_point edge cases"
{
    // Single word — no split possible
    try std.testing.expect(find_string_split_point("abcdef", 10) == null);

    // Empty string
    try std.testing.expect(find_string_split_point("", 10) == null);

    // Space at very start — skip (don't return 1 as split where
    // first part is empty space)
    const leading = find_string_split_point(" abc", 10);
    try std.testing.expect(leading != null);
    try std.testing.expectEqual(@as(usize, 1), leading.?);
}

test "benchmark format throughput"
{
    const allocator = std.testing.allocator;

    // Build a synthetic ~5000 line source covering key
    // formatting patterns. Lines must be short enough that
    // the formatter won't try to break them (the multiline
    // string literal prefix counts toward line length).
    const block =
        \\const std = @import("std");
        \\
        \\fn example_fn(
        \\    allocator: std.mem.Allocator,
        \\    value: u32,
        \\    flag: bool,
        \\    name: []const u8,
        \\) !void {
        \\    const result = try do_work(
        \\        allocator,
        \\        value,
        \\        flag,
        \\        name,
        \\        .{ .opt_a = true, .opt_b = false },
        \\    );
        \\    if (
        \\        result.is_valid
        \\        and result.has_data
        \\        and result.check_other
        \\        or result.fallback
        \\    ) {
        \\        try process(result);
        \\    } else {
        \\        return error.Invalid;
        \\    }
        \\    const items = (
        \\        first_array
        \\        ++ second_array
        \\        ++ third_array
        \\        ++ fourth_array
        \\    );
        \\    for (items) |item| {
        \\        if (item.enabled) {
        \\            try handle(item);
        \\        }
        \\    }
        \\    while (iter.next()) |entry| {
        \\        if (
        \\            entry.key.len > 0
        \\            and entry.value != null
        \\        ) {
        \\            try map.put(
        \\                entry.key,
        \\                entry.value.?,
        \\            );
        \\        }
        \\    }
        \\    const config = Config{
        \\        .width = 80,
        \\        .height = 24,
        \\        .depth = 8,
        \\        .name = "default",
        \\        .enabled = true,
        \\    };
        \\    switch (value) {
        \\        0 => return null,
        \\        1 => try doSomething(),
        \\        2 => try doSomethingElse(),
        \\        else => return error.Unexpected,
        \\    }
        \\}
        \\
    ;
    const repeat_count = 85;
    var source_buf: std.ArrayListUnmanaged(u8) = .{};
    defer source_buf.deinit(allocator);
    for (0..repeat_count)
        |_|
    {
        try source_buf.appendSlice(allocator, block);
    }
    const source = source_buf.items;

    // Warmup
    {
        const result = try format(allocator, source);
        allocator.free(result);
    }

    const iterations = 5;
    var timer = try std.time.Timer.start();
    for (0..iterations)
        |_|
    {
        const result = try format(allocator, source);
        allocator.free(result);
    }
    const elapsed_ns = timer.read();
    const per_iter_ms = (@as(f64, @floatFromInt(elapsed_ns))
        / @as(f64, @floatFromInt(iterations))
        / 1_000_000.0);

    std.debug.print(
        "\n[BENCHMARK] {d} iterations on {d} bytes: {d:.1}ms/iter\n",
        .{ iterations, source.len, per_iter_ms },
    );
}
