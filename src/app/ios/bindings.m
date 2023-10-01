#include "bindings.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include "AppViewController.h"

struct RenderState2
{
    // quads
    id<MTLBuffer> quadInstanceBuffer;
    id<MTLBuffer> quadUniformBuffer;
    id<MTLRenderPipelineState> quadPipelineState;
    // textured quads
    id<MTLBuffer> texQuadInstanceBuffer;
    id<MTLBuffer> texQuadUniformBuffer;
    id<MTLRenderPipelineState> texQuadPipelineState;
    // text
    id<MTLBuffer> textInstanceBuffer;
    id<MTLBuffer> textUniformBuffer;
    id<MTLRenderPipelineState> textPipelineState;
};

void iosLog(const char* string)
{
    NSLog(@"%@", @(string));
}

struct Slice getResourcePath()
{
    // TODO this probably leaks memory
    NSString* resourcePath = [[NSBundle mainBundle] resourcePath];
    NSData* data = [resourcePath dataUsingEncoding:NSUTF8StringEncoding];
    struct Slice slice = {
        .size = 0,
        .data = NULL,
    };
    slice.size = [data length];
    slice.data = (uint8_t*)[data bytes];
    return slice;
}

struct Buffer* createBuffer(void* context, uint64_t length)
{
    AppViewController* controller = (AppViewController*)context;
    id<MTLBuffer> buffer = [
        controller.device
        newBufferWithLength:length
        options:MTLResourceCPUCacheModeDefaultCache
    ];
    if (buffer == nil) {
        return nil;
    }
    return (struct Buffer*)buffer;
}

struct Texture* createAndLoadTexture(void* context, uint32_t width, uint32_t height, enum TextureFormat format, const void* data)
{
    AppViewController* controller = (AppViewController*)context;

    MTLTextureDescriptor* textureDescriptor = [[MTLTextureDescriptor alloc] init];
    uint32_t channels = 4;
    switch (format) {
    case R8: {
        channels = 1;
        textureDescriptor.pixelFormat = MTLPixelFormatR8Unorm;
    } break;
    case RGBA8: {
        textureDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
    } break;
    case BGRA8: {
        textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
    } break;
    }
    textureDescriptor.width = width;
    textureDescriptor.height = height;
    id<MTLTexture> texture = [controller.device newTextureWithDescriptor:textureDescriptor];
    if (texture == nil) {
        return nil;
    }

    const MTLRegion region = {
        { 0, 0, 0 },
        {width, height, 1}
    };
    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:data
               bytesPerRow:width * channels];
    return (struct Texture*)texture;
}

struct Texture* createAndLoadTextureR8(void* context, uint32_t width, uint32_t height, const void* data)
{
    AppViewController* controller = (AppViewController*)context;

    MTLTextureDescriptor* textureDescriptor = [[MTLTextureDescriptor alloc] init];
    textureDescriptor.pixelFormat = MTLPixelFormatR8Unorm;
    textureDescriptor.width = width;
    textureDescriptor.height = height;
    id<MTLTexture> texture = [controller.device newTextureWithDescriptor:textureDescriptor];
    if (texture == nil) {
        return nil;
    }

    const MTLRegion region = {
        { 0, 0, 0 },
        {width, height, 1}
    };
    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:data
               bytesPerRow:width];
    return (struct Texture*)texture;
}

struct Texture* createAndLoadTextureBGRA8(void* context, uint32_t width, uint32_t height, const void* data)
{
    AppViewController* controller = (AppViewController*)context;

    MTLTextureDescriptor* textureDescriptor = [[MTLTextureDescriptor alloc] init];
    textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
    textureDescriptor.width = width;
    textureDescriptor.height = height;
    id<MTLTexture> texture = [controller.device newTextureWithDescriptor:textureDescriptor];
    if (texture == nil) {
        return nil;
    }

    const MTLRegion region = {
        { 0, 0, 0 },
        {width, height, 1}
    };
    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:data
               bytesPerRow:width * 4];
    return (struct Texture*)texture;
}

struct RenderState2* createRenderState(void* context)
{
    AppViewController* controller = (AppViewController*)context;

