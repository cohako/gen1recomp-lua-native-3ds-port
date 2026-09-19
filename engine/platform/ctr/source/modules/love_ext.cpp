#include "common/luax.hpp"

#include "modules/love/love.hpp"

#include <3ds.h>

#include <utilities/driver/hid_ext.hpp>

extern bool love_ctr_apt_closing;                   // renderer_ext.cpp

using namespace love;

static constexpr int SOC_BUFFER_SIZE  = 0x100000;
static constexpr int SOC_BUFFER_ALIGN = 0x1000;

static inline uint32_t* socBuffer = nullptr;

template<>
void love::PreInit<Console::CTR>()
{
    socBuffer = (uint32_t*)aligned_alloc(SOC_BUFFER_ALIGN, SOC_BUFFER_SIZE);
    socInit(socBuffer, SOC_BUFFER_SIZE);
}

template<>
bool love::MainLoop<Console::CTR>(lua_State* L, int numArgs)
{
    if (luax::Resume(L, numArgs) != LUA_YIELD)
        return false;

    if (aptMainLoop())
        return true;

    /* APT wants the app closed and the ONEXIT hook queued love's quit event
    ** during that very aptMainLoop call -- the old `Resume && aptMainLoop`
    ** broke the loop in the same iteration, so Lua never ran love.quit and
    ** game worker threads never got their shutdown message.  On 3dsx _exit
    ** unmaps the heap, so a thread still parked on its heap stack data-aborts
    ** (the on-every-HOME-close crash dumps).  Give Lua a bounded number of
    ** frames to run its quit path and join those threads. */
    static int graceFrames = 0;
    if (graceFrames == 0)
    {

        /* the APTHOOK_ONEXIT hook did NOT fire on a HOME-menu close under
        ** hbloader (verified by close-log on hardware), so neither the
        ** closing flag nor love's quit event can rely on it.  Do both here,
        ** at the first aptMainLoop()==false: the flag turns the renderer
        ** into a no-op (the app has no gsp rights anymore -- the next
        ** present would block forever, which was the eternal "closing..."),
        ** and the quit event is what actually runs the game's shutdown. */
        love_ctr_apt_closing = true;
        HID<Console::CTR>::Instance().SendQuit();
    }
    return (++graceFrames < 300);
}

template<>
void love::OnExit<Console::CTR>()
{
    socExit();

    if (socBuffer)
        free(socBuffer);
}
