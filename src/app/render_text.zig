const std = @import("std");
const A = std.mem.Allocator;

const kb = @import("zigkm-kb");
const m = @import("zigkm-math");

const assets = @import("assets.zig");
const render = @import("render.zig");

pub fn textRect(utf8: []const u8, fontData: *const assets.FontData, width: ?f32) m.Rect
{
    var min = m.Vec2.zero;
    var max = m.Vec2.zero;
    var glyphIt = GlyphIterator.init(utf8, fontData, width);
    while (glyphIt.next()) |gr| {
        min.x = @min(min.x, gr.position.x);
        max.x = @max(max.x, gr.position.x + gr.size.x);
        min.y = @min(min.y, gr.position.y);
        max.y = @max(max.y, gr.position.y + gr.size.y);
    }

    return m.Rect.init(min, max);
}

const GlyphResult = struct {
    position: m.Vec2,
    size: m.Vec2,
    uvOffset: m.Vec2,
    uvSize: m.Vec2,
};

pub fn utf8ToGlyphs(utf8: []const u8, fontData: *const assets.FontData, width: ?f32, a: A) []GlyphResult
{
    _ = width;
    // var cursor = std.mem.zeroes(kb.kbts_cursor);
    // var direction = kb.KBTS_DIRECTION_NONE;
    // var script = kb.KBTS_SCRIPT_DONT_KNOW;
    // var runStart = 0;
    // var breakState: kb.kbts_break_state = undefined;
    // kb.kbts_BeginBreak(&breakState, kb.KBTS_DIRECTION_NONE, kb.KBTS_JAPANESE_LINE_BREAK_STYLE_NORMAL);

    // var codepoints = std.ArrayListUnmanaged(u32) {};
    // var utf8It = std.unicode.Utf8Iterator {
    //     .bytes = utf8,
    //     .i = 0,
    // };
    // while (utf8It.nextCodepoint()) |c| {
    //     codepoints.append(a, c) catch break;
    // }

    // var glyphs = std.ArrayListUnmanaged(GlyphResult) {};
    // for (codepoints.items, 0..) |c, i| {
    //     kb.kbts_BreakAddCodepoint(&breakState, c, 1, i + 1 == codepoints.len);
    //     var kbBreak: kb.kbts_break = undefined;
    //     while (kb.kbts_Break(&breakState, &kbBreak) != 0) {
    //         if ((kbBreak.Position > runStart) and (kbBreak.Flags & (kb.KBTS_BREAK_FLAG_DIRECTION | kb.KBTS_BREAK_FLAG_SCRIPT | kb.KBTS_BREAK_FLAG_LINE_HARD))) {
    //             const runLength = kbBreak.Position - runStart;
    //             shapeText(&cursor, codepoints[runStart..runStart + runLength], breakState.MainDirection, direction, script, &glyphs, a);
    //             runStart = kbBreak.Position;
    //         }

    //         if (kbBreak.Flags & kb.KBTS_BREAK_FLAG_DIRECTION) {
    //             direction = kbBreak.Direction;
    //             if (cursor.Direction == 0) {
    //                 cursor = kb.kbts_Cursor(breakState.MainDirection);
    //             }
    //         }
    //         if (kbBreak.Flags & kb.KBTS_BREAK_FLAG_SCRIPT) {
    //             script = kbBreak.Script;
    //         }
    //     }
    // }
    // return glyphs.items;

    // std.log.info("shaping utf-8 {s}", .{utf8});

    var glyphs = std.ArrayListUnmanaged(GlyphResult) {};

    var kbGlyphs = a.alloc(kb.kbts_glyph, utf8.len) catch return &.{};
    var kbGlyphCount: u32 = 0;
    var kbScript: kb.kbts_script = kb.KBTS_SCRIPT_DONT_KNOW;
    var kbDirection: kb.kbts_direction = kb.KBTS_DIRECTION_NONE;
    var utf8It = std.unicode.Utf8Iterator {
        .bytes = utf8,
        .i = 0,
    };
    while (utf8It.nextCodepoint()) |c| {
        const kbGlyph = kb.kbts_CodepointToGlyph(@constCast(&fontData.kbFont), c);
        // std.log.info("{} -> {} {}", .{c, kbGlyph.Id, kbGlyph.Uid});
        kb.kbts_InferScript(&kbDirection, &kbScript, kbGlyph.Script);
        kbGlyphs[kbGlyphCount] = kbGlyph;
        kbGlyphCount += 1;
    }

    const shapeStateSize = kb.kbts_SizeOfShapeState(@constCast(&fontData.kbFont));
    const shapeStateBytes = a.alloc(u8, @intCast(shapeStateSize)) catch return &.{};
    const shapeState = kb.kbts_PlaceShapeState(shapeStateBytes.ptr, shapeStateSize);
    var shapeConfig = kb.kbts_ShapeConfig(@constCast(&fontData.kbFont), kbScript, kb.KBTS_LANGUAGE_DONT_KNOW);
    while (kb.kbts_Shape(shapeState, &shapeConfig, kbDirection, kbDirection, kbGlyphs.ptr, &kbGlyphCount, kbGlyphs.len) != 0) {
        std.log.err("REALLOC", .{});
        kbGlyphs = a.realloc(kbGlyphs, shapeState.*.RequiredGlyphCapacity) catch return &.{};
    }

    var kbCursor = kb.kbts_Cursor(kbDirection);
    for (kbGlyphs[0..kbGlyphCount]) |*g| {
        var x: c_int = undefined;
        var y: c_int = undefined;
        kb.kbts_PositionGlyph(&kbCursor, g, &x, &y);
        // std.log.info("{} {} | {} {}", .{x, y, g.Id, g.Uid});

        const charData = if (g.Id < fontData.charData.len) fontData.charData[g.Id] else fontData.charData[0];
        const atlasSize = fontData.atlasData.size.toVec2();
        const uvSize = m.Vec2.init(charData.size.x / atlasSize.x, charData.size.y / atlasSize.y);
        const xF: f32 = @floatFromInt(x >> 16);
        const yF: f32 = @floatFromInt(y >> 16);
        glyphs.append(a, .{
            .position = m.Vec2.init(xF, yF),
            .size = m.multScalar(charData.size, fontData.scale),
            .uvOffset = charData.uvOffset,
            .uvSize = uvSize,
        }) catch return &.{};
    }

    return glyphs.items;
}