    // Quads
    id<MTLBuffer> quadInstanceBuffer;
    id<MTLBuffer> quadUniformBuffer;
    id<MTLRenderPipelineState> quadPipelineState;
    {
        quadInstanceBuffer = [
            controller.device
            newBufferWithLength:sizeof(struct QuadInstanceData) * MAX_QUADS
            options:MTLResourceCPUCacheModeDefaultCache
        ];
        if (quadInstanceBuffer == nil) {
            NSLog(@"ZIG.m error creating quad instance buffer");
            return nil;
        }

        quadUniformBuffer = [
            controller.device
            newBufferWithLength:sizeof(struct QuadUniforms)
            options:MTLResourceCPUCacheModeDefaultCache
        ];
        if (quadUniformBuffer == nil) {
            NSLog(@"ZIG.m error creating quad uniform buffer");
            return nil;
        }

        MTLRenderPipelineDescriptor* renderPipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        renderPipelineDescriptor.vertexFunction = [controller.library newFunctionWithName:@"quadVertMain"];
        renderPipelineDescriptor.fragmentFunction = [controller.library newFunctionWithName:@"quadFragMain"];
        MTLRenderPipelineColorAttachmentDescriptor* attachment = renderPipelineDescriptor.colorAttachments[0];
        attachment.pixelFormat = controller.metalLayer.pixelFormat;
        attachment.blendingEnabled = YES;
        attachment.rgbBlendOperation = MTLBlendOperationAdd;
        attachment.alphaBlendOperation = MTLBlendOperationAdd;
        attachment.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        attachment.sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        attachment.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        attachment.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

        NSError* error;
        quadPipelineState = [
            controller.device
            newRenderPipelineStateWithDescriptor:renderPipelineDescriptor
            error:&error
        ];
        if (quadPipelineState == nil) {
            NSLog(@"ZIG.m error creating quad render pipeline state: %@", error);
            return nil;
        }
    }

    // Textured quads
    id<MTLBuffer> texQuadInstanceBuffer;
    id<MTLBuffer> texQuadUniformBuffer;
    id<MTLRenderPipelineState> texQuadPipelineState;
    {
        texQuadInstanceBuffer = [
            controller.device
            newBufferWithLength:sizeof(struct TexQuadInstanceData) * MAX_TEX_QUADS
            options:MTLResourceCPUCacheModeDefaultCache
        ];
        if (texQuadInstanceBuffer == nil) {
            NSLog(@"ZIG.m error creating tex quad instance buffer");
            return nil;
        }

        texQuadUniformBuffer = [
            controller.device
            newBufferWithLength:sizeof(struct QuadUniforms)
            options:MTLResourceCPUCacheModeDefaultCache
        ];
        if (texQuadUniformBuffer == nil) {
            NSLog(@"ZIG.m error creating tex quad uniform buffer");
            return nil;
        }

        MTLRenderPipelineDescriptor* renderPipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        renderPipelineDescriptor.vertexFunction = [controller.library newFunctionWithName:@"texQuadVertMain"];
        renderPipelineDescriptor.fragmentFunction = [controller.library newFunctionWithName:@"texQuadFragMain"];
        MTLRenderPipelineColorAttachmentDescriptor* attachment = renderPipelineDescriptor.colorAttachments[0];
        attachment.pixelFormat = controller.metalLayer.pixelFormat;
        attachment.blendingEnabled = YES;
        attachment.rgbBlendOperation = MTLBlendOperationAdd;
        attachment.alphaBlendOperation = MTLBlendOperationAdd;
        attachment.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        attachment.sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        attachment.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        attachment.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

        NSError* error;
        texQuadPipelineState = [
            controller.device
            newRenderPipelineStateWithDescriptor:renderPipelineDescriptor
            error:&error
        ];
        if (texQuadPipelineState == nil) {
            NSLog(@"ZIG.m error creating textured quad render pipeline state: %@", error);
            return nil;
        }
    }

