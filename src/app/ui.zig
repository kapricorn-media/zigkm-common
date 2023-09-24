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

        pub fn load(self: *Self) void
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
                    .size = .{.{.kind = .Children}, .{.kind = .Children}},
                },
                .pos = .{0, 0},
                .offset = .{0, 0},
                .size = .{0, 0},
                .hover = false,
                .clicked = false,
                .scrollVelY = 0,
            };
            self.parent = &self.elements.buffer[0];
            self.frame = 0;
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
                    if (!e.data.flags.clickable and !e.data.flags.scrollable) {
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
                                    for (inputState.mouseState.clickEvents.slice()) |ce| {
                                        const cePos = ce.pos.toVec2();
                                        if (ce.clickType == .Left and ce.down and m.isInsideRect(cePos, rect)) {
                                            e.clicked = true;
                                        }
                                    }
                                }
                                break;
                            }
                        },
                        .Touch => {
                            if (e.data.flags.clickable) {
                                for (inputState.touchState.activeTouches.slice()) |t| {
                                    const tPos = t.getPos().toVec2();
                                    if (t.new and m.isInsideRect(tPos, rect)) {
                                        e.clicked = true;
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

            for (self.elements.slice()) |*e| {
                if (!e.data.flags.scrollable) continue;

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

            // if (e.parent != self.parent or new) {
            //     e.parent = self.parent;
            // }
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

        fn layoutWithTreeIt(self: *Self, treeIt: *tree.TreeIterator(Element)) void
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
                    if (e.clicked) {
                        e.data.colors = .{
                            m.Vec4.init(0.0, 1.0, 0.0, 1.0),
                            m.Vec4.init(0.0, 1.0, 0.0, 1.0),
                            m.Vec4.init(0.0, 1.0, 0.0, 1.0),
                            m.Vec4.init(0.0, 1.0, 0.0, 1.0),
                        };
                    } else if (e.hover) {
                        e.data.colors = .{
                            m.Vec4.init(1.0, 0.0, 0.0, 1.0),
                            m.Vec4.init(1.0, 0.0, 0.0, 1.0),
                            m.Vec4.init(1.0, 0.0, 0.0, 1.0),
                            m.Vec4.init(1.0, 0.0, 0.0, 1.0),
                        };
                    }
                    i += 1;
                }
            }

            // Calculate independent sizes
            for (self.elements.slice()) |*e| {
                var textSize = [2]f32 {0, 0};
                if (e.data.size[0].kind == .TextContent or e.data.size[1].kind == .TextContent) {
                    if (e.data.text) |t| {
                        const textRect = render.textRect(t.text, t.fontData, null);
                        const textSizeVec = textRect.size();
                        textSize[0] = textSizeVec.x;
                        textSize[1] = textSizeVec.y;
                    }
                }
                inline for (0..2) |axis| {
                    switch (e.data.size[axis].kind) {
                        .Pixels => {
                            e.size[axis] = e.data.size[axis].value;
                        },
                        .TextContent => {
                            e.size[axis] = textSize[axis];
                        },
                        .FractionOfParent, .Children => {},
                    }
                }
            }

            var root = &self.elements.slice()[0];

            // Calculate upward-dependent sizes, except for .FractionOfParent -> .Children
            treeIt.prepare(root, .PreOrder) catch return;
            while (treeIt.next() catch return) |e| {
                if (e != e.parent) {
                    inline for (0..2) |axis| {
                        if (e.data.size[axis].kind == .FractionOfParent and e.parent.data.size[axis].kind != .Children) {
                            e.size[axis] = e.parent.size[axis] * e.data.size[axis].value;
                        }
                    }
                }
            }

            // Calculate downward-dependent sizes
            treeIt.prepare(root, .PostOrder) catch return;
            while (treeIt.next() catch return) |e| {
                if (e.firstChild != e) {
                    inline for (0..2) |axis| {
                        if (e.data.size[axis].kind == .Children) {
                            e.size[axis] = getChildrenSize(e, axis);
                        }
                    }
                }
            }

            // Calculate upward-dependent sizes, for .FractionOfParent -> .Children
            treeIt.prepare(root, .PreOrder) catch return;
            while (treeIt.next() catch return) |e| {
                if (e != e.parent) {
                    inline for (0..2) |axis| {
                        if (e.data.size[axis].kind == .FractionOfParent and e.parent.data.size[axis].kind == .Children) {
                            e.size[axis] = e.parent.size[axis] * e.data.size[axis].value;
                        }
                    }
                }
            }

            // Calculate positions
            treeIt.prepare(root, .PreOrder) catch return;
            root.pos[0] = 0;
            root.pos[1] = 0;
            while (treeIt.next() catch return) |e| {
                var pos = e.parent.pos;
                // TODO it's weird that these are -= instead of +=
                pos[0] -= e.parent.offset[0];
                pos[1] -= e.parent.offset[1];
                inline for (0..2) |axis| {
                    const stack = getStack(e.parent.data.flags, axis);
                    const float = getFloat(e.data.flags, axis);
                    const prev = e.prevSibling;
                    if (prev != e and stack and !float) {
                        pos = prev.pos;
                        pos[axis] += prev.size[axis];
                    }
                }
                e.pos = pos;
            }
        }

        pub fn layout(self: *Self, tempAllocator: std.mem.Allocator) void
        {
            var treeIt = tree.TreeIterator(Element).init(tempAllocator);
            self.layoutWithTreeIt(&treeIt);
        }

        pub fn layoutAndDraw(self: *Self, renderState: *render.RenderState, tempAllocator: std.mem.Allocator) void
        {
            var treeIt = tree.TreeIterator(Element).init(tempAllocator);
            const root = &self.elements.slice()[0];
            self.layoutWithTreeIt(&treeIt);

            var renderQueue = tempAllocator.create(render.RenderQueue) catch {
                std.log.warn("Failed to allocate RenderQueue", .{});
                return;
            };
            renderQueue.load();

            // Calculate positions and draw
            treeIt.prepare(root, .PreOrder) catch return;
            while (treeIt.next() catch return) |e| {
                const size = m.Vec2.init(e.size[0], e.size[1]);
                const pos = getElementRenderPos(e, self.screenSize);
                const depth = e.data.depth;
                var renderQuad = false;
                inline for (0..4) |i| {
                    renderQuad = renderQuad or !m.eql(e.data.colors[i], m.Vec4.zero);
                }
                if (renderQuad) {
                    renderQueue.quadGradient(pos, size, depth, e.data.cornerRadius, e.data.colors);
                }
                if (e.data.text) |t| {
                    const textPosX = blk: {
                        switch (t.alignment) {
                            .Left => break :blk pos.x,
                            .Center => {
                                const textRect = render.textRect(t.text, t.fontData, null);
                                break :blk pos.x + size.x / 2 - textRect.size().x / 2;
                            },
                            .Right => {
                                const textRect = render.textRect(t.text, t.fontData, null);
                                break :blk pos.x + size.x - textRect.size().x;
                            },
                        }
                    };
                    const textPosY = pos.y + e.size[1] - t.fontData.ascent;
                    const textPos = m.Vec2.init(textPosX, textPosY);
                    renderQueue.text(t.text, textPos, depth, t.fontData, t.color);
                }
            }

            renderQueue.render(renderState, self.screenSize, tempAllocator);
        }
    };
    return S;
}

