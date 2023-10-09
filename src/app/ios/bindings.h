#pragma once

#include <stddef.h>
#include <stdint.h>

#include "shader_defs.h"

enum TextureFormat
{
    R8,
    RGBA8,
    BGRA8,
};

enum HttpMethod
{
    HTTP_GET,
    HTTP_POST,
    HTTP_UNSUPPORTED,
};

struct Slice
{
    size_t size;
    uint8_t* data;
};

struct Buffer;
struct Texture;
struct RenderState;
struct RenderState2;

void iosLog(const char* string);

struct Slice getResourcePath(void);

struct Texture* createAndLoadTexture(void* context, uint32_t width, uint32_t height, enum TextureFormat format, const void* data);

struct Texture* createAndLoadTextureR8(void* context, uint32_t width, uint32_t height, const void* data);

struct Texture* createAndLoadTextureBGRA8(void* context, uint32_t width, uint32_t height, const void* data);

struct RenderState2* createRenderState(void* context);

void renderQuads(void* context, const struct RenderState2* renderState, size_t instances, size_t bufferDataLength, const void* bufferData, float screenWidth, float screenHeight);

void renderTexQuads(void* context, const struct RenderState2* renderState, size_t instances, size_t bufferDataLength, const void* bufferData, const struct Texture** textures, float screenWidth, float screenHeight);

void renderText(void* context, const struct RenderState2* renderState, size_t instances, size_t bufferDataLength, const void* bufferData, size_t numAtlases, const struct Texture** atlases, const struct TextUniforms* textUniforms);

void setKeyboardVisible(void* context, int visible);

void httpRequest(void* context, enum HttpMethod method, struct Slice url, struct Slice body);

uint32_t getStatusBarHeight(void* context);

int openDocumentReader(void* context, struct Slice docPath, uint32_t marginTop, uint32_t marginBottom);
void closeDocumentReader(void* context);

void openUrl(void* context, struct Slice url);

void setClipboardContents(void* context, struct Slice string);

enum TouchType
{
    TOUCH_TYPE_UNKNOWN,
    TOUCH_TYPE_DIRECT,
    TOUCH_TYPE_UNSUPPORTED
};

enum TouchPhase
{
    TOUCH_PHASE_UNKNOWN,
    TOUCH_PHASE_BEGIN,
    TOUCH_PHASE_STATIONARY,
    TOUCH_PHASE_MOVE,
    TOUCH_PHASE_END,
    TOUCH_PHASE_CANCEL,
    TOUCH_PHASE_UNSUPPORTED
};

struct TouchEvent
{
    unsigned long id;
    uint32_t x, y;
    uint32_t tapCount;
    enum TouchType type;
    enum TouchPhase phase;
};

void* onStart(void* context, uint32_t screenWidth, uint32_t screenHeight, double scale);
void TODO_onExit(void* context, void* data);

void onTouchEvents(void* data, uint32_t length, const struct TouchEvent* touchEvents);
void onTextUtf32(void* data, uint32_t length, const uint32_t* utf32);

void onHttp(void* data, int success, enum HttpMethod method, struct Slice url, struct Slice responseBody);

int updateAndRender(void* context, void* data, uint32_t screenWidth, uint32_t screenHeight);
int appMain(int argc, char* argv[]);
