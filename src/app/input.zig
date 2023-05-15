const m = @import("zigkm-math");

pub const InputState = struct
{
    mouseState: MouseState,
    keyboardState: KeyboardState,
    deviceState: DeviceState,
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

    const Self = @This();

    pub fn init() Self
    {
        return Self {
            .numKeyEvents = 0,
            .keyEvents = undefined,
        };
    }

    pub fn clear(self: *Self) void
    {
        self.numKeyEvents = 0;
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
