const std = @import("std");
const fixedBufferStream = std.io.fixedBufferStream;
const testing = std.testing;

const style = @import("style.zig");
const Style = style.Style;
const FontStyle = style.FontStyle;
const Color = style.Color;

const esc = "\x1B";
const csi = esc ++ "[";

const reset = csi ++ "0m";

const font_style_codes = std.StaticStringMap([]const u8).initComptime(.{
    .{ "bold", "1" },
    .{ "dim", "2" },
    .{ "italic", "3" },
    .{ "underline", "4" },
    .{ "slowblink", "5" },
    .{ "rapidblink", "6" },
    .{ "reverse", "7" },
    .{ "hidden", "8" },
    .{ "crossedout", "9" },
    .{ "fraktur", "20" },
    .{ "overline", "53" },
});

/// Update the current style of the ANSI terminal
///
/// Optionally accepts the previous style active on the
/// terminal. Using this information, the function will update only
/// the attributes which are new in order to minimize the amount
/// written.
///
/// Tries to use as little bytes as necessary. Use this function if
/// you want to optimize for smallest amount of transmitted bytes
/// instead of computation speed.
pub fn updateStyle(writer: anytype, new: Style, old: ?Style) !void {
    if (old) |sty| if (new.eql(sty)) return;
    if (new.isDefault()) return try resetStyle(writer);

    // A reset is required if the new font style has attributes not
    // present in the old style or if the old style is not known
    const reset_required = if (old) |sty| !sty.font_style.subsetOf(new.font_style) else true;
    if (reset_required) try resetStyle(writer);

    // Start the escape sequence
    try writer.writeAll(csi);
    var written_something = false;

    // Font styles
    const write_styles = if (reset_required) new.font_style else new.font_style.without(old.?.font_style);
    inline for (std.meta.fields(FontStyle)) |field| {
        if (@field(write_styles, field.name)) {
            const code = font_style_codes.get(field.name).?;
            if (written_something) {
                try writer.writeAll(";");
            } else {
                written_something = true;
            }
            try writer.writeAll(code);
        }
    }

    // Foreground color
    if (reset_required and new.foreground != .default or old != null and !old.?.foreground.eql(new.foreground)) {
        if (written_something) {
            try writer.writeAll(";");
        } else {
            written_something = true;
        }

        switch (new.foreground) {
            .default => try writer.writeAll("39"),
            .black => try writer.writeAll("30"),
            .red => try writer.writeAll("31"),
            .green => try writer.writeAll("32"),
            .yellow => try writer.writeAll("33"),
            .blue => try writer.writeAll("34"),
            .magenta => try writer.writeAll("35"),
            .cyan => try writer.writeAll("36"),
            .white => try writer.writeAll("37"),
            .fixed => |fixed| try writer.print("38;5;{}", .{fixed}),
            .grey => |grey| try writer.print("38;2;{};{};{}", .{ grey, grey, grey }),
            .rgb => |rgb| try writer.print("38;2;{};{};{}", .{ rgb.r, rgb.g, rgb.b }),
        }
    }

    // Background color
    if (reset_required and new.background != .default or old != null and !old.?.background.eql(new.background)) {
        if (written_something) {
            try writer.writeAll(";");
        } else {
            written_something = true;
        }

        switch (new.background) {
            .default => try writer.writeAll("49"),
            .black => try writer.writeAll("40"),
            .red => try writer.writeAll("41"),
            .green => try writer.writeAll("42"),
            .yellow => try writer.writeAll("43"),
            .blue => try writer.writeAll("44"),
            .magenta => try writer.writeAll("45"),
            .cyan => try writer.writeAll("46"),
            .white => try writer.writeAll("47"),
            .fixed => |fixed| try writer.print("48;5;{}", .{fixed}),
            .grey => |grey| try writer.print("48;2;{};{};{}", .{ grey, grey, grey }),
            .rgb => |rgb| try writer.print("48;2;{};{};{}", .{ rgb.r, rgb.g, rgb.b }),
        }
    }

    // End the escape sequence
    try writer.writeAll("m");
}

test "same style default, no update" {
    var buf: [1024]u8 = undefined;
    var fixed_buf_stream = fixedBufferStream(&buf);

    try updateStyle(fixed_buf_stream.writer(), Style{}, Style{});

    const expected = "";
    const actual = fixed_buf_stream.getWritten();

    try testing.expectEqualSlices(u8, expected, actual);
}

test "same style non-default, no update" {
    var buf: [1024]u8 = undefined;
    var fixed_buf_stream = fixedBufferStream(&buf);

    const sty = Style{
        .foreground = Color.green,
    };
    try updateStyle(fixed_buf_stream.writer(), sty, sty);

    const expected = "";
    const actual = fixed_buf_stream.getWritten();

    try testing.expectEqualSlices(u8, expected, actual);
}

