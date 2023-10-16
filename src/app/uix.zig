//! Helpers and wrapper utilities built on top of the core UI framework in "ui.zig".

const std = @import("std");

const m = @import("zigkm-math");

const asset_data = @import("asset_data.zig");
const input = @import("input.zig");
const ui = @import("ui.zig");

const OOM = std.mem.Allocator.Error;

const hideBuf = [1]u8{'*'} ** 1024;

pub fn xFromAspect(y: f32, size: m.Vec2) f32
{
    return y / size.y * size.x;
}

pub fn yFromAspect(x: f32, size: m.Vec2) f32
{
    return x / size.x * size.y;
}

pub fn xFromAspectTex(y: f32, textureData: *const asset_data.TextureData) f32
{
    return xFromAspect(y, textureData.size.toVec2());
}

pub fn yFromAspectTex(x: f32, textureData: *const asset_data.TextureData) f32
{
    return yFromAspect(x, textureData.size.toVec2());
}

pub fn spacerX(hashable: anytype, uiState: anytype, size: ui.Size) OOM!void
{
    _ = try uiState.element(hashable, .{.size = .{size, .{.parentFrac = 1}}});
}

pub fn spacerY(hashable: anytype, uiState: anytype, size: ui.Size) OOM!void
{
    _ = try uiState.element(hashable, .{.size = .{.{.parentFrac = 1}, size}});
}

const ElementPadResult = struct {
    outer: *ui.Element,
    inner: *ui.Element,
};

/// Pads are, in order: left, right, top, bottom.
pub fn elementPad(hashable: anytype, uiState: anytype, topFlags: ui.ElementFlags, data: ui.ElementData, pad: [4]f32) OOM!ElementPadResult
{
    var flags = topFlags;
    flags.childrenStackX = true;
    flags.childrenStackY = true;
    const outer = try uiState.element(.{@src(), hashable}, .{
        .size = .{.{.children = {}}, .{.children = {}}},
        .flags = flags,
    });
    uiState.pushParent(outer);
    defer uiState.popParent();

    _ = try uiState.element(.{@src(), hashable}, .{
        .size = .{.{.pixels = pad[0]}, .{.pixels = pad[2]}},
    });

    const inner = try uiState.element(.{@src(), hashable}, data);

    _ = try uiState.element(.{@src(), hashable}, .{
        .size = .{.{.pixels = pad[1]}, .{.pixels = pad[3]}},
    });

    return .{.outer = outer, .inner = inner};
}

pub const MarginXView = struct {
    const Self = @This();

    pub fn init(hashable: anytype, uiState: anytype, width: f32, margin: f32) OOM!Self
    {
        const pad = try elementPad(hashable, uiState, .{}, .{
            .size = .{.{.pixels = width - margin * 2}, .{.children = {}}},
        }, [4]f32 {margin, margin, 0, 0});
        uiState.pushParent(pad.inner);

        return .{};
    }

    pub fn deinit(self: Self, uiState: anytype) OOM!void
    {
        _ = self;

        // Kind of hacky - we gotta pop twice for the inner and outer items of elementPad.
        uiState.popParent();
        uiState.popParent();
    }
};

pub const ScrollXView = struct {
    scroll: *ui.Element,

    const Self = @This();

    pub fn init(hashable: anytype, uiState: anytype, size: m.Vec2, colorsScroll: [4]m.Vec4, colorsContent: [4]m.Vec4) OOM!Self
    {
        const scroll = try uiState.element(.{@src(), hashable}, .{
            .size = .{.{.pixels = size.x}, .{.pixels = size.y}},
            .colors = colorsScroll,
            .flags = .{
                .clickable = true,
                .scrollable = true,
            },
        });
        uiState.pushParent(scroll);

        const scrollContent = try uiState.element(.{@src(), hashable}, .{
            .size = .{.{.children = {}}, .{.pixels = size.y}},
            .colors = colorsContent,
            .flags = .{
                .childrenStackX = true,
                .childrenStackY = false,
            },
        });
        uiState.pushParent(scrollContent);

        return .{.scroll = scroll};
    }

    pub fn deinit(self: Self, uiState: anytype) void
    {
        _ = self;
        uiState.popParent();
        uiState.popParent();
    }
};

pub const ScrollYView = struct {
    const Self = @This();

    const Params = struct {
        size: [2]ui.Size,
        colorsScroll: [4]m.Vec4 = .{m.Vec4.zero, m.Vec4.zero, m.Vec4.zero, m.Vec4.zero},
        colorsContent: [4]m.Vec4 = .{m.Vec4.zero, m.Vec4.zero, m.Vec4.zero, m.Vec4.zero},
    };

    pub fn init(hashable: anytype, uiState: anytype, params: Params) OOM!Self
    {
        const scroll = try uiState.element(.{@src(), hashable}, .{
            .size = params.size,
            .colors = params.colorsScroll,
            .flags = .{.scrollable = true},
        });
        uiState.pushParent(scroll);

        const scrollContent = try uiState.element(.{@src(), hashable}, .{
            .size = .{.{.parentFrac = 1}, .{.children = {}}},
            .colors = params.colorsContent,
        });
        uiState.pushParent(scrollContent);

        return .{};
    }

    pub fn deinit(self: Self, uiState: anytype) void
    {
        _ = self;
        uiState.popParent();
        uiState.popParent();
    }
};

