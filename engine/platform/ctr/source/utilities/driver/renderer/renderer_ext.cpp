#include <utilities/driver/renderer_ext.hpp>
#include <utilities/driver/vertex_ext.hpp>

#include <common/exception.hpp>
#include <common/luax.hpp>
#include <common/math.hpp>

#include <algorithm>
#include <cstdarg>
#include <cstdio>

#include <3ds.h>

#include <objects/shader_ext.hpp>
#include <objects/texture_ext.hpp>

using namespace love;

static C3D_Mtx s_projection;
static C3D_Mtx s_modelView;
static bool s_dirtyProjection;
/* set by the APT ONEXIT hook (hid_ext.cpp): the app is closing from the HOME
** menu and has no gsp rights left -- every GPU entry point below becomes a
** no-op so the Lua quit path can still run to join its worker threads */
bool love_ctr_apt_closing = false;

static size_t s_queuedVertices; // in m_commands, not yet copied to m_vertices
static bool s_dirtySinceSplit;  // any DrawArrays since the last split/frame begin
static unsigned s_splitsThisFrame;
static unsigned s_peakVertices;

static std::optional<GPU_Primitive_t> s_primitive;
static PrimitiveType s_primitiveType;

Renderer<Console::CTR>::Renderer() : targets {}, currentTexture(nullptr)
{
    gfxInitDefault();
    gfxSet3D(true);

    if (!C3D_Init(C3D_DEFAULT_CMDBUF_SIZE))
        throw love::Exception("Failed to initialize citro3d!");

    C3D_CullFace(GPU_CULL_NONE);
    C3D_DepthTest(true, GPU_GEQUAL, GPU_WRITE_ALL);

    C3D_AttrInfo* attributes = C3D_GetAttrInfo();
    AttrInfo_Init(attributes);

    AttrInfo_AddLoader(attributes, 0, GPU_FLOAT, 3); // position
    AttrInfo_AddLoader(attributes, 1, GPU_FLOAT, 4); // color
    AttrInfo_AddLoader(attributes, 2, GPU_FLOAT, 2); // texcoord

    BufInfo_Init(&this->bufferInfo);
    m_vertices = (Vertex*)linearAlloc(TOTAL_BUFFER_SIZE);

    if (!m_vertices)
        throw love::Exception("Out of memory.");

    int result = BufInfo_Add(&this->bufferInfo, (void*)m_vertices, VERTEX_SIZE, 0x03, 0x210);
    C3D_SetBufInfo(&this->bufferInfo);

    if (result < 0)
        throw love::Exception("Failed to add C3D_BufInfo.");

    Mtx_Identity(&s_projection);
    Mtx_Identity(&s_modelView);
}

void Renderer<Console::CTR>::Shutdown()
{
    if (m_vertices == nullptr)
        return;

    linearFree(m_vertices);
    m_vertices = nullptr;

    /* run even when closing from HOME: gfxExit is what stops libctru's gsp
    ** event thread -- skipping it left that thread alive to data-abort when
    ** _exit unmapped the heap (crash dump 15).  The system grants enough
    ** gfx access during the close transition for this to finish (the
    ** zelda-tmc-3ds port does the same). */
    C3D_Fini();
    gfxExit();
}

Renderer<Console::CTR>::~Renderer()
{
    this->Shutdown();
}

Renderer<Console::CTR>::Info Renderer<Console::CTR>::GetRendererInfo()
{
    if (this->info.filled)
        return this->info;

    this->info.device  = Renderer::RENDERER_DEVICE;
    this->info.name    = Renderer::RENDERER_NAME;
    this->info.vendor  = Renderer::RENDERER_VENDOR;
    this->info.version = Renderer::RENDERER_VERSION;

    this->info.filled = true;

    return this->info;
}

void Renderer<Console::CTR>::CreateFramebuffers()
{
    for (uint8_t index = 0; index < this->targets.size(); index++)
        this->targets[index].Create((Screen)index);
}

void Renderer<Console::CTR>::DestroyFramebuffers()
{
    for (uint8_t index = 0; index < this->targets.size(); index++)
        this->targets[index].Destroy();
}

