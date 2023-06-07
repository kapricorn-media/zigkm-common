const std = @import("std");

fn assertMathType(comptime T: type) void
{
    std.debug.assert(T == Vec2usize or T == Vec2i or T == Vec2 or T == Vec3 or T == Vec4);
}

fn zeroValue(comptime T: type) T
{
    assertMathType(T);

    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |f| {
        @field(result, f.name) = 0;
    }
    return result;
}

fn oneValue(comptime T: type) T
{
    assertMathType(T);

    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |f| {
        @field(result, f.name) = 1;
    }
    return result;
}

pub fn eql(v1: anytype, v2: @TypeOf(v1)) bool
{
    const T = @TypeOf(v1);
    assertMathType(T);

    inline for (@typeInfo(T).Struct.fields) |f| {
        if (@field(v1, f.name) != @field(v2, f.name)) {
            return false;
        }
    }
    return true;
}

pub fn add(v1: anytype, v2: @TypeOf(v1)) @TypeOf(v1)
{
    const T = @TypeOf(v1);
    assertMathType(T);

    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |f| {
        @field(result, f.name) = @field(v1, f.name) + @field(v2, f.name);
    }
    return result;
}

pub fn sub(v1: anytype, v2: @TypeOf(v1)) @TypeOf(v1)
{
    const T = @TypeOf(v1);
    assertMathType(T);

    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |f| {
        @field(result, f.name) = @field(v1, f.name) - @field(v2, f.name);
    }
    return result;
}

pub fn multElements(v1: anytype, v2: @TypeOf(v1)) @TypeOf(v1)
{
    const T = @TypeOf(v1);
    assertMathType(T);

    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |f| {
        @field(result, f.name) = @field(v1, f.name) * @field(v2, f.name);
    }
    return result;
}

pub fn divElements(v1: anytype, v2: @TypeOf(v1)) @TypeOf(v1)
{
    const T = @TypeOf(v1);
    assertMathType(T);

    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |f| {
        @field(result, f.name) = @field(v1, f.name) / @field(v2, f.name);
    }
    return result;
}

pub fn multScalar(v: anytype, s: @TypeOf(v.x)) @TypeOf(v)
{
    const T = @TypeOf(v);
    assertMathType(T);

    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |f| {
        @field(result, f.name) = @field(v, f.name) * s;
    }
    return result;
}

pub fn divScalar(v: anytype, s: @TypeOf(v.x)) @TypeOf(v)
{
    const T = @TypeOf(v);
    assertMathType(T);
    const TScalar = @TypeOf(v.x);

    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |f| {
        if (@typeInfo(TScalar) == .Int) {
            @field(result, f.name) = @divTrunc(@field(v, f.name), s);
        } else {
            @field(result, f.name) = @field(v, f.name) / s;
        }
    }
    return result;
}

pub fn dot(v1: anytype, v2: @TypeOf(v1)) @TypeOf(v1.x)
{
    const T = @TypeOf(v1);
    assertMathType(T);
    const TScalar = @TypeOf(v1.x);

    var result: TScalar = 0;
    inline for (@typeInfo(T).Struct.fields) |f| {
        result += @field(v1, f.name) * @field(v2, f.name);
    }
    return result;
}

pub fn max(v1: anytype, v2: @TypeOf(v1)) @TypeOf(v1)
{
    const T = @TypeOf(v1);
    assertMathType(T);

    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |f| {
        @field(result, f.name) = @max(@field(v1, f.name), @field(v2, f.name));
    }
    return result;
}

pub fn min(v1: anytype, v2: @TypeOf(v1)) @TypeOf(v1)
{
    const T = @TypeOf(v1);
    assertMathType(T);

    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |f| {
        @field(result, f.name) = @min(@field(v1, f.name), @field(v2, f.name));
    }
    return result;
}

pub fn lerpFloat(v1: anytype, v2: @TypeOf(v1), t: @TypeOf(v1)) @TypeOf(v1)
{
    std.debug.assert(@typeInfo(@TypeOf(v1)) == .Float);
    return v1 * (1.0 - t) + v2 * t;
}