pub const ScrollXViewSnappy = struct {
    scroll: ScrollXView,

    const Self = @This();

    pub fn init(hashable: anytype, i: *u32, n: u32, uiState: anytype, size: m.Vec2, colorsScroll: [4]m.Vec4, colorsContent: [4]m.Vec4) OOM!Self
    {
        var self = Self {
            .scroll = try ScrollXView.init(hashable, uiState, size, colorsScroll, colorsContent),
        };
        if (self.scroll.scroll.pressed) {
            const offsetX = -self.scroll.scroll.offset[0];
            const iF = (offsetX + size.x / 2) / size.x;
            i.* = @intFromFloat(iF);
            i.* = std.math.clamp(i.*, 0, n);
        } else {
            const targetOffsetX = -size.x * @as(f32, @floatFromInt(i.*));
            self.scroll.scroll.data.targetOffsetX = targetOffsetX;
            // self.scroll.scroll.offset[0] = targetOffsetX;
        }        
        return self;
    }

    pub fn deinit(self: Self, uiState: anytype) void
    {
        self.scroll.deinit(uiState);
    }
};

pub const Accordion = struct {
    src: std.builtin.SourceLocation,
    width: f32,
    open: *bool,

    const Self = @This();

    pub fn init(src: std.builtin.SourceLocation, uiState: anytype, width: f32, colorClosed: m.Vec4, colorOpen: m.Vec4, open: *bool) OOM!Self
    {
        var acc = try uiState.element(.{@src(), src}, .{
            .size = .{.{.pixels = width}, .{.children = {}}},
            .flags = .{
                .clickable = true,
            },
        });
        uiState.pushParent(acc);

        if (acc.clicked) {
            open.* = !open.*;
        }
        const color = if (open.*) colorOpen else colorClosed;
        acc.data.colors = .{color, color, color, color};

        return .{
            .src = src,
            .width = width,
            .open = open,
        };
    }

    pub fn beginContent(self: Self, uiState: anytype) OOM!void
    {
        uiState.popParent();

        const content = try uiState.element(.{@src(), self.src}, .{
            .size = .{.{.pixels = self.width}, .{.children = {}}},
            .flags = .{
                .enabled = self.open.*,
            },
        });
        uiState.pushParent(content);
    }

    pub fn deinit(self: Self, uiState: anytype) void
    {
        _ = self;
        uiState.popParent();
    }
};

const ButtonParams = struct {
    size: [2]ui.Size,
    colors: [4]m.Vec4 = .{m.Vec4.zero, m.Vec4.zero, m.Vec4.zero, m.Vec4.zero},
    cornerRadius: f32 = 0,
    depth: ?f32 = null,
    text: ?ui.ElementTextData = null,
    textureData: ?ui.ElementTextureData = null,
};

pub fn button(hashable: anytype, uiState: anytype, params: ButtonParams) OOM!bool
{
    var element = try uiState.element(hashable, .{
        .size = params.size,
        .flags = .{.clickable = true},
        .colors = params.colors,
        .cornerRadius = params.cornerRadius,
        .text = params.text,
        .textureData = params.textureData,
    });
    if (params.depth) |d| {
        element.data.depth = d;
    }
    return element.clicked;
}

/// Helper type for managing textInput buffers.
pub fn TextInput(comptime size: u32) type
{
    const Buf = struct {
        buf: [size]u8 = [_]u8{0} ** size,

        const Self = @This();

        pub fn slice(self: *const Self) []const u8
        {
            const len = std.mem.indexOfScalar(u8, &self.buf, 0) orelse self.buf.len;
            return self.buf[0..len];
        }
    };
    return Buf;
}

pub const TextInputParams = struct {
    textBuf: []u8,
    fontData: *const asset_data.FontData,
    alignX: ui.TextAlignX = .left,
    alignY: ui.TextAlignY = .center,
    textColor: m.Vec4,
    size: [2]ui.Size,
    colors: [4]m.Vec4,
    colorsActive: [4]m.Vec4,
    depth: ?f32 = null,
    cornerRadius: f32 = 0,
    hide: bool = false, // for sensitive inputs, like password fields
};

pub const TextInputResult = struct {
    element: *ui.Element,
    changed: bool,
    enter: bool,
    tab: bool,
};

