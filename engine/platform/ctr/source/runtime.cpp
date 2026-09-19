#include <3ds.h>

#include <utilities/result.hpp>

#include <cerrno>
#include <cstdio>
#include <unistd.h>
#include <cstring>
#include <functional>
#include <memory>

extern "C"
{
    static void tryInit(std::function<love::ResultCode()> initFunction, love::AbortCode code)
    {
        if (!initFunction || love::g_EarlyExit)
            return;

        love::ResultCode result;
        if ((result = initFunction()); result.Success())
            return;

        /* Breadcrumb first: the error applet below needs a working
        ** framebuffer, and under a CIA the crash that follows when it has
        ** none used to hide which service failed (crash dump 20). */
        if (FILE* log = std::fopen("sdmc:/gen1_init.txt", "a"))
        {
            std::fprintf(log, "init failed: code=%d result=0x%08lx\n", (int)code, (uint32_t)result);
            std::fclose(log);
        }

        /* errorDisp -> aptLaunchSystemApplet -> aptScreenTransfer needs live
        ** framebuffers and crashes this early under a CIA even with
        ** gfxInitDefault (crash dumps 20, 21).  There the breadcrumb above is
        ** the report; only the Homebrew Launcher path shows the applet. */
        if (!envIsHomebrew())
        {
            love::g_EarlyExit = true;
            return;
        }
        gfxInitDefault();

        errorConf conf {};

        errorInit(&conf, ERROR_TEXT_WORD_WRAP, CFG_LANGUAGE_EN);
        errorCode(&conf, result);

        static char message[0x100] {};

        std::optional<const char*> header;
        if ((header = love::abortTypes.Find(code)))
            snprintf(message, sizeof(message), love::ABORT_FORMAT_KNOWN, *header, (int32_t)result,
                     R_LEVEL(result), R_SUMMARY(result), R_DESCRIPTION(result));

        errorText(&conf, message);
        errorDisp(&conf);
        gfxExit();

        love::g_EarlyExit = true;
    }

    void userAppInit()
    {
        osSetSpeedupEnable(true);

        tryInit(std::bind_front(romfsInit), love::ABORT_ROMFS);

        /* main.cpp hands boot.lua the relative source "game", which the
        ** Homebrew Launcher resolves against the 3dsx's own folder
        ** (sdmc:/3ds/game).  A CIA has no such folder and starts at the
        ** SD root, so pin the same working directory here; the game tree
        ** then lives in one place for both install methods. */
        if (!envIsHomebrew())
        {
            const int rc = chdir("sdmc:/3ds");
            char cwd[256] = "?";
            getcwd(cwd, sizeof(cwd));
            if (FILE* log = std::fopen("sdmc:/gen1_init.txt", "a"))
            {
                std::fprintf(log, "chdir(sdmc:/3ds) rc=%d errno=%d cwd=%s\n", rc, errno, cwd);
                std::fclose(log);
            }
        }

#if !defined(__EMULATION__)
        /* raw battery info */
        tryInit(std::bind_front(mcuHwcInit), love::ABORT_MCU_HWC);
#endif

        /* charging state */
        tryInit(std::bind_front(ptmuInit), love::ABORT_PTMU);

        /* region information and fonts */
        tryInit(std::bind_front(cfguInit), love::ABORT_CFGU);

        /* network state */
        tryInit(std::bind_front(acInit), love::ABORT_AC);

        /* friend code */
        tryInit(std::bind_front(frdInit, false), love::ABORT_FRD);

        /* theora video conversion */
        tryInit(std::bind_front(y2rInit), love::ABORT_Y2R);

        /* Memory layout breadcrumb: the 3dsx (Homebrew Launcher) and the CIA
        ** get different heap splits from libctru; compare the two runs. */
        extern u32 __ctru_heap_size, __ctru_linear_heap_size;
        if (FILE* log = std::fopen("sdmc:/gen1_init.txt", "a"))
        {
            std::fprintf(log, "%s: heap=%lu linear=%lu linearFree=%lu appRegion=%lu\n",
                         envIsHomebrew() ? "3dsx" : "cia", (unsigned long)__ctru_heap_size,
                         (unsigned long)__ctru_linear_heap_size, (unsigned long)linearSpaceFree(),
                         (unsigned long)osGetMemRegionSize(MEMREGION_APPLICATION));
            std::fclose(log);
        }
    }

    void userAppExit()
    {
        y2rExit();

        frdExit();

        acExit();

        cfguExit();

        ptmuExit();

        romfsExit();

#if !defined(__EMULATION__)
        mcuHwcExit();
#endif
    }
}
