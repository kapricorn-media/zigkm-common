// fn toFloat2(v: m.Vec2) ios.float2
// {
//     return .{
//         .x = v.x,
//         .y = v.y,
//     };
// }

// fn toFloat4(v: m.Vec4) ios.float4
// {
//     return .{
//         .x = v.x,
//         .y = v.y,
//         .z = v.z,
//         .w = v.w,
//     };
// }

// pub const RenderState = struct
// {
//     renderState: *bindings.RenderState2,

//     const Self = @This();

//     pub fn load(self: *Self, context: *bindings.Context) !void
//     {
//         self.* = RenderState {
//             .renderState = try bindings.createRenderState(context),
//         };
//     }
// };

// pub fn render(
//     context: *bindings.Context,
//     renderState: *const RenderState,
//     renderQueue: *RenderQueue,
//     assets: anytype,
//     screenSize: m.Vec2,
//     allocator: std.mem.Allocator) void
// {
//     var tempArena = std.heap.ArenaAllocator.init(allocator);
//     defer tempArena.deinit();
//     const tempAllocator = tempArena.allocator();

//     if (renderQueue.quads.len > 0) {
//         const instanceBufferBytes = std.mem.sliceAsBytes(renderQueue.quads.slice());
//         bindings.renderQuads(
//             context, renderState.renderState, renderQueue.quads.len, instanceBufferBytes, screenSize.x, screenSize.y
//         );
//     }

//     if (renderQueue.texQuads.len > 0) {
//         var texQuadInstances = tempAllocator.alloc(ios.TexQuadInstanceData, renderQueue.texQuads.len) catch {
//             std.log.warn("Failed to allocate textured quad instances, skipping", .{});
//             return;
//         };
//         var textures = tempAllocator.alloc(*bindings.Texture, renderQueue.texQuads.len) catch {
//             std.log.warn("Failed to allocate textured quad Textures, skipping", .{});
//             return;
//         };
//         for (renderQueue.texQuads.slice()) |texQuad, i| {
//             texQuadInstances[i] = .{
//                 .quad = .{
//                     .colors = .{
//                         toFloat4(texQuad.colors[0]),
//                         toFloat4(texQuad.colors[1]),
//                         toFloat4(texQuad.colors[2]),
//                         toFloat4(texQuad.colors[3]),
//                     },
//                     .bottomLeft = toFloat2(texQuad.bottomLeft),
//                     .size = toFloat2(texQuad.size),
//                     .depth = texQuad.depth,
//                     .cornerRadius = texQuad.cornerRadius,
//                     ._pad = undefined,
//                 },
//                 .uvBottomLeft = toFloat2(texQuad.uvBottomLeft),
//                 .uvSize = toFloat2(texQuad.uvSize),
//             };
//             textures[i] = texQuad.texture;
//         }
//         const instanceBufferBytes = std.mem.sliceAsBytes(texQuadInstances);
//         bindings.renderTexQuads(context, renderState.renderState, instanceBufferBytes, textures, screenSize.x, screenSize.y);
//     }

//     if (renderQueue.texts.len > 0) {
//         var textInstances = tempAllocator.create(std.BoundedArray(ios.TextInstanceData, ios.MAX_TEXT_INSTANCES)) catch {
//             std.log.warn("Failed to allocate text instances, skipping", .{});
//             return;
//         };
//         textInstances.len = 0;

//         var atlases = tempAllocator.create(std.BoundedArray(*bindings.Texture, ios.MAX_ATLASES)) catch {
//             std.log.warn("Failed to allocate text atlases, skipping", .{});
//             return;
//         };
//         atlases.len = 0;

//         // TODO: n^2 alert
//         for (renderQueue.texts.slice()) |t| {
//             const fontData = assets.getFontData(t.font) orelse continue;
//             const atlasTextureData = assets.getTextureData(.{ .Index = fontData.textureIndex }) orelse continue;
//             if (std.mem.indexOfScalar(*bindings.Texture, atlases.slice(), atlasTextureData.texture) == null) {
//                 atlases.append(atlasTextureData.texture) catch break;
//             }
//         }

//         for (renderQueue.texts.slice()) |t| {
//             const fontData = assets.getFontData(t.font) orelse continue;
//             const atlasTextureData = assets.getTextureData(.{ .Index = fontData.textureIndex }) orelse continue;
//             const atlasIndex = @intCast(u32, std.mem.indexOfScalar(*bindings.Texture, atlases.slice(), atlasTextureData.texture) orelse continue);

//             var pos = m.Vec2.init(t.baselineLeft.x, t.baselineLeft.y);
//             for (t.text) |c| {
//                 if (c == '\n') {
//                     textInstances.append(.{
//                         .color = toFloat4(t.color),
//                         .bottomLeft = toFloat2(m.Vec2.zero),
//                         .size = toFloat2(m.Vec2.zero),
//                         .uvBottomLeft = toFloat2(m.Vec2.zero),
//                         .atlasIndex = atlasIndex,
//                         .depth = t.depth,
//                         .atlasScale = fontData.scale,
//                         ._pad = undefined,
//                     }) catch break;
//                     pos.y -= fontData.lineHeight;
//                     pos.x = t.baselineLeft.x;
//                 } else {
//                     const charData = fontData.charData[c];
//                     textInstances.append(.{
//                         .color = toFloat4(t.color),
//                         .bottomLeft = toFloat2((m.add(pos, m.multScalar(charData.offset, fontData.scale)))),
//                         .size = toFloat2(m.multScalar(charData.size, fontData.scale)),
//                         .uvBottomLeft = toFloat2(charData.uvOffset),
//                         .atlasIndex = atlasIndex,
//                         .depth = t.depth,
//                         .atlasScale = fontData.scale,
//                         ._pad = undefined,
//                     }) catch break;
//                     pos.x += charData.advanceX * fontData.scale + fontData.kerning;
//                 }
//             }
//         }

//         const uniforms = ios.TextUniforms {
//             .screenSize = toFloat2(screenSize),
//         };
//         const instances = textInstances.slice();
//         const instanceBufferBytes = std.mem.sliceAsBytes(instances);
//         bindings.renderText(context, renderState.renderState, instances.len, instanceBufferBytes, atlases.slice(), &uniforms);
//     }
// }

// comptime {
//     std.debug.assert(@sizeOf(RenderEntryQuad) == 4 * 4 * 4 + 8 + 8 + 4 + 4 + 8);
//     std.debug.assert(@sizeOf(RenderEntryQuad) == @sizeOf(ios.QuadInstanceData));
// }
