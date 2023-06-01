const std = @import("std");

const m = @import("zigkm-math");

pub const PixelData = struct {
    size: m.Vec2usize,
    channels: u8,
    data: []u8,
};

pub const PixelDataSlice = struct {
    topLeft: m.Vec2usize,
    size: m.Vec2usize,
};

pub fn trim(data: PixelData, slice: PixelDataSlice) PixelDataSlice
{
    std.debug.assert(data.channels == 4); // need alpha channel for current trim
    std.debug.assert(slice.topLeft.x <= data.size.x and slice.topLeft.y <= data.size.y);
    const sliceMax = m.add(slice.topLeft, slice.size);
    std.debug.assert(sliceMax.x <= data.size.x and sliceMax.y <= data.size.y);

    var max = slice.topLeft;
    var min = sliceMax;
    var y: usize = 0;
    while (y < slice.size.y) : (y += 1) {
        var x: usize = 0;
        while (x < slice.size.x) : (x += 1) {
            const pixel = m.add(slice.topLeft, m.Vec2usize.init(x, y));
            const pixelInd = pixel.y * data.size.x + pixel.x;
            const alphaInd = pixelInd * data.channels + 3;
            if (data.data[alphaInd] != 0) {
                max = m.max(max, pixel);
                min = m.min(min, pixel);
            }
        }
    }

    std.debug.assert(min.x <= max.x and min.y <= max.y);
    return PixelDataSlice {
        .topLeft = m.add(slice.topLeft, min),
        .size = m.sub(max, min),
    };
}
