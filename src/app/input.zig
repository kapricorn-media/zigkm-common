const std = @import("std");

const m = @import("zigkm-math");

pub const InputState = struct
{
    mouseState: MouseState,
    keyboardState: KeyboardState,
    deviceState: DeviceState,
    touchState: TouchState,

    const Self = @This();

    pub fn clear(self: *Self) void
    {
        self.mouseState.clear();
        self.keyboardState.clear();
        self.touchState.clear();
    }

    pub fn updateStart(self: *Self) void
    {
        self.touchState.updateStart();
    }

    pub fn updateEnd(self: *Self) void
    {
        self.mouseState.clear();
        self.keyboardState.clear();
        self.touchState.updateEnd();
    }
};

pub const ClickType = enum {
    Left,
    Middle,
    Right,
    Other,
};

pub const ClickEvent = struct {
    pos: m.Vec2i,
    clickType: ClickType,
    down: bool,
};

pub const MouseState = struct {
    pos: m.Vec2i,
    numClickEvents: usize,
    clickEvents: [64]ClickEvent,

    const Self = @This();

    pub fn init() Self
    {
        return Self {
            .pos = m.Vec2i.zero,
            .numClickEvents = 0,
            .clickEvents = undefined,
        };
    }

    pub fn clear(self: *Self) void
    {
        self.numClickEvents = 0;
    }

    pub fn addClickEvent(self: *Self, pos: m.Vec2i, clickType: ClickType, down: bool) void
    {
        const i = self.numClickEvents;
        if (i >= self.clickEvents.len) {
            return;
        }

        self.clickEvents[i] = ClickEvent {
            .pos = pos,
            .clickType = clickType,
            .down = down,
        };
        self.numClickEvents += 1;
    }
};

pub const KeyEvent = struct {
    keyCode: i32,
    down: bool,
};

pub const KeyboardState = struct {
    numKeyEvents: usize,
    keyEvents: [64]KeyEvent,
    numUtf32: u32,
    utf32: [4096]u32,

    const Self = @This();

    pub fn init() Self
    {
        return Self {
            .numKeyEvents = 0,
            .keyEvents = undefined,
            .numUtf32 = 0,
            .utf32 = undefined,
        };
    }

    pub fn clear(self: *Self) void
    {
        self.numKeyEvents = 0;
        self.numUtf32 = 0;
    }

    pub fn addKeyEvent(self: *Self, keyCode: i32, down: bool) void
    {
        const i = self.numKeyEvents;
        if (i >= self.keyEvents.len) {
            return;
        }

        self.keyEvents[i] = KeyEvent {
            .keyCode = keyCode,
            .down = down,
        };
        self.numKeyEvents += 1;
    }

    pub fn keyDown(self: Self, keyCode: i32) bool
    {
        const keyEvents = self.keyEvents[0..self.numKeyEvents];
        var latestDown = false;
        for (keyEvents) |e| {
            if (e.keyCode == keyCode) {
                latestDown = e.down;
            }
        }
        return latestDown;
    }
};

pub const DeviceState = struct {
    angles: m.Vec3,
};

pub const TouchPhase = enum
{
    Begin,
    Still,
    Move,
    End,
    Cancel,
};

pub const TouchEvent = struct
{
    id: u64,
    pos: m.Vec2i,
    tapCount: u32,
    phase: TouchPhase,
};

const ActiveTouch = struct
{
    id: u64,
    new: bool, // new this frame?
    ending: bool, // ending this frame?
    updated: bool, // updated this frame? internal
    posStart: m.Vec2i,
    i: u32, // index of current pos
    n: u32, // number of active elements in pos
    pos: [10]m.Vec2i,

    const Self = @This();

    pub fn getPos(self: *const Self) m.Vec2i
    {
        std.debug.assert(self.i < self.pos.len);
        std.debug.assert(self.n != 0);
        std.debug.assert(self.n <= self.pos.len);

        return self.pos[self.i];
    }

    pub fn getPrevPos(self: *const Self) ?m.Vec2i
    {
        std.debug.assert(self.i < self.pos.len);
        std.debug.assert(self.n <= self.pos.len);

        if (self.n <= 1) {
            return null;
        }
        const prevInd = if (self.i == 0) self.pos.len - 1 else self.i - 1;
        return self.pos[prevInd];
    }

    pub fn getWeightedVel(self: *const Self) m.Vec2
    {
        std.debug.assert(self.i < self.pos.len);
        std.debug.assert(self.n != 0);
        std.debug.assert(self.n <= self.pos.len);

        const weights = [10]f32 {
            0.5,
            3.0,
            2.0,
            1.5,
            1.0,
            0.75,
            0.5,
            0.4,
            0.3,
            0.2,
        };

        var mean = m.Vec2.zero;

        var i = self.i;
        var n: u32 = 0;
        while (n < self.n - 1) : (n += 1) {
            const iPrev = if (i == 0) @as(u32, @intCast(self.pos.len - 1)) else i - 1;
            const delta = m.Vec2i.sub(self.pos[i], self.pos[iPrev]);
            mean = m.Vec2.add(mean, m.Vec2.mul(delta.toVec2(), weights[n]));
            i = iPrev;
        }

        return m.Vec2.divide(mean, @floatFromInt(self.n));
    }

    fn addPos(self: *Self, pos: m.Vec2i) void
    {
        std.debug.assert(self.i < self.pos.len);
        std.debug.assert(self.n <= self.pos.len);

        var newIndex = self.i + 1;
        if (newIndex >= self.pos.len) {
            newIndex = 0;
        }
        self.pos[newIndex] = pos;
        self.i = newIndex;

        if (self.n < self.pos.len) {
            self.n += 1;
        }
    }
};

