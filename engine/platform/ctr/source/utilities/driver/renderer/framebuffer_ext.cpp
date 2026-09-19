#include <utilities/driver/framebuffer_ext.hpp>

#include <common/exception.hpp>

#include <algorithm>

extern "C" void love_ctr_trace(const char* fmt, ...); // renderer_ext.cpp

using namespace love;

Framebuffer<Console::CTR>::Framebuffer() : target(nullptr)
{}

void Framebuffer<Console::CTR>::Create(Screen screen)
{
    this->id = screen;
    Mtx_Identity(&this->modelView);

    switch (screen)
    {
        case Screen::LEFT:
        case Screen::RIGHT:
        {
            const auto side = (screen == Screen::LEFT) ? GFX_LEFT : GFX_RIGHT;
            this->SetSize(400, 240, GFX_TOP, side);
            break;
        }
        case Screen::BOTTOM:
        {
            this->SetSize(320, 240, GFX_BOTTOM, GFX_LEFT);
            break;
        }
        default:
            break; // shouldn't happen
    }
}

void Framebuffer<Console::CTR>::Destroy()
{
    if (this->target)
        C3D_RenderTargetDelete(this->target);

    this->target = nullptr;
}

void Framebuffer<Console::CTR>::SetSize(int width, int height, gfxScreen_t screen, gfx3dSide_t side)
{
    this->target = C3D_RenderTargetCreate(height, width, GPU_RB_RGBA8, GPU_RB_DEPTH16);

    if (this->target)
        C3D_RenderTargetSetOutput(this->target, screen, side, Framebuffer::DISPLAY_FLAGS);
    else
    {
        const auto name = std::string(love::GetScreenName(this->id));
        throw love::Exception("Failed to allocate framebuffer %s", name.c_str());
    }

    this->width  = width;
    this->height = height;

    this->viewport = { 0, 0, width, height };
    this->scissor  = { 0, 0, width, height };

    Mtx_OrthoTilt(&this->projView, 0, width, height, 0, Z_NEAR, Z_FAR, true);
    this->SetScissor();
}

const Rect Framebuffer<Console::CTR>::CalculateBounds(const Rect& bounds)
{
    // clang-format off
    const uint32_t left   = this->height > (bounds.y + bounds.h) ? this->height - (bounds.y + bounds.h) : 0;
    const uint32_t top    = this->width  > (bounds.x + bounds.w) ? this->width - (bounds.x + bounds.w) : 0;
    const uint32_t right  = this->height - bounds.y;
    const uint32_t bottom = this->width  - bounds.x;
    // clang-format on

    return { (int)left, (int)top, (int)right, (int)bottom };
}

void Framebuffer<Console::CTR>::SetViewport(const Rect& viewport, bool canvasActive)
{
    Rect newViewport = viewport;
    if (viewport == Rect::EMPTY)
        newViewport = this->viewport;

    Mtx_OrthoTilt(&this->projView, newViewport.x, newViewport.w, newViewport.h, newViewport.y,
                  Z_NEAR, Z_FAR, true);
}

void Framebuffer<Console::CTR>::SetScissor(const Rect& scissor, bool canvasActive)
{
    if (scissor == Rect::EMPTY)
    {
        C3D_SetScissor(GPU_SCISSOR_DISABLE, 0, 0, 0, 0);
        return;
    }

    if (canvasActive)
    {
        /* a canvas target renders through plain Mtx_Ortho into the po2
        ** texture with its own V convention; none of the rotation math below
        ** applies, and the correct mapping has not been validated on
        ** hardware yet.  An oversized clip beats a wrong one: zone passes
        ** just colorize a little past their band. */
        C3D_SetScissor(GPU_SCISSOR_DISABLE, 0, 0, 0, 0);
        return;
    }

    /* the physical framebuffer is the screen rotated 90°: BOTH axes flip.
    ** Canonical devkitPro mapping for a top-left screen rect (x, y, w, h) on
    ** a W x 240 screen:
    **   C3D_SetScissor(NORMAL, 240-(y+h), W-(x+w), 240-y, W-x)
    ** (same formula upstream computed in CalculateBounds; upstream's bug was
    ** the argument ORDER it then passed to C3D_SetScissor).  The register
    ** fields are unsigned 10-bit, so everything clamps to the framebuffer --
    ** a negative would wrap into a garbage clip region. */
    const int fbWidth  = this->height;
    const int fbHeight = this->width;

    const auto left   = std::clamp(fbWidth - (scissor.y + scissor.h), 0, fbWidth);
    const auto top    = std::clamp(fbHeight - (scissor.x + scissor.w), 0, fbHeight);
    const auto right  = std::clamp(fbWidth - scissor.y, 0, fbWidth);
    const auto bottom = std::clamp(fbHeight - scissor.x, 0, fbHeight);

    love_ctr_trace("scissor in=%d,%d,%dx%d out=%d,%d,%d,%d%s\n",
                   scissor.x, scissor.y, scissor.w, scissor.h,
                   left, top, right, bottom,
                   (left >= right || top >= bottom) ? " EMPTY" : "");

    if (left >= right || top >= bottom)
    {
        /* empty region: NORMAL mode cannot express it (fields underflow), so
        ** exclude the whole framebuffer instead */
        C3D_SetScissor(GPU_SCISSOR_INVERT, 0, 0, fbWidth, fbHeight);
        return;
    }

    C3D_SetScissor(GPU_SCISSOR_NORMAL, left, top, right, bottom);
}

void Framebuffer<Console::CTR>::UseProjection(Shader<Console::CTR>::Uniforms uniforms)
{
    C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uniforms.uLocProjMtx, &this->projView);
    C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uniforms.uLocMdlView, &this->modelView);
}