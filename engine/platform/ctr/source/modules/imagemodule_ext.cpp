#include <modules/image/imagemodule.hpp>

#include <common/color.hpp>
#include <common/exception.hpp>
#include <common/math.hpp>
#include <common/pixelformat.hpp>

#include <utilities/formathandler/types/pnghandler.hpp>

#include <algorithm>
#include <cstring>

using namespace love;

namespace
{
    /* PNGHandler hands back linear RGBA rows.  ImageData on this console keeps
    ** its pixels the way the PICA200 samples them: 8x8 tiles inside a
    ** power-of-two buffer, one ABGR word per texel (see setPixelRGBA8 and
    ** Color::FromTile).  Re-laying the rows here makes a decoded PNG
    ** indistinguishable from a decoded t3x, so Texture::CreateTexture can keep
    ** memcpy'ing the slice straight into the C3D_Tex. */
    /* Area-average downscale so the longer side lands on `limit`. */
    static FormatHandler::DecodedImage shrinkToFit(const FormatHandler::DecodedImage& src,
                                                   int limit)
    {
        const double scale = std::min((double)limit / src.width, (double)limit / src.height);
        const int dstW     = std::max(1, (int)(src.width * scale));
        const int dstH     = std::max(1, (int)(src.height * scale));

        FormatHandler::DecodedImage dst {};
        dst.width  = dstW;
        dst.height = dstH;
        dst.format = src.format;
        dst.size   = (size_t)dstW * dstH * 4;
        dst.data   = std::make_unique<uint8_t[]>(dst.size);

        uint8_t* out = dst.data.get();
        for (int dy = 0; dy < dstH; dy++)
        {
            const int sy0 = dy * src.height / dstH;
            const int sy1 = std::max(sy0 + 1, (dy + 1) * src.height / dstH);

            for (int dx = 0; dx < dstW; dx++, out += 4)
            {
                const int sx0 = dx * src.width / dstW;
                const int sx1 = std::max(sx0 + 1, (dx + 1) * src.width / dstW);

                uint32_t sum[4] = { 0, 0, 0, 0 };
                for (int sy = sy0; sy < sy1; sy++)
                {
                    const uint8_t* row = src.data.get() + ((size_t)sy * src.width + sx0) * 4;
                    for (int sx = sx0; sx < sx1; sx++, row += 4)
                        for (int c = 0; c < 4; c++)
                            sum[c] += row[c];
                }

                const uint32_t count = (uint32_t)(sx1 - sx0) * (sy1 - sy0);
                for (int c = 0; c < 4; c++)
                    out[c] = (uint8_t)(sum[c] / count);
            }
        }

        return dst;
    }

    class TiledPNGHandler : public PNGHandler
    {
      public:
        DecodedImage Decode(Data* data) override
        {
            DecodedImage linear = PNGHandler::Decode(data);

            /* The PICA200 samples nothing wider or taller than 1024 texels.  The
            ** offline tex3ds pipeline shrank the oversized launcher art before
            ** converting it, so do the same here: box-filter down to fit, keep
            ** the aspect ratio.  Game art never comes close; this only ever
            ** touches shipped launcher/skin backdrops. */
            if (linear.width > LOVE_TEX3DS_MAX || linear.height > LOVE_TEX3DS_MAX)
                linear = shrinkToFit(linear, LOVE_TEX3DS_MAX);

            const unsigned powWidth = NextPo2(linear.width);
            const size_t tiledSize  = GetPixelFormatSliceSize(PIXELFORMAT_RGBA8_UNORM,
                                                              linear.width, linear.height, true);

            DecodedImage tiled {};
            tiled.width  = linear.width;
            tiled.height = linear.height;
            tiled.format = PIXELFORMAT_RGBA8_UNORM;
            /* ImageData::Decode validates the logical width*height*4, exactly as
            ** T3XHandler reports it, while the buffer itself is the padded tile
            ** grid the GPU upload copies. */
            tiled.size = linear.size;
            tiled.data = std::make_unique<uint8_t[]>(tiledSize);
            std::memset(tiled.data.get(), 0, tiledSize);

            const uint8_t* src = linear.data.get();
            for (int y = 0; y < linear.height; y++)
            {
                for (int x = 0; x < linear.width; x++, src += 4)
                {
                    const uint32_t abgr = (uint32_t)src[3] | ((uint32_t)src[2] << 8) |
                                          ((uint32_t)src[1] << 16) | ((uint32_t)src[0] << 24);

                    *Color::FromTile<uint32_t>(tiled.data.get(), powWidth,
                                               { (float)x, (float)y }) = abgr;
                }
            }

            return tiled;
        }
    };
} // namespace

ImageModule::ImageModule()
{
    this->formatHandlers.push_back(new T3XHandler());
    this->formatHandlers.push_back(new TiledPNGHandler());
}