pub const TouchState = struct
{
    numTouchEvents: u32,
    touchEvents: [4096]TouchEvent,
    // numUtf32: u32,
    // utf32: [4096]u32,

    numActiveTouches: u32,
    activeTouches: [64]ActiveTouch,

    const Self = @This();

    pub fn clear(self: *Self) void
    {
        self.numTouchEvents = 0;
        // self.numUtf32 = 0;
        self.numActiveTouches = 0;
    }

    pub fn updateStart(self: *Self) void
    {
        var i: usize = 0;
        while (i < self.numActiveTouches) : (i += 1) {
            self.activeTouches[i].updated = false;
        }

        if (self.numTouchEvents > 0) {
            const touchEvents = self.touchEvents[0..self.numTouchEvents];
            for (touchEvents) |touchEvent| {
                // std.log.debug("touchEvent: {}", .{touchEvent});
                var foundIndex: usize = self.numActiveTouches;
                if (self.numActiveTouches > 0) {
                    const activeTouches = self.activeTouches[0..self.numActiveTouches];
                    for (activeTouches, 0..) |touch, j| {
                        if (touchEvent.id == touch.id) {
                            foundIndex = j;
                            break;
                        }
                    }
                }
                if (foundIndex != self.numActiveTouches) {
                    switch (touchEvent.phase) {
                        .Begin => {
                            std.debug.panic("begin phase on active touch event", .{});
                        },
                        .Still, .Move => {
                            self.activeTouches[foundIndex].addPos(touchEvent.pos);
                            self.activeTouches[foundIndex].updated = true;
                        },
                        .End, .Cancel => {
                            self.activeTouches[foundIndex].addPos(touchEvent.pos);
                            self.activeTouches[foundIndex].updated = true;
                            self.activeTouches[foundIndex].ending = true;
                        },
                    }
                } else {
                    if (self.numActiveTouches >= self.activeTouches.len) {
                        std.log.err("No more space for active touches", .{});
                        continue;
                    }
                    if (touchEvent.phase != .Begin) {
                        std.log.err("missed begin for touch", .{});
                        continue;
                    }
                    self.activeTouches[self.numActiveTouches] = .{
                        .id = touchEvent.id,
                        .new = true,
                        .ending = false,
                        .updated = true,
                        .posStart = touchEvent.pos,
                        .i = 0,
                        .n = 0,
                        .pos = undefined,
                    };
                    self.activeTouches[self.numActiveTouches].addPos(touchEvent.pos);
                    self.numActiveTouches += 1;
                }
            }
        }

        i = 0;
        while (i < self.numActiveTouches) : (i += 1) {
            if (!self.activeTouches[i].updated) {
                self.activeTouches[i].addPos(self.activeTouches[i].getPos());
            }
        }
    }

    pub fn updateEnd(self: *Self) void
    {
        var i: usize = 0;
        while (i < self.numActiveTouches) {
            if (self.activeTouches[i].ending) {
                self.activeTouches[i] = self.activeTouches[self.numActiveTouches - 1];
                self.numActiveTouches -= 1;
                continue; // don't increment i
            }

            self.activeTouches[i].new = false;
            // self.activeTouches[i].addPos(
            // self.activeTouches[i].posPrev = self.activeTouches[i].pos;
            i += 1;
        }

        self.numTouchEvents = 0;
        // self.numUtf32 = 0;
    }
};