void Renderer<Console::CTR>::Clear(const Color& color)
{
    if (love_ctr_apt_closing)
        return;

    /* C3D_RenderTargetClear is a GX memory fill, not a P3D command: issued
    ** against a target already drawn to in the current frame it races the
    ** pending command list (fincs: FrameSplit is required before any clear/
    ** transfer of a target drawn this frame -- citro2d's C2D_TargetClear does
    ** exactly this dance).  Also behind lovepotion #276 (canvas drawing at
    ** 0,0 after love.graphics.clear).
    **
    ** Split ONLY when something was actually drawn since the last split: an
    ** empty command list enqueued to the GX queue is the citro3d issue #35
    ** GPU wedge, and a clear-heavy frame would flood the queue with them. */
    if (this->inFrame && s_dirtySinceSplit)
    {
        if (!m_commands.empty())
            FlushVertices();
        C3D_FrameSplit(0);
        s_dirtySinceSplit = false;
        ++s_splitsThisFrame;
    }

    C3D_RenderTargetClear(this->context.target, C3D_CLEAR_ALL, color.abgr(), 0);
}

/* todo */
void Renderer<Console::CTR>::ClearDepthStencil(int stencil, uint8_t mask, double depth)
{}

/* kept track of in Graphics<Console::CTR> */
void Renderer<Console::CTR>::SetBlendColor(const Color& color)
{}

void Renderer<Console::CTR>::EnsureInFrame()
{
    if (love_ctr_apt_closing)
        return;

    if (!this->inFrame)
    {
        C3D_FrameBegin(C3D_FRAME_SYNCDRAW);
        this->inFrame = true;
    }
}

void Renderer<Console::CTR>::BindFramebuffer(Texture<Console::ALL>* texture)
{
    if (love_ctr_apt_closing || !IsActiveScreenValid())
        return;

    this->EnsureInFrame();
    FlushVertices();

    /* Leaving a texture target with draws pending: submit that segment
    ** before any later pass samples the texture.  This is the barrier
    ** zelda-tmc-3ds keeps via C2D_TargetClear ("render-to-texture submission
    ** boundary ... whose removal caused the white and black screens") and
    ** citro2d apps get from the screen TargetClear between passes.  Guarded
    ** by s_dirtySinceSplit: an empty command list in the GX queue is the
    ** citro3d issue #35 wedge.  Hardware-only -- emulators do not model it. */
    const bool leavingTextureTarget =
        this->context.target != nullptr && !this->context.target->linked;
    if (leavingTextureTarget && s_dirtySinceSplit)
    {
        C3D_FrameSplit(0);
        s_dirtySinceSplit = false;
        ++s_splitsThisFrame;
    }

    /* Force the next textured draw to rebind: only C3D_TexBind makes citro3d
    ** re-emit GPUREG_TEXUNIT_CONFIG with the PICA texture-cache clear bit.
    ** Without it, a frame whose last bound texture is already the canvas
    ** samples STALE texels through the cache -- the frozen-with-old-content
    ** screen, also hardware-only. */
    this->currentTexture = nullptr;

    this->context.target = this->targets[love::GetActiveScreen()].GetTarget();
    Rect viewport        = this->targets[love::GetActiveScreen()].GetViewport();

    if (texture != nullptr && texture->IsRenderTarget())
    {
        auto* _texture       = (Texture<Console::CTR>*)texture;
        this->context.target = _texture->GetRenderTargetHandle();

        /* logical dims on purpose: the ortho this viewport drives and the
        ** V-flipped sampling in refreshQuad (texture_ext.cpp) agree on the
        ** logical rect inside the po2 texture.  (A po2 viewport was tried
        ** here and desynced the pair -- content rendered where the sampler
        ** never looks.) */
        viewport = { 0, 0, _texture->GetPixelWidth(), _texture->GetPixelHeight() };
    }

    C3D_FrameDrawOn(this->context.target);
    this->SetViewport(viewport, this->context.target->linked);
}

#include <utilities/debug/measure.hpp>
using namespace vertex::attributes;

void Renderer<Console::CTR>::FlushVertices()
{
    if (love_ctr_apt_closing)
    {
        m_commands.clear();
        s_queuedVertices = 0;
        return;
    }

    if (s_dirtyProjection)
    {
        const auto uniforms = Shader<Console::CTR>::current->GetUniformLocations();
        C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uniforms.uLocProjMtx, &s_projection);
        C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uniforms.uLocMdlView, &s_modelView);

        s_dirtyProjection = false;
    }

    s_queuedVertices = 0;

    for (const auto& command : m_commands)
    {
        std::memcpy(m_vertices + m_vertexOffset, command.Vertices().get(), command.size);
        SetTexEnvFunction(command.format);

        if (s_primitiveType != command.type)
        {
            if (!(s_primitive = primitiveModes.Find(command.type)))
                throw love::Exception("Invalid primitive mode");

            s_primitiveType = command.type;
        }

        ++drawCallsBatched;
        C3D_DrawArrays(*s_primitive, m_vertexOffset, command.count);
        m_vertexOffset += command.count;
        s_dirtySinceSplit = true;
    }

    m_commands.clear();
}