    // Text
    id<MTLBuffer> textInstanceBuffer;
    id<MTLBuffer> textUniformBuffer;
    id<MTLRenderPipelineState> textPipelineState;
    {
        textInstanceBuffer = [
            controller.device
            newBufferWithLength:sizeof(struct TextInstanceData) * MAX_TEXT_INSTANCES
            options:MTLResourceCPUCacheModeDefaultCache
        ];
        if (textInstanceBuffer == nil) {
            NSLog(@"ZIG.m error creating text instance buffer");
            return nil;
        }

        textUniformBuffer = [
            controller.device
            newBufferWithLength:sizeof(struct TextUniforms)
            options:MTLResourceCPUCacheModeDefaultCache
        ];
        if (textUniformBuffer == nil) {
            NSLog(@"ZIG.m error creating text uniform buffer");
            return nil;
        }

        MTLRenderPipelineDescriptor* renderPipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        renderPipelineDescriptor.vertexFunction = [controller.library newFunctionWithName:@"textVertMain"];
        renderPipelineDescriptor.fragmentFunction = [controller.library newFunctionWithName:@"textFragMain"];
        MTLRenderPipelineColorAttachmentDescriptor* attachment = renderPipelineDescriptor.colorAttachments[0];
        attachment.pixelFormat = controller.metalLayer.pixelFormat;
        attachment.blendingEnabled = YES;
        attachment.rgbBlendOperation = MTLBlendOperationAdd;
        attachment.alphaBlendOperation = MTLBlendOperationAdd;
        attachment.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        attachment.sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        attachment.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        attachment.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

        NSError* error;
        textPipelineState = [
            controller.device
            newRenderPipelineStateWithDescriptor:renderPipelineDescriptor
            error:&error
        ];
        if (textPipelineState == nil) {
            NSLog(@"ZIG.m error creating text render pipeline state: %@", error);
            return nil;
        }
    }

    struct RenderState2* renderState = (struct RenderState2*)malloc(sizeof(struct RenderState2));
    if (renderState == NULL) {
        NSLog(@"ZIG.m Failed to allocate RenderState2");
        return nil;
    }
    renderState->quadInstanceBuffer = quadInstanceBuffer;
    renderState->quadUniformBuffer = quadUniformBuffer;
    renderState->quadPipelineState = quadPipelineState;
    renderState->texQuadInstanceBuffer = texQuadInstanceBuffer;
    renderState->texQuadUniformBuffer = texQuadUniformBuffer;
    renderState->texQuadPipelineState = texQuadPipelineState;
    renderState->textInstanceBuffer = textInstanceBuffer;
    renderState->textUniformBuffer = textUniformBuffer;
    renderState->textPipelineState = textPipelineState;

    return renderState;
}

void renderQuads(void* context, const struct RenderState2* renderState, size_t instances, size_t bufferDataLength, const void* bufferData, float screenWidth, float screenHeight)
{
    AppViewController* controller = (AppViewController*)context;
    if (controller.renderCommandEncoder == nil) {
        NSLog(@"renderRect called outside of frame draw");
        return;
    }

    memcpy([renderState->quadInstanceBuffer contents], bufferData, bufferDataLength);
    const struct QuadUniforms uniforms = {
        .screenSize = {
            .x = screenWidth,
            .y = screenHeight,
        },
    };
    memcpy([renderState->quadUniformBuffer contents], &uniforms, sizeof(struct QuadUniforms));

    const id<MTLRenderCommandEncoder> encoder = controller.renderCommandEncoder;
    [encoder setRenderPipelineState:renderState->quadPipelineState];
    [encoder setVertexBuffer:renderState->quadInstanceBuffer offset:0 atIndex:0];
    [encoder setVertexBuffer:renderState->quadUniformBuffer offset:0 atIndex:1];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:6
              instanceCount:instances];
}

