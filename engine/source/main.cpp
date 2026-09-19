#include <algorithm>
#include <common/console.hpp>
#include <common/luax.hpp>
#include <common/variant.hpp>
#include <utilities/result.hpp>

#include <modules/love/love.hpp>
#include <string.h>
#include <unistd.h>

#if defined(__3DS__)
    #include <utilities/driver/dsp_ext.hpp>
    #include <utilities/driver/renderer_ext.hpp>
    #include <3ds.h>
extern "C" void userAppExit(void);
#endif

using namespace love;

DoneAction RunLOVE(int argc, char** argv, int& retval, Variant& restartValue)
{
    /* make a new lua state */
    lua_State* L = luaL_newstate();
    luaL_openlibs(L);

    luaopen_bit(L);

    /* register in package.loaded so require("bit") resolves (the global
    ** alone leaves require failing, pushing callers onto slow fallbacks) */
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "loaded");
    lua_getglobal(L, "bit");
    lua_setfield(L, -2, "bit");
    lua_pop(L, 2);

    /* preload "love" */
    luax::Preload(L, love::Initialize, "love");

    {
        lua_newtable(L);

        if (argc > 0)
        {
            lua_pushstring(L, argv[0]);
            lua_rawseti(L, -2, -2);
        }
        else
        {
            /* A CIA title gets no argv.  boot.lua takes the lowest arg index
            ** as the executable path and love.filesystem.init() refuses an
            ** empty one, so without this a CIA quits before its first frame
            ** with nothing on screen.  Any path on the SD works: it only
            ** seeds PhysFS' base directory (the save dir comes from cwd). */
            lua_pushstring(L, "sdmc:/3ds/gen1recomp.3dsx");
            lua_rawseti(L, -2, -2);
        }

        /* arg[1..] = argv[1..] then the game folder.  Skip argv[0] by
        ** position, not by starting the copy at index 1: with argc == 0 (a
        ** CIA title) the old loop copied nothing and "game" never reached
        ** arg[1], so boot.lua showed the no-game screen (CIA breadcrumb:
        ** "tried=nil"). */
        std::vector<const char*> args(argv + std::min(argc, 1), argv + argc);
        args.push_back("game");

        lua_pushstring(L, "embedded boot.lua");
        lua_rawseti(L, -2, -1);

        for (int index = 0; index < (int)args.size(); index++)
        {
            lua_pushstring(L, args[index]);
            lua_rawseti(L, -2, index + 1);
        }

        lua_setglobal(L, "arg");
    }

    /* require "love" */
    lua_getglobal(L, "require");
    lua_pushstring(L, "love");
    lua_call(L, 1, 1);

    /* love.restart = value, clear it */
    luax::PushVariant(L, restartValue);
    lua_setfield(L, -2, "restart");
    restartValue = Variant();

    /* pop the love table */
    lua_pop(L, 1);

    /* boot! */
    lua_getglobal(L, "require");
    lua_pushstring(L, "love.boot");
    lua_call(L, 1, 1);

    /* put this on a new lua thread */
    lua_newthread(L);
    lua_pushvalue(L, -2);

    int stackPosition = lua_gettop(L);

    /* execute the main loop */
    while (love::MainLoop<Console::Which>(L, 0))
        lua_pop(L, lua_gettop(L) - stackPosition);

    retval          = 0;
    DoneAction done = DoneAction::DONE_QUIT;

    int returnIndex = stackPosition;
    if (!lua_isnoneornil(L, returnIndex))
    {
        if (lua_type(L, returnIndex) == LUA_TSTRING &&
            strcmp(lua_tostring(L, returnIndex), "restart") == 0)
        {
            done = DONE_RESTART;
        }

        if (lua_isnumber(L, returnIndex))
            retval = lua_tonumber(L, returnIndex);

        if (returnIndex < lua_gettop(L))
            restartValue = luax::CheckVariant(L, returnIndex + 1, false);
    }

#if defined(__3DS__)
    /* HOME-menu close: aptMainLoop() already returned false (that is what
    ** broke the loop above -- Lua never saw a quit event, so game worker
    ** threads never got their shutdown message).  lua_close would then join
    ** those threads and hang until the system force-kills the process (the
    ** crash dumps on exit).  The system is waiting for us to die: tear down
    ** services and leave now; svcExitProcess reaps the threads.  On a normal
    ** in-game quit aptMainLoop() is still true and this is skipped. */
    if (!aptMainLoop())
    {
        DSP<Console::Which>::Instance().Shutdown();
        Renderer<Console::Which>::Instance().Shutdown();
        love::OnExit<Console::Which>();
        userAppExit();
        fflush(NULL);
        /* NOT svcExitProcess: under hbloader that raises the system's
        ** "error has occurred, forcing the software to close" dialog and
        ** reboots the console.  _exit is the loader-sanctioned path; every
        ** thread must already be dead by here (love.quit joins the game
        ** workers -- including from the error screen -- and the shutdowns
        ** above stop the ndsp and gsp threads). */
        _exit(0);
    }
#endif

    lua_close(L);

    return done;
}

int main(int argc, char** argv)
{
    love::PreInit<Console::Which>();

    if (love::g_EarlyExit)
    {
        love::OnExit<Console::Which>();
#if defined(__3DS__)
        /* same reason as the tail of main(): the static destructor chain
        ** data-aborts on this console, so leave without running it */
        fflush(NULL);
        _exit(0);
#endif
        return 0;
    }

    DoneAction done = love::DONE_QUIT;
    int returnValue = 0;
    Variant restartValue;

    do
    {
        done = RunLOVE(argc, argv, returnValue, restartValue);

#if defined(__3DS__)
        /* an in-game HOME-menu close runs the game's quit path, which asks
        ** for DONE_RESTART (quit-to-launcher); honoring it would boot a whole
        ** new Lua session while the system waits for the process to die.
        ** The workers are already joined by that quit path, so just leave. */
        if (done != love::DONE_QUIT && !aptMainLoop())
            done = love::DONE_QUIT;
#endif
    } while (done != love::DONE_QUIT);

    love::OnExit<Console::Which>();

#if defined(__3DS__)
    /* Returning normally runs the C++ static destructor chain, and one of
    ** those destructors data-aborts on the 3DS (a 64-bit division with the
    ** stack already torn down -- crash on every exit to the HOME menu,
    ** observed on hardware).  Skipping them with _exit also skips the DSP
    ** singleton's destructor, whose ndspExit is what stops the ndsp worker
    ** thread -- which then aborted on its own (ndspiReadChnState, also
    ** observed).  So: stop the audio driver explicitly, then leave without
    ** touching the rest of the destructor chain. */
    /* the canonical homebrew exit order: audio thread first, then citro3d +
    ** the gfx service, then the system services userAppExit closes -- all of
    ** which normally live in destructors/atexit handlers that _exit skips */
    {
        DSP<Console::Which>::Instance().Shutdown();
        Renderer<Console::Which>::Instance().Shutdown();
        userAppExit();
    }
    fflush(NULL);
    /* same rationale as the fast-exit path above */
    _exit(returnValue);
#endif

    return returnValue;
}