pub fn lerp(v1: anytype, v2: @TypeOf(v1), t: @TypeOf(v1.x)) @TypeOf(v1)
{
    return add(multScalar(v1, 1.0 - t), multScalar(v2, t));
}

pub fn isInsideRect(p: Vec2, rect: Rect) bool
{
    return p.x >= rect.min.x and p.x <= rect.max.x and p.y >= rect.min.y and p.y <= rect.max.y;
}

pub const Vec2usize = extern struct {
    x: usize,
    y: usize,

    const Self = @This();

    pub const zero = zeroValue(Self);
    pub const one  = oneValue(Self);

    pub fn init(x: usize, y: usize) Self
    {
        return Self { .x = x, .y = y };
    }

    pub fn initFromVec2i(v: Vec2i) Self
    {
        return Self { .x = @intCast(usize, v.x), .y = @intCast(usize, v.y) };
    }

    pub fn toVec2(self: Self) Vec2
    {
        return Vec2.initFromVec2usize(self);
    }

    pub fn toVec2i(self: Self) Vec2i
    {
        return Vec2i.initFromVec2usize(self);
    }
};

pub const Vec2i = extern struct {
    x: i32,
    y: i32,

    const Self = @This();

    pub const zero  = zeroValue(Self);
    pub const one   = oneValue(Self);
    pub const unitX = init(1, 0);
    pub const unitY = init(0, 1);

    pub fn init(x: i32, y: i32) Self
    {
        return Self { .x = x, .y = y };
    }

    pub fn initFromVec2usize(v: Vec2usize) Self
    {
        return Self { .x = @intCast(i32, v.x), .y = @intCast(i32, v.y) };
    }

    pub fn toVec2(self: Self) Vec2
    {
        return Vec2.initFromVec2i(self);
    }

    pub fn toVec2usize(self: Self) Vec2usize
    {
        return Vec2usize.initFromVec2i(self);
    }
};

pub const Vec2 = extern struct {
    x: f32,
    y: f32,

    const Self = @This();

    pub const zero  = zeroValue(Self);
    pub const one   = oneValue(Self);
    pub const unitX = init(1.0, 0.0);
    pub const unitY = init(0.0, 1.0);

    pub fn init(x: f32, y: f32) Self
    {
        return Self { .x = x, .y = y };
    }

    pub fn initFromVec2i(v: Vec2i) Self
    {
        return Self.init(@intToFloat(f32, v.x), @intToFloat(f32, v.y));
    }

    pub fn initFromVec2usize(v: Vec2usize) Self
    {
        return Self.init(@intToFloat(f32, v.x), @intToFloat(f32, v.y));
    }
};

pub const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,

    const Self = @This();

    pub const zero  = zeroValue(Self);
    pub const one   = oneValue(Self);
    pub const unitX = init(1.0, 0.0, 0.0);
    pub const unitY = init(0.0, 1.0, 0.0);
    pub const unitZ = init(0.0, 0.0, 1.0);

    pub fn init(x: f32, y: f32, z: f32) Self
    {
        return Self { .x = x, .y = y, .z = z };
    }
};

pub const Vec4 = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    const Self = @This();

    pub const zero  = zeroValue(Self);
    pub const one   = oneValue(Self);
    pub const white = one;
    pub const black = init(0.0, 0.0, 0.0, 1.0);
    pub const red   = init(1.0, 0.0, 0.0, 1.0);
    pub const green = init(0.0, 1.0, 0.0, 1.0);
    pub const blue  = init(0.0, 0.0, 1.0, 1.0);

    pub fn init(x: f32, y: f32, z: f32, w: f32) Self
    {
        return Self { .x = x, .y = y, .z = z, .w = w };
    }

    pub fn initColorU8(r: u8, g: u8, b: u8, a: u8) Self
    {
        return Self {
            .x = @intToFloat(f32, r) / 255.0,
            .y = @intToFloat(f32, g) / 255.0,
            .z = @intToFloat(f32, b) / 255.0,
            .w = @intToFloat(f32, a) / 255.0,
        };
    }
};