bool Renderer<Console::CTR>::Render(DrawCommand& command)
{
    /* a zero-vertex draw wedges the PICA200: the GX queue never retires the
    ** command list, and the next C3D_FrameBegin(SYNCDRAW) waits on it forever
    ** -- screen frozen, CPU alive.  Same root cause and fix as the
    ** zelda-tmc-3ds port ("zero-count draws, now never submitted"). */
    if (command.count == 0)
        return true;

    /* the vertex arena is per-frame (m_vertexOffset only resets in Present);
    ** a frame that outruns it must drop draws -- the old behavior memcpy'd
    ** past the buffer and corrupted the linear heap */
    if (m_vertexOffset + s_queuedVertices + command.count > (size_t)VERTEX_BUFFER_SIZE)
        return false;

    s_queuedVertices += command.count;

    Shader<Console::CTR>::defaults[command.shader]->Attach();

    // check if texture is the same, or no texture at all
    if (command.handles.empty() || (this->currentTexture == command.handles.back()))
    {
        ++drawCalls;
        m_commands.push_back(command.Clone());
        return true;
    }
    else
    {
        FlushVertices();

        if (!command.handles.empty())
        {
            if (this->currentTexture != command.handles.back())
                this->currentTexture = command.handles.back();

            C3D_TexBind(0, command.handles.back());
        }

        ++drawCalls;
        m_commands.push_back(command.Clone());
        return true;
    }

    return false;
}

void Renderer<Console::CTR>::Present()
{
    if (love_ctr_apt_closing)
    {
        m_commands.clear();
        m_vertexOffset   = 0;
        s_queuedVertices = 0;
        this->inFrame    = false;
        return;
    }

    if (this->inFrame)
    {
        FlushVertices();

        if (m_vertexOffset > s_peakVertices)
            s_peakVertices = m_vertexOffset;

        C3D_FrameEnd(0);

        m_vertexOffset = 0;
        s_dirtySinceSplit = false;
        s_splitsThisFrame = 0;

        this->inFrame = false;
    }

    Renderer<>::cpuTime = C3D_GetProcessingTime();
    Renderer<>::gpuTime = C3D_GetDrawingTime();

    for (size_t i = this->deferred.size(); i > 0; i--)
    {
        this->deferred[i - 1]();
        this->deferred.erase(deferred.begin() + i - 1);
    }
}

void Renderer<Console::CTR>::SetViewport(const Rect& rect, bool tilt)
{
    /* no early-out on this->viewport == rect: C3D_FrameDrawOn (called on
    ** every target switch in BindFramebuffer) resets the GPU viewport to the
    ** full target, so the cached rect does not describe the GPU state.  Two
    ** same-size canvases bound back to back left the second one rendering
    ** into its full po2 texture with a stale projection (title screen in the
    ** top-left corner, world drawn in 240x144 chunks -- seen on hardware). */
    this->viewport = rect;

    if (rect.h == GSP_SCREEN_WIDTH && tilt)
    {
        if (rect.w == GSP_SCREEN_HEIGHT_TOP || rect.w == GSP_SCREEN_HEIGHT_TOP_2X)
        {
            Mtx_Copy(&s_projection, &this->targets[0].GetProjView());
            s_dirtyProjection = true;
            return;
        }
        else if (rect.w == GSP_SCREEN_HEIGHT_BOTTOM)
        {
            Mtx_Copy(&s_projection, &this->targets[2].GetProjView());
            s_dirtyProjection = true;
            return;
        }
    }

    auto* ortho = tilt ? Mtx_OrthoTilt : Mtx_Ortho;
    ortho(&s_projection, 0.0f, rect.w, rect.h, 0.0f, Z_NEAR, Z_FAR, true);
    s_dirtyProjection = true;

    C3D_SetViewport(0, 0, rect.w, rect.h);
}

