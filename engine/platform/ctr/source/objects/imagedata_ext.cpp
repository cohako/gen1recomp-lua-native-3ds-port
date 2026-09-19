#include <modules/image/imagemodule.hpp>
#include <objects/imagedata_ext.hpp>

using namespace love;

void ImageData<Console::CTR>::Paste(ImageData* source, int x, int y, Rect& sourceRect)
{
    PixelFormat destFormat = this->GetFormat();
    PixelFormat srcFormat  = source->GetFormat();

    if (destFormat != srcFormat)
        throw love::Exception("Pixel formats do not match.");

    if (srcFormat != PIXELFORMAT_RGBA8_UNORM && destFormat != PIXELFORMAT_RGBA8_UNORM)
        throw love::Exception("Both source and destination formats must be RGBA8.");

    const auto srcWidth  = source->GetWidth();
    const auto srcHeight = source->GetHeight();

    const auto destWidth  = this->GetWidth();
    const auto destHeight = this->GetHeight();

    this->AdjustPaste(source, x, y, destWidth, destHeight, sourceRect);

    std::unique_lock lock(source->mutex);
    std::unique_lock other(this->mutex);

    uint8_t* srcData = (uint8_t*)source->GetData();
    uint8_t* dstData = (uint8_t*)this->GetData();

    auto getFunction = source->pixelGetFunction;
    auto setFunction = this->pixelSetFunction;

    const auto _srcWidth = NextPo2(srcWidth);
    const auto _dstWidth = NextPo2(destWidth);

    for (int _y = 0; _y < std::min(sourceRect.h, destHeight - y); _y++)
    {
        for (int _x = 0; _x < std::min(sourceRect.w, destWidth - x); _x++)
        {
            Color color {};

            // clang-format off
            Vector2 srcPosition { (sourceRect.x + _x), (sourceRect.y + _y) };
            const auto* sourcePixel = Color::FromTile(srcData, _srcWidth, srcPosition);

            getFunction((const Pixel*)sourcePixel, color);

            Vector2 dstPosition { (x + _x), (y + _y) };
            auto* destinationPixel = Color::FromTile(dstData, _dstWidth, dstPosition);

            setFunction(color, (Pixel*)destinationPixel);
            // clang-format on
        }
    }
}
#include <modules/filesystem/physfs/filesystem.hpp>

#include <common/math.hpp>

#include <cstring>

FileData* ImageData<Console::CTR>::Encode(FormatHandler::EncodedFormat encodedFormat,
                                          std::string_view filename, bool writeFile) const
{
    if (this->format != PIXELFORMAT_RGBA8_UNORM)
    {
        throw love::Exception("Only RGBA8 ImageData can be encoded on this console (got %s).",
                              love::GetPixelFormatName(this->format));
    }

    auto module = Module::GetInstance<ImageModule>(Module::M_IMAGE);
    if (module == nullptr)
        throw love::Exception("love.image must be loaded in order to encode an ImageData.");

    FormatHandler* encoder = nullptr;
    for (auto* handler : module->GetFormatHandlers())
    {
        if (handler->CanEncode(this->format, encodedFormat))
        {
            encoder = handler;
            break;
        }
    }

    if (encoder == nullptr)
    {
        throw love::Exception("No suitable image encoder for the %s format.",
                              love::GetPixelFormatName(this->format));
    }

    /* The encoders expect what every other platform stores: linear RGBA rows.
    ** Our pixels sit in 8x8 tiles of ABGR words (mirror of TiledPNGHandler). */
    FormatHandler::DecodedImage linear {};
    linear.width  = this->width;
    linear.height = this->height;
    linear.format = this->format;
    linear.size   = (size_t)this->width * this->height * sizeof(uint32_t);
    linear.data   = std::make_unique<uint8_t[]>(linear.size);

    const unsigned powWidth = NextPo2(this->width);

    FormatHandler::EncodedImage image {};
    {
        std::unique_lock lock(this->mutex);

        uint8_t* dst = linear.data.get();
        for (int y = 0; y < this->height; y++)
        {
            for (int x = 0; x < this->width; x++, dst += 4)
            {
                const uint32_t abgr = *Color::FromTile<const uint32_t>(
                    this->data.get(), powWidth, { (float)x, (float)y });

                dst[0] = (abgr >> 24) & 0xFF;
                dst[1] = (abgr >> 16) & 0xFF;
                dst[2] = (abgr >> 8) & 0xFF;
                dst[3] = abgr & 0xFF;
            }
        }

        image = encoder->Encode(linear, encodedFormat);
    }

    if (image.data == nullptr)
        throw love::Exception("Image encoder returned no data.");

    const std::string name(filename);
    FileData* fileData = new FileData(image.size, name);
    std::memcpy(fileData->GetData(), image.data.get(), image.size);

    if (writeFile)
    {
        auto filesystem = Module::GetInstance<Filesystem>(Module::M_FILESYSTEM);
        if (filesystem == nullptr)
        {
            fileData->Release();
            throw love::Exception(
                "love.filesystem must be loaded in order to encode an ImageData.");
        }

        try
        {
            filesystem->Write(name.c_str(), fileData->GetData(), fileData->GetSize());
        }
        catch (love::Exception&)
        {
            fileData->Release();
            throw;
        }
    }

    return fileData;
}