pub const Rect = RectType(Vec2);
pub const Rect2 = Rect;
pub const Rect2i = RectType(Vec2i);
pub const Rect2usize = RectType(Vec2usize);

fn RectType(comptime VectorType: type) type
{
    const R = extern struct {
        min: VectorType,
        max: VectorType,

        const Self = @This();

        pub const zero = init(zeroValue(VectorType), zeroValue(VectorType));

        pub fn init(vMin: VectorType, vMax: VectorType) Self
        {
            return Self {
                .min = vMin,
                .max = vMax,
            };
        }

        pub fn initOriginSize(origin: VectorType, theSize: VectorType) Self
        {
            return Self {
                .min = origin,
                .max = add(origin, theSize),
            };
        }

        pub fn size(self: Self) VectorType
        {
            return sub(self.max, self.min);
        }
    };
    return R;
}

// Should always be unit quaternions
pub const Quat = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    const Self = @This();

    pub const one = Self {
        .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0
    };

    // Quat QuatRotBetweenVectors(Vec3 v1, Vec3 v2)
    // {
    //     float32 dot = Dot(v1, v2);
    //     if (dot > 0.99999f) {
    //         return Quat::one;
    //     }
    //     else if (dot < -0.99999f) {
    //         // TODO 180 degree rotation about any perpendicular axis
    //         // hardcoded PI_F could be cheaper to calculate some other way
    //         const Vec3 axis = Normalize(GetPerpendicular(v1));
    //         return QuatFromAngleUnitAxis(PI_F, axis);
    //     }

    //     const Vec3 axis = Cross(v1, v2);
    //     const float32 angle = Sqrt32(MagSq(v1) * MagSq(v2)) + dot;
    //     return QuatFromAngleUnitAxis(angle, Normalize(axis));
    // }

    pub fn init(angle: f32, unitAxis: Vec3) Self
    {
        const cosHalfAngle = std.math.cos(angle / 2.0);
        const sinHalfAngle = std.math.sin(angle / 2.0);
        return Self {
            .x = unitAxis.x * sinHalfAngle,
            .y = unitAxis.y * sinHalfAngle,
            .z = unitAxis.z * sinHalfAngle,
            .w = cosHalfAngle,
        };
    }

    // TODO is this working?
    pub fn initFromEulerAngles(euler: Vec3) Self
    {
        var quat = init(euler.x, Vec3.unitX);
        quat = mult(init(euler.y, Vec3.unitY), quat);
        quat = mult(init(euler.z, Vec3.unitZ), quat);
        return quat;
    }

    pub fn mult(q1: Self, q2: Self) Self
    {
        return Self {
            .x = q1.w*q2.x + q1.x*q2.w + q1.y*q2.z - q1.z*q2.y,
            .y = q1.w*q2.y + q1.y*q2.w + q1.z*q2.x - q1.x*q2.z,
            .z = q1.w*q2.z + q1.z*q2.w + q1.x*q2.y - q1.y*q2.x,
            .w = q1.w*q2.w - q1.x*q2.x - q1.y*q2.y - q1.z*q2.z,
        };
    }

    pub fn magSq(q: Self) f32
    {
        return q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w;
    }

    pub fn mag(q: Self) f32
    {
        return std.math.sqrt(magSq(q));
    }

    pub fn normalize(q: Self) Self
    {
        const m = mag(q);
        return Self {
            .x = q.x / m,
            .y = q.y / m,
            .z = q.z / m,
            .w = q.w / m,
        };
    }

    // Returns a new quaternion qInv such that q * qInv = Quat::one
    pub fn inverse(q: Self) Self
    {
        return Self {
            .x = -q.x,
            .y = -q.y,
            .z = -q.z,
            .w = q.w,
        };
    }

    pub fn rotate(q: Self, v: Vec3) Vec3
    {
        // Treat v as a quaternion with w = 0
        const vQ = Self { .x = v.x, .y = v.y, .z = v.z, .w = 0 };
        // TODO Quat multiply with baked in w=0 would be faster, obviously
        // qv.x = q.w*v.x + q.y*v.z - q.z*v.y;
        // qv.y = q.w*v.y + q.z*v.x - q.x*v.z;
        // qv.z = q.w*v.z + q.x*v.y - q.y*v.x;
        // qv.w = -q.x*v.x - q.y*v.y - q.z*v.z;
        const qv = mult(q, vQ);

        const qInv = inverse(q);
        const qvqInv = mult(qv, qInv);
        return Vec3 { .x = qvqInv.x, .y = qvqInv.y, .z = qvqInv.z };
    }
};