pub const GlyphIterator = struct {
    utf8It: std.unicode.Utf8Iterator,
    pos: m.Vec2,
    fontData: *const assets.FontData,
    width: ?f32,

    const Self = @This();

    pub fn init(utf8: []const u8, fontData: *const assets.FontData, width: ?f32) Self
    {
        return .{
            .utf8It = .{
                .bytes = utf8,
                .i = 0,
            },
            .pos = m.Vec2.zero,
            .fontData = fontData,
            .width = width,
        };
    }

    pub fn next(self: *Self) ?GlyphResult
    {
        const codepoint = self.utf8It.nextCodepoint() orelse return null;
        const result = glyph(codepoint, &self.pos, self.fontData);

        if (self.width) |w| {
            if (isWordSeparator(codepoint) and self.utf8It.i < self.utf8It.bytes.len) {
                var utf8ItCopy = self.utf8It;
                var iWordEnd = utf8ItCopy.i;
                while (utf8ItCopy.nextCodepoint()) |c| {
                    if (isWordSeparator(c)) {
                        break;
                    }
                    iWordEnd = utf8ItCopy.i;
                }
                const wordUtf8 = self.utf8It.bytes[self.utf8It.i..iWordEnd];
                if (wordUtf8.len > 0) {
                    const wordRect = textRect(wordUtf8, self.fontData, null);
                    if (self.pos.x + wordRect.size().x > w) {
                        self.pos.x = 0;
                        self.pos.y -= self.fontData.lineHeight;
                    }
                }
            }
        }

        return result;
    }
};

fn glyph(c: u32, pos: *m.Vec2, fontData: *const assets.FontData) GlyphResult
{
    if (c == '\n') {
        pos.y -= fontData.lineHeight;
        pos.x = 0;
        return .{
            .position = m.Vec2.zero,
            .size = m.Vec2.zero,
            .uvOffset = m.Vec2.zero,
            .uvSize = m.Vec2.zero,
        };
    } else {
        const charData = if (c < fontData.charData.len) fontData.charData[c] else fontData.charData[0];
        const prevPos = pos.*;
        // TODO better kerning?
        pos.x += charData.advanceX * fontData.scale + fontData.kerning;
        const atlasSize = fontData.atlasData.size.toVec2();
        const uvSize = m.Vec2.init(charData.size.x / atlasSize.x, charData.size.y / atlasSize.y);
        return .{
            .position = m.add(prevPos, m.multScalar(charData.offset, fontData.scale)),
            .size = m.multScalar(charData.size, fontData.scale),
            .uvOffset = charData.uvOffset,
            .uvSize = uvSize
        };
    }
}

fn isWordSeparator(c: u32) bool
{
    if (c >= 256) return false;
    return std.ascii.isWhitespace(@intCast(c));
}
