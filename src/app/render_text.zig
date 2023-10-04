const std = @import("std");

const m = @import("zigkm-math");

const asset_data = @import("asset_data.zig");
const render = @import("render.zig");

pub const TextRenderBuffer = struct {
    allocator: std.mem.Allocator,
    capacity: usize,
    positions: []m.Vec2,
    sizes: []m.Vec2,
    uvOffsets: []m.Vec2,

    const Self = @This();

    pub fn init(capacity: usize, allocator: std.mem.Allocator) !Self
    {
        return .{
            .allocator = allocator,
            .capacity = capacity,
            .positions = try allocator.alloc(m.Vec2, capacity),
            .sizes = try allocator.alloc(m.Vec2, capacity),
            .uvOffsets = try allocator.alloc(m.Vec2, capacity),
        };
    }

    pub fn deinit(self: *Self) void
    {
        self.allocator.free(self.positions);
        self.allocator.free(self.sizes);
        self.allocator.free(self.uvOffsets);
    }

    pub fn fill(self: *Self, text: []const u8, baselineLeft: m.Vec2, fontData: *const asset_data.FontData, width: ?f32) usize
    {
        var i: usize = 0;
        var glyphIt = GlyphIterator.init(text, fontData, width);
        while (glyphIt.next()) |gr| {
            if (i >= self.capacity) {
                break;
            }

            self.positions[i] = m.add(gr.position, baselineLeft);
            self.sizes[i] = gr.size;
            self.uvOffsets[i] = gr.uvOffset;
            i += 1;
        }

        return i;
    }
};

pub fn textRect(text: []const u8, fontData: *const asset_data.FontData, width: ?f32) m.Rect
{
    var min = m.Vec2.zero;
    var max = m.Vec2.zero;
    var glyphIt = GlyphIterator.init(text, fontData, width);
    while (glyphIt.next()) |gr| {
        min.x = @min(min.x, gr.position.x);
        max.x = @max(max.x, gr.position.x + gr.size.x);
        min.y = @min(min.y, gr.position.y);
        max.y = @max(max.y, gr.position.y + gr.size.y);
    }

    return m.Rect.init(min, max);
}

const GlyphIterator = struct {
    i: usize,
    pos: m.Vec2,
    text: []const u8,
    fontData: *const asset_data.FontData,
    width: ?f32,

    const Self = @This();

    fn init(text: []const u8, fontData: *const asset_data.FontData, width: ?f32) Self
    {
        return .{
            .i = 0,
            .pos = m.Vec2.zero,
            .text = text,
            .fontData = fontData,
            .width = width,
        };
    }

    fn next(self: *Self) ?GlyphResult
    {
        if (self.i >= self.text.len) {
            return null;
        }

        const char = self.text[self.i];
        self.i += 1;
        const result = glyph(char, &self.pos, self.fontData);

        if (self.width) |w| {
            if (char == ' ' and self.i < self.text.len) {
                const wordEnd = std.mem.indexOfScalarPos(u8, self.text, self.i, ' ') orelse self.text.len;
                const word = self.text[self.i..wordEnd];
                if (word.len > 0) {
                    const wordRect = textRect(word, self.fontData, null);
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

const GlyphResult = struct {
    position: m.Vec2,
    size: m.Vec2,
    uvOffset: m.Vec2,
};

fn glyph(c: u32, pos: *m.Vec2, fontData: *const asset_data.FontData) GlyphResult
{
    if (c == '\n') {
        pos.y -= fontData.lineHeight;
        pos.x = 0;
        return .{
            .position = m.Vec2.zero,
            .size = m.Vec2.zero,
            .uvOffset = m.Vec2.zero,
        };
    } else {
        const charData = fontData.charData[c];
        const prevPos = pos.*;
        // TODO better kerning?
        pos.x += charData.advanceX * fontData.scale + fontData.kerning;
        return .{
            .position = m.add(prevPos, m.multScalar(charData.offset, fontData.scale)),
            .size = m.multScalar(charData.size, fontData.scale),
            .uvOffset = charData.uvOffset,
        };
    }
}