void Renderer<Console::CTR>::SetScissor(const Rect& scissor, bool canvasActive)
{
    /* draws are deferred into m_commands and the GPU scissor is immediate
    ** state: without a flush here every queued draw would be clipped by THIS
    ** scissor instead of the one it was issued under (lovepotion #275 -- only
    ** the last setScissor of the frame applied to everything).  Only when
    ** something is queued: a bare flush touches Shader::current, which is
    ** still null before the first draw of the program. */
    if (!m_commands.empty())
        FlushVertices();

    this->targets[love::GetActiveScreen()].SetScissor(scissor, canvasActive);
}

void Renderer<Console::CTR>::SetStencil(RenderState::CompareMode mode, int value)
{
    bool enabled = (mode == RenderState::COMPARE_ALWAYS) ? false : true;

    std::optional<GPU_TESTFUNC> compareOp;
    if (!(compareOp = Renderer::compareModes.Find(mode)))
        return;

    C3D_StencilTest(enabled, *compareOp, value, 0xFFFFFFFF, 0xFFFFFFFF);
    C3D_StencilOp(GPU_STENCIL_KEEP, GPU_STENCIL_KEEP, GPU_STENCIL_KEEP);
}

void Renderer<Console::CTR>::SetMeshCullMode(vertex::CullMode mode)
{
    std::optional<GPU_CULLMODE> cullMode;
    if (!(cullMode = Renderer::cullModes.Find(mode)))
        return;

    if (this->context.cullMode == mode)
        return;

    C3D_CullFace(*cullMode);
    this->context.cullMode = mode;
}

/* ??? */
void Renderer<Console::CTR>::SetVertexWinding(vertex::Winding winding)
{}

void Renderer<Console::CTR>::SetSamplerState(Texture<Console::CTR>* texture, SamplerState& state)
{
    /* set the min and mag filters */

    auto* handle = texture->GetHandle();

    std::optional<GPU_TEXTURE_FILTER_PARAM> mag;
    if (!(mag = Renderer::filterModes.Find(state.magFilter)))
        return;

    std::optional<GPU_TEXTURE_FILTER_PARAM> min;
    if (!(min = Renderer::filterModes.Find(state.minFilter)))
        return;

    C3D_TexSetFilter(handle, *mag, *min);

    /* set the wrapping modes */

    std::optional<GPU_TEXTURE_WRAP_PARAM> wrapU;
    if (!(wrapU = Renderer::wrapModes.Find(state.wrapU)))
        return;

    std::optional<GPU_TEXTURE_WRAP_PARAM> wrapV;
    if (!(wrapV = Renderer::wrapModes.Find(state.wrapV)))
        return;

    C3D_TexSetWrap(handle, *wrapU, *wrapV);
}

void Renderer<Console::CTR>::SetColorMask(const RenderState::ColorMask& mask)
{
    uint8_t writeMask = GPU_WRITE_DEPTH;
    writeMask |= mask.GetColorMask();

    if (this->context.colorMask == mask)
        return;

    this->context.colorMask = mask;
    C3D_DepthTest(true, GPU_GEQUAL, (GPU_WRITEMASK)writeMask);
}

void Renderer<Console::CTR>::SetBlendMode(const RenderState::BlendState& state)
{
    std::optional<GPU_BLENDEQUATION> opRGB;
    if (!(opRGB = Renderer::blendEquations.Find(state.operationRGB)))
        return;

    std::optional<GPU_BLENDEQUATION> opAlpha;
    if (!(opAlpha = Renderer::blendEquations.Find(state.operationA)))
        return;

    std::optional<GPU_BLENDFACTOR> srcColor;
    if (!(srcColor = Renderer::blendFactors.Find(state.srcFactorRGB)))
        return;

    std::optional<GPU_BLENDFACTOR> dstColor;
    if (!(dstColor = Renderer::blendFactors.Find(state.dstFactorRGB)))
        return;

    std::optional<GPU_BLENDFACTOR> srcAlpha;
    if (!(srcAlpha = Renderer::blendFactors.Find(state.srcFactorA)))
        return;

    std::optional<GPU_BLENDFACTOR> dstAlpha;
    if (!(dstAlpha = Renderer::blendFactors.Find(state.dstFactorA)))
        return;

    if (this->context.blendState == state)
        return;

    this->context.blendState = state;
    C3D_AlphaBlend(*opRGB, *opAlpha, *srcColor, *dstColor, *srcAlpha, *dstAlpha);
}
