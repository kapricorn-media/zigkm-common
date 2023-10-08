const std = @import("std");

const m = @import("zigkm-math");

const asset_data = @import("asset_data.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const tree = @import("tree.zig");

pub fn State(comptime maxMemory: usize) type
{
    const maxElements = maxMemory / @sizeOf(Element);
    if (maxElements == 0) {
        unreachable;
    }

    const S = struct {
        elements: std.BoundedArray(Element, maxElements),
        parent: *Element,
        active: ?*Element,
        screenSize: m.Vec2,
        frame: u64,

        const Self = @This();

        fn findElementWithHash(self: *Self, hash: u64) ?*Element
        {
            for (self.elements.slice()) |*e| {
                if (e.hash == hash) {
                    return e;
                }
            }
            return null;
        }

        pub fn clear(self: *Self) void
        {
            self.elements.len = 1;

            // add root and set as parent
            std.debug.assert(self.elements.buffer.len > 0);
            self.elements.buffer[0] = .{
                .firstChild = &self.elements.buffer[0],
                .lastChild = &self.elements.buffer[0],
                .nextSibling = &self.elements.buffer[0],
                .prevSibling = &self.elements.buffer[0],
                .parent = &self.elements.buffer[0],

                .hash = 0,
                .lastFrameTouched = 0,

                .data = .{
                    .size = .{.{.children = {}}, .{.children = {}}},
                },
                .pos = .{0, 0},
                .offset = .{0, 0},
                .size = .{0, 0},
                .hover = false,
                .clicked = false,
                .scrollVelY = 0,
            };
            self.parent = &self.elements.buffer[0];
            self.active = null;
            self.frame = 0;

            input.setSoftwareKeyboardVisible(false);
        }

        pub fn prepare(self: *Self, inputState: *const input.InputState, screenSize: m.Vec2, tempAllocator: std.mem.Allocator) void
        {
            self.screenSize = screenSize;

            var treeIt = tree.TreeIterator(Element).init(tempAllocator);
            {
                // UI interactions based on current frame's input and last frame's layout.
                for (self.elements.slice()) |*e| {
                    e.hover = false;
                    e.clicked = false;
                }

                var root = &self.elements.slice()[0];
                const mousePosF = inputState.mouseState.pos.toVec2();

                treeIt.prepare(root, .PostOrder) catch return;
                while (treeIt.next() catch return) |e| {
                    if (!isEnabled(e) or (!e.data.flags.clickable and !e.data.flags.scrollable)) {
                        continue;
                    }

                    const pos = getElementRenderPos(e, screenSize);
                    const size = m.Vec2.init(e.size[0], e.size[1]);
                    const rect = m.Rect.initOriginSize(pos, size);
                    const maxScrollY = getMaxScrollY(e);
                    switch (inputState.pointerSource) {
                        .Mouse => {
                            if (m.isInsideRect(mousePosF, rect)) {
                                e.hover = true;
                                if (e.data.flags.clickable) {
                                    for (inputState.mouseState.clickEvents.slice()) |c| {
                                        const cPos = c.pos.toVec2();
                                        if (c.clickType == .Left and c.down and m.isInsideRect(cPos, rect)) {
                                            e.clicked = true;
                                            self.active = e;
                                            break;
                                        }
                                    }
                                }
                                if (e.data.flags.scrollable) {
                                    e.offset[1] += @floatFromInt(inputState.mouseState.wheelDelta.y);
                                    e.offset[1] = std.math.clamp(e.offset[1], 0, maxScrollY);
                                }
                            }
                        },
                        .Touch => {
                            if (e.data.flags.clickable) {
                                for (inputState.touchState.activeTouches.slice()) |t| {
                                    const tPos = t.getPos().toVec2();
                                    if (t.ending and t.isTap() and m.isInsideRect(tPos, rect)) {
                                        e.clicked = true;
                                        self.active = e;
                                        break;
                                    }
                                }
                            }
                            if (e.data.flags.scrollable) {
                                for (inputState.touchState.activeTouches.slice()) |t| {
                                    const tPrevPos = (t.getPrevPos() orelse continue).toVec2();
                                    const tPosStart = t.posStart.toVec2();
                                    if (m.isInsideRect(tPosStart, rect)) {
                                        if (t.ending) {
                                            const meanVel = t.getWeightedVel();
                                            e.scrollVelY = meanVel.y;
                                        } else {
                                            e.scrollVelY = 0;
                                            const tPos = t.getPos().toVec2();
                                            e.offset[1] += tPos.y - tPrevPos.y;
                                            e.offset[1] = std.math.clamp(e.offset[1], 0, maxScrollY);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Unset active element on unrelated clicks/taps.
            // Also, show or hide the software keyboard accordingly.
            if (inputState.mouseState.anyClick(.Left) or inputState.touchState.anyTap()) {
                if (self.active) |a| {
                    if (!a.clicked) {
                        input.setSoftwareKeyboardVisible(false);
                        self.active = null;
                    } else if (a.data.flags.opensKeyboard) {
                        input.setSoftwareKeyboardVisible(true);
                    }
                }
            }

            for (self.elements.slice()) |*e| {
                if (!isEnabled(e) or !e.data.flags.scrollable) continue;

                const maxScrollY = getMaxScrollY(e);
                e.offset[1] += e.scrollVelY;
                if (e.offset[1] < 0) {
                    e.offset[1] = 0;
                    e.scrollVelY = 0;
                } else if (e.offset[1] > maxScrollY) {
                    e.offset[1] = maxScrollY;
                    e.scrollVelY = 0;
                }

                // TODO tweak, probably try to make FPS-independent
                const deccelerationFactor = 0.95;
                const speedTolerance = 0.1;
                e.scrollVelY *= deccelerationFactor;
                if (std.math.approxEqAbs(f32, e.scrollVelY, 0.0, speedTolerance)) {
                    e.scrollVelY = 0.0;
                }
            }

            self.frame += 1;

            self.parent = &self.elements.buffer[0];
            for (self.elements.slice()) |*e| {
                e.parent = e;
                e.firstChild = e;
                e.lastChild = e;
                e.nextSibling = e;
                e.prevSibling = e;
            }
        }

        pub fn pushParent(self: *Self, e: *Element) void
        {
            self.parent = e;
        }

        pub fn popParent(self: *Self) void
        {
            std.debug.assert(self.parent.parent != self.parent);
            self.parent = self.parent.parent;
        }

        pub fn elementWithHash(self: *Self, hash: u64, data: ElementData) ?*Element
        {
            var new = false;
            var e = blk: {
                if (self.findElementWithHash(hash)) |e| {
                    break :blk e;
                }

                const e = self.elements.addOne() catch {
                    std.log.warn("No space for elements", .{});
                    return null;
                };
                new = true;
                break :blk e;
            };

            if (!new and e.lastFrameTouched == self.frame) {
                // Not new and touched this frame - we might have a hashing bug in builder code.
                unreachable;
            }
            if (data.size[1] == .text and data.size[0] != .text and data.size[0] != .pixels) {
                // We only support text sizes with other parent/child-independent sizes.
                unreachable;
            }

            e.parent = self.parent;
            if (self.parent.firstChild == self.parent) {
                // parent has no children yet
                self.parent.firstChild = e;
                self.parent.lastChild = e;
            }
            e.firstChild = e;
            e.lastChild = e;
            e.nextSibling = e;
            e.prevSibling = self.parent.lastChild;
            self.parent.lastChild.nextSibling = e;
            self.parent.lastChild = e;

            e.hash = hash;
            e.lastFrameTouched = self.frame;

            e.data = data;

            if (new) {
                e.pos = .{0, 0};
                e.offset = .{0, 0};
                e.size = .{0, 0};
                e.hover = false;
                e.clicked = false;
                e.scrollVelY = 0;
            }

            return e;
        }

        pub fn element(self: *Self, src: std.builtin.SourceLocation, data: ElementData) ?*Element
        {
            const hash = srcToHash(src);
            return self.elementWithHash(hash, data);
        }

        pub fn elementX(self: *Self, hashable: anytype, data: ElementData) ?*Element
        {
            var hasher = std.hash.Wyhash.init(0);
            std.hash.autoHashStrat(&hasher, hashable, .Shallow);
            return self.elementWithHash(hasher.final(), data);
        }

        fn layoutWithTreeIt(self: *Self, treeIt: *tree.TreeIterator(Element)) !void
        {
            { // trim outdated elements
                var i: usize = 1;
                while (i < self.elements.len) {
                    const e = &self.elements.buffer[i];
                    if (e.lastFrameTouched != self.frame) {
                        self.elements.buffer[i] = self.elements.buffer[self.elements.len - 1];
                        self.elements.len -= 1;
                        continue;
                    }
                    i += 1;
                }
            }

            // Calculate independent sizes
            for (self.elements.slice()) |*e| {
                var textSize = [2]f32 {0, 0};
                if (e.data.text) |t| {
                    const maxWidth = switch (e.data.size[0]) {
                        .pixels => |v| v,
                        else => null,
                    };
                    const textRect = render.textRect(t.text, t.fontData, maxWidth);
                    const textSizeVec = textRect.size();
                    textSize[0] = textSizeVec.x;
                    textSize[1] = textSizeVec.y;
                }
                inline for (0..2) |axis| {
                    switch (e.data.size[axis]) {
                        .pixels => |v| {
                            e.size[axis] = v;
                        },
                        .text => {
                            e.size[axis] = textSize[axis];
                        },
                        .parentFrac, .children => {},
                    }
                }
            }

            var root = &self.elements.slice()[0];

            // Calculate upward-dependent sizes, except for .parentFrac -> .children
            try treeIt.prepare(root, .PreOrder);
            while (try treeIt.next()) |e| {
                if (e != e.parent) {
                    inline for (0..2) |axis| {
                        if (e.data.size[axis] == .parentFrac and e.parent.data.size[axis] != .children) {
                            e.size[axis] = e.parent.size[axis] * e.data.size[axis].parentFrac;
                        }
                    }
                }
            }

            // Calculate downward-dependent sizes
            try treeIt.prepare(root, .PostOrder);
            while (try treeIt.next()) |e| {
                if (e.firstChild != e) {
                    inline for (0..2) |axis| {
                        if (e.data.size[axis] == .children) {
                            e.size[axis] = getChildrenSize(e, axis);
                        }
                    }
                }
            }

            // Calculate upward-dependent sizes, for .parentFrac -> .children
            try treeIt.prepare(root, .PreOrder);
            while (try treeIt.next()) |e| {
                if (e != e.parent) {
                    inline for (0..2) |axis| {
                        if (e.data.size[axis] == .parentFrac and e.parent.data.size[axis] == .children) {
                            e.size[axis] = e.parent.size[axis] * e.data.size[axis].parentFrac;
                        }
                    }
                }
            }

            // Calculate positions
            try treeIt.prepare(root, .PreOrder);
            root.pos[0] = 0;
            root.pos[1] = 0;
            while (try treeIt.next()) |e| {
                if (!isEnabled(e)) continue;

                var pos = e.parent.pos;
                // TODO it's weird that these are -= instead of +=
                pos[0] -= e.parent.offset[0];
                pos[1] -= e.parent.offset[1];
                if (findFirstEnabledPrev(e)) |prev| {
                    inline for (0..2) |axis| {
                        const stack = getStack(e.parent.data.flags, axis);
                        const float = getFloat(e.data.flags, axis);
                        if (stack and !float) {
                            pos[axis] = prev.pos[axis];
                            pos[axis] += prev.size[axis];
                        }
                        // if (getCenter(e.data.flags, axis)) {
                        //     pos[axis] += e.parent.size[axis] / 2;
                        //     pos[axis] -= e.size[axis] / 2;
                        // }
                    }
                }
                e.pos = pos;
            }
        }

        pub fn layout(self: *Self, tempAllocator: std.mem.Allocator) !void
        {
            var treeIt = tree.TreeIterator(Element).init(tempAllocator);
            try self.layoutWithTreeIt(&treeIt);
        }

        pub fn layoutAndDraw(self: *Self, renderState: *render.RenderState, tempAllocator: std.mem.Allocator) !void
        {
            var treeIt = tree.TreeIterator(Element).init(tempAllocator);
            const root = &self.elements.slice()[0];
            try self.layoutWithTreeIt(&treeIt);

            var renderQueue = try tempAllocator.create(render.RenderQueue);
            renderQueue.clear();

            // Calculate render positions and draw
            try treeIt.prepare(root, .PreOrder);
            while (try treeIt.next()) |e| {
                if (!isEnabled(e)) continue;

                const size = m.Vec2.init(e.size[0], e.size[1]);
                const pos = getElementRenderPos(e, self.screenSize);
                const depth = e.data.depth;
                var renderQuad = false;
                inline for (0..4) |i| {
                    renderQuad = renderQuad or !m.eql(e.data.colors[i], m.Vec4.zero);
                }
                if (renderQuad) {
                    if (e.data.textureData) |tex| {
                        renderQueue.texQuad(pos, size, depth, e.data.cornerRadius, tex);
                    } else {
                        renderQueue.quadGradient(pos, size, depth, e.data.cornerRadius, e.data.colors);
                    }
                }
                if (e.data.text) |t| {
                    const textPosX = blk: {
                        switch (t.alignX) {
                            .left => break :blk pos.x,
                            .center => {
                                const textRect = render.textRect(t.text, t.fontData, null);
                                break :blk pos.x + size.x / 2 - textRect.size().x / 2;
                            },
                            .right => {
                                const textRect = render.textRect(t.text, t.fontData, null);
                                break :blk pos.x + size.x - textRect.size().x;
                            },
                        }
                    };
                    const textPosY = blk: {
                        switch (t.alignY) {
                            .top => break :blk pos.y + e.size[1] - t.fontData.ascent,
                            .center => {
                                const textRect = render.textRect(t.text, t.fontData, null);
                                break :blk pos.y + (e.size[1] - textRect.size().y) / 2;
                            },
                            .bottom => break :blk pos.y,
                        }
                    };
                    const textPos = m.Vec2.init(textPosX, textPosY);
                    const maxWidth = blk: {
                        switch (e.data.size[0]) {
                            .text => break :blk null,
                            else => break :blk e.size[0],
                        }
                    };
                    renderQueue.textWithMaxWidth(t.text, textPos, depth, maxWidth, t.fontData, t.color);
                }
            }

            renderQueue.render(renderState, self.screenSize, tempAllocator);
        }
    };
    return S;
}

pub const SizeKind = enum {
    pixels,
    parentFrac,
    text,
    children,
};

pub const Size = union(SizeKind) {
    pixels: f32,
    parentFrac: f32,
    text: void,
    children: void,
};

pub const ElementFlags = packed struct {
    // layout
    enabled: bool = true,
    floatX: bool = false,
    floatY: bool = false,
    overflowX: bool = false,
    overflowY: bool = false,
    // centerX: bool = false,
    // centerY: bool = false,
    childrenStackX: bool = false,
    childrenStackY: bool = true,

    // interaction
    clickable: bool = false,
    scrollable: bool = false,
    opensKeyboard: bool = false,
};

pub const TextAlignX = enum {
    left,
    center,
    right,
};

pub const TextAlignY = enum {
    top,
    center,
    bottom,
};

pub const ElementTextData = struct {
    text: []const u8,
    fontData: *const asset_data.FontData,
    alignX: TextAlignX = .left,
    alignY: TextAlignY = .top,
    color: m.Vec4,
};

pub const ElementData = struct {
    size: [2]Size,
    flags: ElementFlags = .{},
    colors: [4]m.Vec4 = .{
        m.Vec4.zero, m.Vec4.zero, m.Vec4.zero, m.Vec4.zero
    },
    depth: f32 = 0.5,
    cornerRadius: f32 = 0,
    text: ?ElementTextData = null,
    textureData: ?*const asset_data.TextureData = null,
};

pub const Element = struct {
    // tree
    firstChild: *Self,
    lastChild: *Self,
    nextSibling: *Self,
    prevSibling: *Self,
    parent: *Self,

    // hash
    hash: u64,
    lastFrameTouched: u64,

    // data
    // Supplied by UI usage code every frame.
    data: ElementData,

    // Computed at the end of the frame, will "lag" by 1 frame.
    pos: [2]f32,
    offset: [2]f32,
    size: [2]f32,
    // Computed at the start of the frame, based on previous frame's data.
    hover: bool,
    clicked: bool,
    scrollVelY: f32,

    const Self = @This();
};

pub fn srcToHash(src: std.builtin.SourceLocation) u64
{
    var hasher = std.hash.Wyhash.init(0);
    std.hash.autoHashStrat(&hasher, src.file, .Shallow);
    std.hash.autoHashStrat(&hasher, src.fn_name, .Shallow);
    std.hash.autoHashStrat(&hasher, src.line, .Shallow);
    std.hash.autoHashStrat(&hasher, src.column, .Shallow);
    return hasher.final();
}

fn getFloat(flags: ElementFlags, comptime axis: comptime_int) bool
{
    return if (axis == 0) flags.floatX else flags.floatY;
}

fn getStack(flags: ElementFlags, comptime axis: comptime_int) bool
{
    return if (axis == 0) flags.childrenStackX else flags.childrenStackY;
}

// fn getCenter(flags: ElementFlags, comptime axis: comptime_int) bool
// {
//     return if (axis == 0) flags.centerX else flags.centerY;
// }

fn getElementRenderPos(e: *Element, screenSize: m.Vec2) m.Vec2
{
    return m.Vec2.init(e.pos[0], screenSize.y - e.pos[1] - e.size[1]);
}

fn getChildrenSize(e: *Element, comptime axis: comptime_int) f32
{
    var size: f32 = 0;

    const stack = getStack(e.data.flags, axis);
    var child = e.firstChild;
    while (true) : (child = child.nextSibling) {
        const flags = child.data.flags;
        if (!flags.enabled) continue;

        const float = getFloat(flags, axis);
        if (float or !stack) {
            size = @max(size, child.size[axis]);
        } else {
            size += child.size[axis];
        }

        if (child.nextSibling == child) {
            break;
        }
    }
    return size;
}

fn findFirstEnabledPrev(e: *Element) ?*Element
{
    var ee = e;
    while (true) {
        const prev = ee.prevSibling;
        if (prev == ee) {
            return null;
        }
        if (prev.data.flags.enabled) {
            return prev;
        }
        ee = prev;
    }
}

/// Checks if e and all its parents are enabled.
fn isEnabled(e: *Element) bool
{
    var ee = e;
    while (true) {
        if (!ee.data.flags.enabled) {
            return false;
        }
        ee = ee.parent;
        if (ee == ee.parent) {
            return true;
        }
    }
}

fn getMaxScrollY(e: *Element) f32
{
    return @max(getChildrenSize(e, 1) - e.size[1], 0);
}

test "layout"
{
    // All allocations done by these functions are temporary and don't free,
    // so memory leaks are expected. Use an arena to catch them all and free in bulk.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const screenSize = m.Vec2.init(500, 400);
    const marginX = 50;
    const centerSize = screenSize.x - marginX * 2;

    const size = 512 * 1024;
    var uiState = try allocator.create(State(size));
    uiState.clear();
    var inputState: input.InputState = undefined;
    inputState.clear();
    uiState.prepare(&inputState, screenSize, allocator);

    // content
    {
        const content = uiState.element(@src(), .{
            .size = .{
                .{.children = {}}, .{.children = {}},
            },
            .flags = .{
                .childrenStackX = true,
                .childrenStackY = false,
            },
        }) orelse return error.OOM;

        uiState.pushParent(content);
        defer uiState.popParent();

        _ = uiState.element(@src(), .{
            .size = .{
                .{.pixels = marginX}, .{.parentFrac = 1},
            },
        }) orelse return error.OOM;

        // center content
        {
            const center = uiState.element(@src(), .{
                .size = .{
                    .{.pixels = centerSize}, .{.children = {}},
                },
            }) orelse return error.OOM;

            uiState.pushParent(center);
            defer uiState.popParent();

            _ = uiState.element(@src(), .{
                .size = .{
                    .{.pixels = 200}, .{.pixels = 100},
                },
            }) orelse return error.OOM;
        }

        _ = uiState.element(@src(), .{
            .size = .{
                .{.pixels = marginX}, .{.parentFrac = 1},
            },
        }) orelse return error.OOM;
    }

    _ = uiState.element(@src(), .{
        .size = .{
            .{.pixels = screenSize.x}, .{.pixels = 150},
        },
    }) orelse return error.OOM;

    try uiState.layout(allocator);

    const elements = uiState.elements.slice();
    try std.testing.expectEqual(@as(usize, 1 + 6), elements.len); // root + 6 elements

    try std.testing.expectEqual([2]f32{0, 0}, elements[0].pos);
    try std.testing.expectEqual([2]f32{screenSize.x, 250}, elements[0].size);

    try std.testing.expectEqual([2]f32{0, 0}, elements[1].pos);
    try std.testing.expectEqual([2]f32{screenSize.x, 100}, elements[1].size);

    try std.testing.expectEqual([2]f32{0, 0}, elements[2].pos);
    try std.testing.expectEqual([2]f32{marginX, 100}, elements[2].size);

    try std.testing.expectEqual([2]f32{marginX, 0}, elements[3].pos);
    try std.testing.expectEqual([2]f32{centerSize , 100}, elements[3].size);

    try std.testing.expectEqual([2]f32{marginX, 0}, elements[4].pos);
    try std.testing.expectEqual([2]f32{200, 100}, elements[4].size);

    try std.testing.expectEqual([2]f32{screenSize.x - marginX, 0}, elements[5].pos);
    try std.testing.expectEqual([2]f32{marginX, 100}, elements[5].size);

    try std.testing.expectEqual([2]f32{0, 100}, elements[6].pos);
    try std.testing.expectEqual([2]f32{screenSize.x, 150}, elements[6].size);
}

test "diagonal layout"
{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const size = 512 * 1024;
    var uiState = try allocator.create(State(size));
    uiState.clear();

    var inputState: input.InputState = undefined;
    const screenSize = m.Vec2.init(500, 400);
    uiState.prepare(&inputState, screenSize, allocator);

    const diag = uiState.element(@src(), .{
        .size = .{.{.children = {}}, .{.children = {}}},
        .flags = .{.childrenStackX = true, .childrenStackY = true},
    }) orelse return error.OOM;
    uiState.pushParent(diag);
    defer uiState.popParent();

    _ = uiState.element(@src(), .{
        .size = .{.{.pixels = 50}, .{.pixels = 100}},
    }) orelse return error.OOM;

    _ = uiState.element(@src(), .{
        .size = .{.{.pixels = 50}, .{.pixels = 50}},
    }) orelse return error.OOM;

    _ = uiState.element(@src(), .{
        .size = .{.{.pixels = 200}, .{.pixels = 25}},
    }) orelse return error.OOM;

    try uiState.layout(allocator);

    const elements = uiState.elements.slice();
    try std.testing.expectEqual(@as(usize, 1 + 4), elements.len);

    try std.testing.expectEqual([2]f32{0, 0}, elements[0].pos);
    try std.testing.expectEqual([2]f32{300, 175}, elements[0].size);

    try std.testing.expectEqual([2]f32{0, 0}, elements[1].pos);
    try std.testing.expectEqual([2]f32{300, 175}, elements[1].size);

    try std.testing.expectEqual([2]f32{0, 0}, elements[2].pos);
    try std.testing.expectEqual([2]f32{50, 100}, elements[2].size);

    try std.testing.expectEqual([2]f32{50, 100}, elements[3].pos);
    try std.testing.expectEqual([2]f32{50, 50}, elements[3].size);

    try std.testing.expectEqual([2]f32{100, 150}, elements[4].pos);
    try std.testing.expectEqual([2]f32{200, 25}, elements[4].size);
}

test "layout with scroll and float"
{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const screenSize = m.Vec2.init(500, 400);

    const size = 512 * 1024;
    var uiState = try allocator.create(State(size));
    uiState.clear();
    var inputState: input.InputState = undefined;
    inputState.clear();
    uiState.prepare(&inputState, screenSize, allocator);

    {
        const scroll = uiState.element(@src(), .{
            .size = .{
                .{.pixels = screenSize.x}, .{.pixels = screenSize.y},
            },
        }) orelse return error.OOM;
        uiState.pushParent(scroll);
        defer uiState.popParent();

        const scrollContent = uiState.element(@src(), .{
            .size = .{
                .{.pixels = screenSize.x}, .{.children = {}},
            },
        }) orelse return error.OOM;
        uiState.pushParent(scrollContent);
        defer uiState.popParent();

        const top = uiState.element(@src(), .{
            .size = .{
                .{.pixels = 500}, .{.pixels = 50},
            },
        }) orelse return error.OOM;
        uiState.pushParent(top);
        defer uiState.popParent();

        _ = uiState.element(@src(), .{
            .size = .{
                .{.parentFrac = 1}, .{.parentFrac = 1},
            },
            .flags = .{
                .floatX = true,
                .floatY = true,
            },
        }) orelse return error.OOM;

        _ = uiState.element(@src(), .{
            .size = .{
                .{.parentFrac = 0.5}, .{.parentFrac = 1},
            },
            .flags = .{
                .floatX = true,
                .floatY = true,
            },
        }) orelse return error.OOM;
    }

    try uiState.layout(allocator);

    const elements = uiState.elements.slice();
    try std.testing.expectEqual(@as(usize, 1 + 5), elements.len);

    try std.testing.expectEqual([2]f32{0, 0}, elements[0].pos);
    try std.testing.expectEqual([2]f32{screenSize.x, screenSize.y}, elements[0].size);

    try std.testing.expectEqual([2]f32{0, 0}, elements[1].pos);
    try std.testing.expectEqual([2]f32{screenSize.x, screenSize.y}, elements[1].size);

    try std.testing.expectEqual([2]f32{0, 0}, elements[2].pos);
    try std.testing.expectEqual([2]f32{500, 50}, elements[2].size);

    try std.testing.expectEqual([2]f32{0, 0}, elements[3].pos);
    try std.testing.expectEqual([2]f32{500, 50}, elements[3].size);

    try std.testing.expectEqual([2]f32{0, 0}, elements[4].pos);
    try std.testing.expectEqual([2]f32{500, 50}, elements[4].size);

    try std.testing.expectEqual([2]f32{0, 0}, elements[5].pos);
    try std.testing.expectEqual([2]f32{250, 50}, elements[5].size);
}

test "layout across frames"
{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const screenSize = m.Vec2.init(1920, 1080);
    const size = 512 * 1024;
    var uiState = try allocator.create(State(size));
    uiState.clear();

    var inputState: input.InputState = undefined;
    inputState.clear();

    { // frame 1
        uiState.prepare(&inputState, screenSize, allocator);

        const screen = uiState.elementWithHash(1, .{
             .size = .{
                .{.pixels = 500}, .{.pixels = 500},
            },
        }) orelse return error.OOM;

        uiState.pushParent(screen);
        defer uiState.popParent();

        _ = uiState.elementWithHash(2, .{
            .size = .{
                .{.pixels = 50}, .{.parentFrac = 0.9},
            },
        }) orelse return error.OOM;

        _ = uiState.elementWithHash(3, .{
            .size = .{
                .{.pixels = 500}, .{.pixels = 20},
            },
        }) orelse return error.OOM;

        try uiState.layout(allocator);

        const elements = uiState.elements.slice();
        try std.testing.expectEqual(@as(usize, 1 + 3), elements.len);

        try std.testing.expectEqual([2]f32{0, 0}, elements[0].pos);
        try std.testing.expectEqual([2]f32{500, 500}, elements[0].size);

        try std.testing.expectEqual([2]f32{0, 0}, elements[1].pos);
        try std.testing.expectEqual([2]f32{500, 500}, elements[1].size);

        try std.testing.expectEqual([2]f32{0, 0}, elements[2].pos);
        try std.testing.expectEqual([2]f32{50, 450}, elements[2].size);

        try std.testing.expectEqual([2]f32{0, 450}, elements[3].pos);
        try std.testing.expectEqual([2]f32{500, 20}, elements[3].size);
    }

    { // frame 2
        uiState.prepare(&inputState, screenSize, allocator);

        const screen = uiState.elementWithHash(1, .{
             .size = .{
                .{.pixels = 500}, .{.pixels = 500},
            },
        }) orelse return error.OOM;

        uiState.pushParent(screen);
        defer uiState.popParent();

        _ = uiState.elementWithHash(2, .{
            .size = .{
                .{.pixels = 50}, .{.parentFrac = 0.9},
            },
        }) orelse return error.OOM;

        _ = uiState.elementWithHash(3, .{
            .size = .{
                .{.pixels = 500}, .{.pixels = 20},
            },
        }) orelse return error.OOM;

        try uiState.layout(allocator);

        const elements = uiState.elements.slice();
        try std.testing.expectEqual(@as(usize, 1 + 3), elements.len);

        try std.testing.expectEqual([2]f32{0, 0}, elements[0].pos);
        try std.testing.expectEqual([2]f32{500, 500}, elements[0].size);

        try std.testing.expectEqual([2]f32{0, 0}, elements[1].pos);
        try std.testing.expectEqual([2]f32{500, 500}, elements[1].size);

        try std.testing.expectEqual([2]f32{0, 0}, elements[2].pos);
        try std.testing.expectEqual([2]f32{50, 450}, elements[2].size);

        try std.testing.expectEqual([2]f32{0, 450}, elements[3].pos);
        try std.testing.expectEqual([2]f32{500, 20}, elements[3].size);
    }
}