pub const Mat4x4 = extern struct {
    e: [4][4]f32,

    const Self = @This();

    pub const identity = Self {
        .e = [4][4]f32 {
            [4]f32 { 1.0, 0.0, 0.0, 0.0 },
            [4]f32 { 0.0, 1.0, 0.0, 0.0 },
            [4]f32 { 0.0, 0.0, 1.0, 0.0 },
            [4]f32 { 0.0, 0.0, 0.0, 1.0 },
        },
    };

    pub fn initTranslate(v: Vec3) Self
    {
        var result = identity;
        result.e[3][0] = v.x;
        result.e[3][1] = v.y;
        result.e[3][2] = v.z;
        return result;
    }
};

fn testFn(function: anytype, v1: anytype, v2: anytype, expected: anytype) !void
{
    const result = function(v1, v2);
    try std.testing.expectEqual(expected, result);
}

test "arithmetic"
{
    try testFn(add, Vec2i.init(1, 6), Vec2i.init(4, 5), Vec2i.init(5, 11));
    try testFn(add, Vec2.init(1.0, 0.0), Vec2.init(4.0, 5.0), Vec2.init(5.0, 5.0));
    try testFn(add, Vec3.init(1.0, 0.0, -200.0), Vec3.init(4.0, 5.0, 1.0), Vec3.init(5.0, 5.0, -199.0));

    try testFn(sub, Vec2i.init(1, 6), Vec2i.init(4, 5), Vec2i.init(-3, 1));
    try testFn(sub, Vec2.init(1.0, 0.0), Vec2.init(4.0, 5.0), Vec2.init(-3.0, -5.0));
    try testFn(sub, Vec3.init(1.0, 0.0, -200.0), Vec3.init(4.0, 5.0, 1.0), Vec3.init(-3.0, -5.0, -201.0));

    try testFn(multScalar, Vec2i.init(1, 6), 3, Vec2i.init(1 * 3, 6 * 3));
    try testFn(multScalar, Vec2.init(-3.0, 5.0), 2.5, Vec2.init(-3.0 * 2.5, 5.0 * 2.5));
    try testFn(multScalar, Vec3.init(1.0, 0.0, -200.0), 2.5, Vec3.init(1.0 * 2.5, 0.0 * 2.5, -200.0 * 2.5));

    try testFn(divScalar, Vec2i.init(1, 6), 3, Vec2i.init(0, 2));
    try testFn(divScalar, Vec2.init(-3.0, 5.0), 2.5, Vec2.init(-3.0 / 2.5, 5.0 / 2.5));
    try testFn(divScalar, Vec3.init(1.0, 0.0, -200.0), 2.5, Vec3.init(1.0 / 2.5, 0.0 / 2.5, -200.0 / 2.5));

    // TODO max, min, dot
}

comptime {
    std.debug.assert(@sizeOf(Vec2i) == 4 * 2);
    std.debug.assert(@sizeOf(Vec2) == 4 * 2);
    std.debug.assert(@sizeOf(Vec3) == 4 * 3);
    std.debug.assert(@sizeOf(Vec4) == 4 * 4);
    std.debug.assert(@sizeOf(Mat4x4) == 4 * 4 * 4);
}