test "reset to default, old null" {
    var buf: [1024]u8 = undefined;
    var fixed_buf_stream = fixedBufferStream(&buf);

    try updateStyle(fixed_buf_stream.writer(), Style{}, null);

    const expected = "\x1B[0m";
    const actual = fixed_buf_stream.getWritten();

    try testing.expectEqualSlices(u8, expected, actual);
}

test "reset to default, old non-null" {
    var buf: [1024]u8 = undefined;
    var fixed_buf_stream = fixedBufferStream(&buf);

    try updateStyle(fixed_buf_stream.writer(), Style{}, Style{
        .font_style = FontStyle.Bold,
    });

    const expected = "\x1B[0m";
    const actual = fixed_buf_stream.getWritten();

    try testing.expectEqualSlices(u8, expected, actual);
}

test "bold style" {
    var buf: [1024]u8 = undefined;
    var fixed_buf_stream = fixedBufferStream(&buf);

    try updateStyle(fixed_buf_stream.writer(), Style{
        .font_style = FontStyle.Bold,
    }, Style{});

    const expected = "\x1B[1m";
    const actual = fixed_buf_stream.getWritten();

    try testing.expectEqualSlices(u8, expected, actual);
}

test "add bold style" {
    var buf: [1024]u8 = undefined;
    var fixed_buf_stream = fixedBufferStream(&buf);

    try updateStyle(fixed_buf_stream.writer(), Style{
        .font_style = FontStyle{ .bold = true, .italic = true },
    }, Style{
        .font_style = FontStyle.Italic,
    });

    const expected = "\x1B[1m";
    const actual = fixed_buf_stream.getWritten();

    try testing.expectEqualSlices(u8, expected, actual);
}

test "reset required font style" {
    var buf: [1024]u8 = undefined;
    var fixed_buf_stream = fixedBufferStream(&buf);

    try updateStyle(fixed_buf_stream.writer(), Style{
        .font_style = FontStyle.Bold,
    }, Style{
        .font_style = FontStyle{ .bold = true, .underline = true },
    });

    const expected = "\x1B[0m\x1B[1m";
    const actual = fixed_buf_stream.getWritten();

    try testing.expectEqualSlices(u8, expected, actual);
}

test "reset required color style" {
    var buf: [1024]u8 = undefined;
    var fixed_buf_stream = fixedBufferStream(&buf);

    try updateStyle(fixed_buf_stream.writer(), Style{
        .foreground = Color.red,
    }, null);

    const expected = "\x1B[0m\x1B[31m";
    const actual = fixed_buf_stream.getWritten();

    try testing.expectEqualSlices(u8, expected, actual);
}

test "no reset required color style" {
    var buf: [1024]u8 = undefined;
    var fixed_buf_stream = fixedBufferStream(&buf);

    try updateStyle(fixed_buf_stream.writer(), Style{
        .foreground = Color.red,
    }, Style{});

    const expected = "\x1B[31m";
    const actual = fixed_buf_stream.getWritten();

    try testing.expectEqualSlices(u8, expected, actual);
}

test "no reset required add color style" {
    var buf: [1024]u8 = undefined;
    var fixed_buf_stream = fixedBufferStream(&buf);

    try updateStyle(fixed_buf_stream.writer(), Style{
        .foreground = Color.red,
        .background = Color.magenta,
    }, Style{
        .background = Color.magenta,
    });

    const expected = "\x1B[31m";
    const actual = fixed_buf_stream.getWritten();

    try testing.expectEqualSlices(u8, expected, actual);
}

pub fn resetStyle(writer: anytype) !void {
    try writer.writeAll(reset);
}

test "reset style" {
    var buf: [1024]u8 = undefined;
    var fixed_buf_stream = fixedBufferStream(&buf);

    try resetStyle(fixed_buf_stream.writer());

    const expected = "\x1B[0m";
    const actual = fixed_buf_stream.getWritten();

    try testing.expectEqualSlices(u8, expected, actual);
}

test "Grey foreground color" {
    var buf: [1024]u8 = undefined;
    var fixed_buf_stream = fixedBufferStream(&buf);
    var new_style = Style{};
    new_style.foreground = Color{ .grey = 1 };

    try updateStyle(fixed_buf_stream.writer(), new_style, Style{});

    const expected = "\x1B[38;2;1;1;1m";
    const actual = fixed_buf_stream.getWritten();

    try testing.expectEqualSlices(u8, expected, actual);
}

test "Grey background color" {
    var buf: [1024]u8 = undefined;
    var fixed_buf_stream = fixedBufferStream(&buf);
    var new_style = Style{};
    new_style.background = Color{ .grey = 1 };

    try updateStyle(fixed_buf_stream.writer(), new_style, Style{});

    const expected = "\x1B[48;2;1;1;1m";
    const actual = fixed_buf_stream.getWritten();

    try testing.expectEqualSlices(u8, expected, actual);
}