void renderTexQuads(void* context, const struct RenderState2* renderState, size_t instances, size_t bufferDataLength, const void* bufferData, const struct Texture** textures, float screenWidth, float screenHeight)
{
    AppViewController* controller = (AppViewController*)context;
    if (controller.renderCommandEncoder == nil) {
        NSLog(@"renderRect called outside of frame draw");
        return;
    }

    memcpy([renderState->texQuadInstanceBuffer contents], bufferData, bufferDataLength);
    const struct QuadUniforms uniforms = {
        .screenSize = {
            .x = screenWidth,
            .y = screenHeight,
        },
    };
    memcpy([renderState->texQuadUniformBuffer contents], &uniforms, sizeof(struct QuadUniforms));

    const id<MTLRenderCommandEncoder> encoder = controller.renderCommandEncoder;
    [encoder setRenderPipelineState:renderState->texQuadPipelineState];
    [encoder setVertexBuffer:renderState->texQuadInstanceBuffer offset:0 atIndex:0];
    [encoder setVertexBuffer:renderState->texQuadUniformBuffer offset:0 atIndex:1];
    for (size_t i = 0; i < instances; i++) {
        [encoder setFragmentTexture:(id<MTLTexture>)textures[i] atIndex:0];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                    vertexStart:0
                    vertexCount:6
                  instanceCount:1
                   baseInstance:i];
    }
}

void renderText(void* context, const struct RenderState2* renderState, size_t instances, size_t bufferDataLength, const void* bufferData, size_t numAtlases, const struct Texture** atlases, const struct TextUniforms* textUniforms)
{
    AppViewController* controller = (AppViewController*)context;
    if (controller.renderCommandEncoder == nil) {
        NSLog(@"renderRect called outside of frame draw");
        return;
    }

    memcpy([renderState->textInstanceBuffer contents], bufferData, bufferDataLength);
    memcpy([renderState->textUniformBuffer contents], textUniforms, sizeof(struct TextUniforms));

    const id<MTLRenderCommandEncoder> encoder = controller.renderCommandEncoder;
    [encoder setRenderPipelineState:renderState->textPipelineState];
    [encoder setVertexBuffer:renderState->textInstanceBuffer offset:0 atIndex:0];
    [encoder setVertexBuffer:renderState->textUniformBuffer offset:0 atIndex:1];
    for (size_t i = 0; i < numAtlases; i++) {
        [encoder setFragmentTexture:(id<MTLTexture>)atlases[i] atIndex:i];
    }
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                vertexStart:0
                vertexCount:6
              instanceCount:instances];
}

void setKeyboardVisible(void* context, int visible)
{
    AppViewController* controller = (AppViewController*)context;

    if (visible != 0 && controller.dummyTextView == nil) {
        CGRect rect;
        rect.origin.x = 0;
        rect.origin.y = 0;
        rect.size.width = 0;
        rect.size.height = 0;
        controller.dummyTextView = [[DummyTextView alloc] initWithFrame:rect];
        controller.dummyTextView.controller = controller;
        // dummyTextView.hidden = YES;
        [controller.view addSubview:controller.dummyTextView];
        [controller.dummyTextView becomeFirstResponder];
    }
    else if (visible == 0 && controller.dummyTextView != nil) {
        [controller.dummyTextView resignFirstResponder];
        [controller.dummyTextView release];
        controller.dummyTextView = nil;
    }
}

void httpRequest(void* context, enum HttpMethod method, struct Slice url, struct Slice body)
{
    AppViewController* controller = (AppViewController*)context;
    const struct Slice nullSlice = {
        .size = 0,
        .data = NULL,
    };

    NSURLSessionConfiguration* conf = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession* session = [NSURLSession sessionWithConfiguration:conf];

    @try {
        NSString* urlString = [[NSString alloc] initWithBytes:url.data length:url.size encoding:NSUTF8StringEncoding];
        NSURL* url = [NSURL URLWithString:urlString];
        NSMutableURLRequest* request = [[NSMutableURLRequest alloc] init];
        [request setURL:url];
        [request setHTTPMethod:@"GET"];
        // [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
        // [request setHTTPBody:postData];
        NSURLSessionDataTask* task = [session dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
            NSData* urlStringUtf8 = [urlString dataUsingEncoding:NSUTF8StringEncoding];
            const struct Slice urlSlice = {
                .size = urlStringUtf8.length,
                .data = (uint8_t*)urlStringUtf8.bytes,
            };
            const struct Slice responseBodySlice = {
                .size = data.length,
                .data = (uint8_t*)data.bytes,
            };
            onHttp(controller.data, 1, method, urlSlice, responseBodySlice);
        }];
        [task resume];
    } @catch (id exception) {
        onHttp(controller.data, 0, method, url, nullSlice);
    }
}