pub fn textInput(hashable: anytype, uiState: anytype, inputState: *const input.InputState, params: TextInputParams) OOM!TextInputResult
{
    var result = TextInputResult {
        .element = undefined,
        .changed = false,
        .enter = false,
        .tab = false,
    };

    var element = try uiState.element(.{@src(), hashable}, .{
        .size = params.size,
        .flags = .{.clickable = true, .opensKeyboard = true},
        .colors = params.colors,
        .cornerRadius = params.cornerRadius,
    });
    result.element = element;
    if (params.depth) |d| {
        element.data.depth = d;
    }

    const textEnd = std.mem.indexOfScalar(u8, params.textBuf, 0) orelse params.textBuf.len;
    var newTextEnd = textEnd;
    if (uiState.active == element) {
        element.data.colors = params.colorsActive;
        for (inputState.keyboardState.utf32.slice()) |u| {
            std.debug.assert(u <= std.math.maxInt(u8));
            const ascii: u8 = @intCast(u);
            switch (ascii) {
                8 => {
                    if (newTextEnd > 0) {
                        newTextEnd -= 1;
                        params.textBuf[newTextEnd] = 0;
                        result.changed = true;
                    }
                },
                9 => {
                    result.tab = true;
                },
                10, 13 => {
                    result.enter = true;
                },
                else => {
                    if (newTextEnd < params.textBuf.len) {
                        params.textBuf[newTextEnd] = ascii;
                        newTextEnd += 1;
                        result.changed = true;
                    }
                }
            }
        }
    }

    std.debug.assert(newTextEnd <= hideBuf.len);
    const buf = if (params.hide) hideBuf[0..newTextEnd] else params.textBuf[0..newTextEnd];
    element.data.text = .{
        .text = buf,
        .fontData = params.fontData,
        .alignX = params.alignX,
        .alignY = params.alignY,
        .color = params.textColor,
    };

    return result;
}

const TestSetup = struct {
    const stateSize = 1024 * 1024;

    arena: std.heap.ArenaAllocator,
    uiState: *ui.State(stateSize),
    inputState: *input.InputState,

    const Self = @This();

    fn init() !Self
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        const allocator = arena.allocator();

        var uiState = try allocator.create(ui.State(stateSize));
        uiState.clear();

        var inputState = try allocator.create(input.InputState);
        inputState.clear();

        uiState.prepare(inputState, m.Vec2.zero, 0, allocator);

        return .{
            .arena = arena,
            .uiState = uiState,
            .inputState = inputState,
        };
    }

    fn deinit(self: *Self) void
    {
        self.arena.deinit();
    }
};

const TestExpected = struct {
    pos: ?[2]f32 = null,
    size: ?[2]f32 = null,
};

fn checkExpected(expected: []const TestExpected, elements: []ui.Element) !void
{
    try std.testing.expectEqual(expected.len, elements.len);
    for (expected, 0..) |e, i| {
        if (e.pos) |p| try std.testing.expectEqual(p, elements[i].pos);
        if (e.size) |s| try std.testing.expectEqual(s, elements[i].size);
    }
}

test "elementPad"
{
    var testSetup = try TestSetup.init();
    defer testSetup.deinit();
    const allocator = testSetup.arena.allocator();
    const uiState = testSetup.uiState;

    _ = try elementPad(@src(), uiState, .{}, .{
        .size = .{.{.pixels = 100}, .{.pixels = 50}},
    }, [_]f32 {20, 10, 7, 8});

    const expected = [_]TestExpected {
        .{.pos = .{0, 0}, .size = .{130, 65}},
        .{.pos = .{0, 0}, .size = .{130, 65}},
        .{.pos = .{0, 0}, .size = .{20, 7}},
        .{.pos = .{20, 7}, .size = .{100, 50}},
        .{.pos = .{120, 57}, .size = .{10, 8}},
    };

    try uiState.layout(allocator);
    try checkExpected(&expected, uiState.elements.slice());
}

test "margin"
{
    var testSetup = try TestSetup.init();
    defer testSetup.deinit();
    const allocator = testSetup.arena.allocator();
    const uiState = testSetup.uiState;

    {
        const width = 100;
        const margin = 20;
        const view = try MarginXView.init(@src(), uiState, width, margin);
        defer view.deinit(uiState) catch {};

        try spacerY(@src(), uiState, .{.pixels = 400});
    }

    const expected = [_]TestExpected {
        .{.pos = .{0, 0}, .size = .{100, 400}},
        .{.pos = .{0, 0}, .size = .{100, 400}},
        .{.pos = .{0, 0}, .size = .{20, 0}},
        .{.pos = .{20, 0}, .size = .{60, 400}},
        .{.pos = .{80, 400}, .size = .{20, 0}},
        .{.pos = .{20, 0}, .size = .{60, 400}},
    };

    try uiState.layout(allocator);
    try checkExpected(&expected, uiState.elements.slice());
}