pub const ElementFlags = packed struct {
    // layout
    floatX: bool = false,
    floatY: bool = false,
    overflowX: bool = false,
    overflowY: bool = false,
    childrenStackX: bool = false,
    childrenStackY: bool = true,

    // interaction
    clickable: bool = false,
    scrollable: bool = false,
};

pub const TextAlignment = enum {
    Left,
    Center,
    Right,
};

pub const ElementTextData = struct {
    text: []const u8,
    fontData: *const asset_data.FontData,
    alignment: TextAlignment,
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

pub const SizeKind = enum {
    Pixels,
    TextContent,
    FractionOfParent,
    Children,
};

pub const Size = struct {
    kind: SizeKind = .Pixels,
    value: f32 = 0.0,
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

fn getInteractionFlags(inputState: *const input.InputState, e: *Element) bool
{
    _ = inputState;
    e.hover = false;
    e.clicked = false;
    return false;
}

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
    uiState.load();
    var inputState: input.InputState = undefined;
    uiState.prepare(&inputState, screenSize, allocator);

    // content
    {
        const content = uiState.element(@src(), .{
            .size = .{
                .{.kind = .Children},
                .{.kind = .Children},
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
                .{.kind = .Pixels, .value = marginX},
                .{.kind = .FractionOfParent, .value = 1},
            },
        }) orelse return error.OOM;

        // center content
        {
            const center = uiState.element(@src(), .{
                .size = .{
                    .{.kind = .Pixels, .value = centerSize},
                    .{.kind = .Children},
                },
            }) orelse return error.OOM;

            uiState.pushParent(center);
            defer uiState.popParent();

            _ = uiState.element(@src(), .{
                .size = .{
                    .{.kind = .Pixels, .value = 200},
                    .{.kind = .Pixels, .value = 100},
                },
            }) orelse return error.OOM;
        }

        _ = uiState.element(@src(), .{
            .size = .{
                .{.kind = .Pixels, .value = marginX},
                .{.kind = .FractionOfParent, .value = 1},
            },
        }) orelse return error.OOM;
    }

    _ = uiState.element(@src(), .{
        .size = .{
            .{.kind = .Pixels, .value = screenSize.x},
            .{.kind = .Pixels, .value = 150},
        },
    }) orelse return error.OOM;

    uiState.layout(allocator);

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

test "layout across frames"
{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const screenSize = m.Vec2.init(1920, 1080);
    const size = 512 * 1024;
    var uiState = try allocator.create(State(size));
    uiState.load();

    { // frame 1
        var inputState: input.InputState = undefined;
        uiState.prepare(&inputState, screenSize, allocator);

        const screen = uiState.elementWithHash(1, .{
             .size = .{
                .{.kind = .Pixels, .value = 500},
                .{.kind = .Pixels, .value = 500},
            },
        }) orelse return error.OOM;

        uiState.pushParent(screen);
        defer uiState.popParent();

        _ = uiState.elementWithHash(2, .{
            .size = .{
                .{.kind = .Pixels, .value = 50},
                .{.kind = .FractionOfParent, .value = 0.9},
            },
        }) orelse return error.OOM;

        _ = uiState.elementWithHash(3, .{
            .size = .{
                .{.kind = .Pixels, .value = 500},
                .{.kind = .Pixels, .value = 20},
            },
        }) orelse return error.OOM;

        uiState.layout(allocator);

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
        var inputState: input.InputState = undefined;
        uiState.prepare(&inputState, screenSize, allocator);

        const screen = uiState.elementWithHash(1, .{
             .size = .{
                .{.kind = .Pixels, .value = 500},
                .{.kind = .Pixels, .value = 500},
            },
        }) orelse return error.OOM;

        uiState.pushParent(screen);
        defer uiState.popParent();

        _ = uiState.elementWithHash(2, .{
            .size = .{
                .{.kind = .Pixels, .value = 50},
                .{.kind = .FractionOfParent, .value = 0.9},
            },
        }) orelse return error.OOM;

        _ = uiState.elementWithHash(3, .{
            .size = .{
                .{.kind = .Pixels, .value = 500},
                .{.kind = .Pixels, .value = 20},
            },
        }) orelse return error.OOM;

        uiState.layout(allocator);

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