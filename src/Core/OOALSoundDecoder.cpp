/*

OOALSoundDecoder.m


OOALSound - OpenAL sound implementation for Oolite.
Copyright (C) 2005-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#include "OOALSoundDecoder.h"
#include "OOLogging.h"
#include "unzip.h"
#include <cstring>
#include <vorbis/vorbisfile.h>

#include "oofnd/String.hpp"

enum {
    kMaxDecodeSize = 1 << 20 // 2^20 frames = 4 MB
};

static size_t OOReadOXZVorbis(void* ptr, size_t size, size_t nmemb, void* datasource);
static int OOCloseOXZVorbis(void* datasource);
// not practical to implement these
// static int OOSeekOXZVorbis  (void *datasource, ogg_int64_t offset, int whence);
// static long OOTellOXZVorbis (void *datasource);

namespace {

// The class cluster's one concrete decoder, private to this file (proposed ADR-0056, amendment
// oo-x2wy item 3).
class OOALSoundVorbisCodec final : public OOALSoundDecoder {
public:
    // Was [[OOALSoundVorbisCodec alloc] cxx_initWithPath:]: null where it answered nil.
    static oo::Ref<OOALSoundDecoder> createWithPath(const std::optional<std::string>& path);

    ~OOALSoundVorbisCodec() override;

    std::optional<std::map<std::string, std::string>> comments();

    bool readCreatingBuffer(char** outBuffer, size_t* outSize) override;
    size_t streamToBuffer(char* buffer) override;
    size_t sizeAsBuffer() override;
    bool isStereo() override;
    std::optional<std::string> descriptionComponents() const override;
    long sampleRate() override;
    void reset() override;
    std::optional<std::string> name() override;

private:
    OOALSoundVorbisCodec() = default;
    bool initWithPath(const std::optional<std::string>& path);

    OggVorbis_File _vf = { };
    std::optional<std::string> _name; // nil when the path was nil
    bool _readStarted = { };
    bool _seekableStream = { };
    unzFile uf = { }; // @public before, for the OXZ read callback, now its friend

    friend size_t(::OOReadOXZVorbis)(void* ptr, size_t size, size_t nmemb, void* datasource);
};

} // namespace

oo::Ref<OOALSoundDecoder> OOALSoundDecoder::initWithPath(const std::optional<std::string>& inPath)
{
    oo::Ref<OOALSoundDecoder> self;

    if (oo::str::pathExtension(inPath.value_or(std::string())) == "ogg") {
        self = OOALSoundVorbisCodec::createWithPath(inPath);
    }

    return self;
}

oo::Ref<OOALSoundDecoder> OOALSoundDecoder::codecWithPath(const std::string& inPath)
{
    if (oo::str::pathExtension(inPath) == "ogg") {
        return OOALSoundVorbisCodec::createWithPath(inPath);
    }
    return nullptr;
}

size_t OOALSoundDecoder::streamToBuffer(char* /*ioBuffer*/)
{
    return 0;
}

bool OOALSoundDecoder::readCreatingBuffer(char** outBuffer, size_t* outSize)
{
    if (NULL != outBuffer)
        *outBuffer = NULL;
    if (NULL != outSize)
        *outSize = 0;

    return false;
}

size_t OOALSoundDecoder::sizeAsBuffer()
{
    return 0;
}

bool OOALSoundDecoder::isStereo()
{
    return false;
}

long OOALSoundDecoder::sampleRate()
{
    return 0;
}

void OOALSoundDecoder::reset()
{
    // nothing
}

std::optional<std::string> OOALSoundDecoder::name()
{
    return std::string();
}

std::optional<std::string> OOALSoundDecoder::descriptionComponents() const
{
    return std::nullopt;
}

oo::Ref<OOALSoundDecoder> OOALSoundVorbisCodec::createWithPath(const std::optional<std::string>& path)
{
    oo::Ref<OOALSoundVorbisCodec> codec = oo::adopt(new OOALSoundVorbisCodec);
    if (!codec->initWithPath(path))
        return nullptr;
    return codec;
}

/*	The body of -cxx_initWithPath:. [super init] could not fail, so its block stays as it was; each
        "[self release]; self = nil;" is return false (the factory drops the object, as the release did).
*/
bool OOALSoundVorbisCodec::initWithPath(const std::optional<std::string>& path)
{
    {
        bool OK = false;

        const std::string pathString = path.value_or(std::string());
        if (path.has_value())
            _name = oo::str::lastPathComponent(pathString);

        std::size_t i, cl;
        const std::vector<std::string> components = oo::str::pathComponents(pathString);
        cl = components.size();
        for (i = 0; i < cl; i++) {
            const std::string& component = components[i];
            if (oo::str::lowercase(oo::str::pathExtension(component)) == "oxz") {
                break;
            }
        }
        // if i == cl then the path is entirely uncompressed
        if (i == cl) {
            /* Get vorbis data from a standard file stream */
            int err;
            FILE* file;

            _seekableStream = true;

            if (path.has_value()) {
                file = fopen(path->c_str(), "rb");
                if (NULL != file) {
                    err = ov_open_callbacks(file, &_vf, NULL, 0, OV_CALLBACKS_DEFAULT);
                    if (0 == err) {
                        OK = true;
                    }
                }
            }

            if (!OK) {
                return false;
            }

        } else {
            _seekableStream = false;

            const std::string zipFile = oo::str::pathWithComponents(std::vector<std::string>(components.begin(), components.begin() + i + 1));
            const std::string containedFile = oo::str::pathWithComponents(std::vector<std::string>(components.begin() + i + 1, components.end()));

            uf = unzOpen64(zipFile.c_str());
            if (uf == NULL) {
                OO_LOG(cxx_kOOLogFileNotFound, "Could not unzip OXZ at {}", zipFile);
                return false;
            } else {
                const char* filename = containedFile.c_str();
                // unzLocateFile(*, *, 1) = case-sensitive extract
                if (unzLocateFile(uf, filename, 1) != UNZ_OK) {
                    unzClose(uf);
                    return false;
                } else {
                    int err = UNZ_OK;
                    unz_file_info64 file_info = { };
                    err = unzGetCurrentFileInfo64(uf, &file_info, NULL, 0, NULL, 0, NULL, 0);
                    if (err != UNZ_OK) {
                        unzClose(uf);
                        OO_LOG(cxx_kOOLogFileNotFound, "Could not get properties of {} within OXZ at {}", containedFile, zipFile);
                        return false;
                    } else {
                        err = unzOpenCurrentFile(uf);
                        if (err != UNZ_OK) {
                            unzClose(uf);
                            OO_LOG(cxx_kOOLogFileNotFound, "Could not read {} within OXZ at {}", containedFile, zipFile);
                            return false;
                        } else {
                            ov_callbacks _callbacks = {
                                OOReadOXZVorbis, // read sequentially
                                NULL, // no seek
                                OOCloseOXZVorbis, // close file
                                NULL, // no tell
                            };
                            err = ov_open_callbacks(this, &_vf, NULL, 0, _callbacks);
                            if (0 == err) {
                                OK = true;
                                _readStarted = false;
                            }
                            if (!OK) {
                                unzClose(uf);
                                return false;
                            }
                        }
                    }
                }
            }
        }
    }
#ifdef OOLITE_DEBUG_SOUND_FILE_OPENING
    {
        OO_LOG("sound.retain", "{}", _name.value_or("(null)"));
    }
#endif
    return true;
}

OOALSoundVorbisCodec::~OOALSoundVorbisCodec()
{
#ifdef OOLITE_DEBUG_SOUND_FILE_OPENING
    {
        OO_LOG("sound.release", "{}", _name.value_or("(null)"));
    }
#endif

    ov_clear(&_vf);
    unzClose(uf);
}

std::optional<std::map<std::string, std::string>> OOALSoundVorbisCodec::comments()
{
    vorbis_comment* comments;
    unsigned i, count;
    std::optional<std::map<std::string, std::string>> result;

    comments = ov_comment(&_vf, -1);
    if (NULL != comments) {
        count = comments->comments;
        if (0 != count) {
            result.emplace();
            for (i = 0; i != count; ++i) {
                const std::string comment(comments->user_comments[i], static_cast<std::size_t>(comments->comment_lengths[i]));
                const std::size_t equals = comment.find('=');
                if (equals != std::string::npos) {
                    (*result)[comment.substr(0, equals)] = comment.substr(equals + 1);
                } else {
                    (*result)[comment] = "";
                }
            }
        }
    }

    return result;
}

bool OOALSoundVorbisCodec::readCreatingBuffer(char** outBuffer, size_t* outSize)
{
    char *buffer = NULL, *dst;
    size_t sizeInFrames = 0;
    int remaining;
    long framesRead;
    // 16-bit samples, either two or one track
    int frameSize = isStereo() ? 4 : 2;
    ogg_int64_t totalSizeInFrames;
    bool OK = true;

    if (NULL != outBuffer)
        *outBuffer = NULL;
    if (NULL != outSize)
        *outSize = 0;
    if (NULL == outBuffer || NULL == outSize)
        OK = false;

    if (OK) {
        totalSizeInFrames = ov_pcm_total(&_vf, -1);
        assert((uint64_t)totalSizeInFrames < (uint64_t)SIZE_MAX); // Should have been checked by caller
        sizeInFrames = (size_t)totalSizeInFrames;
    }

    if (OK) {
        buffer = (char*)malloc(sizeof(char) * frameSize * sizeInFrames);
        if (!buffer)
            OK = false;
    }

    if (OK && sizeInFrames) {
        remaining = (int)MIN(frameSize * sizeInFrames, (size_t)INT_MAX);
        dst = buffer;

        char pcmout[4096];

        do {
            int toRead = sizeof(pcmout);
            if (remaining < toRead) {
                toRead = remaining;
            }
            framesRead = ov_read(&_vf, pcmout, toRead, 0, 2, 1, NULL);
            if (framesRead <= 0) {
                if (OV_HOLE == framesRead)
                    continue;
                // else:
                break;
            }

            memcpy(dst, &pcmout, sizeof(char) * framesRead);

            remaining -= framesRead;
            dst += framesRead;
        } while (0 < remaining);

        sizeInFrames -= remaining; // In case we stopped at an error
    }

    if (OK) {
        *outBuffer = buffer;
        *outSize = sizeInFrames * frameSize;
    } else {
        if (buffer)
            free(buffer);
    }
    return OK;
}

size_t OOALSoundVorbisCodec::streamToBuffer(char* buffer)
{

    int remaining = OOAL_STREAM_CHUNK_SIZE;
    size_t streamed = 0;
    long framesRead;

    char* dst = buffer;
    char pcmout[4096];
    _readStarted = true;
    do {
        int toRead = sizeof(pcmout);
        if (remaining < toRead) {
            toRead = remaining;
        }
        framesRead = ov_read(&_vf, pcmout, toRead, 0, 2, 1, NULL);
        if (framesRead <= 0) {
            if (OV_HOLE == framesRead)
                continue;
            // else:
            break;
        }
        memcpy(dst, &pcmout, sizeof(char) * framesRead);
        remaining -= sizeof(char) * framesRead;
        dst += sizeof(char) * framesRead;
        streamed += sizeof(char) * framesRead;
    } while (0 < remaining);

    return streamed;
}

size_t OOALSoundVorbisCodec::sizeAsBuffer()
{
    ogg_int64_t size;
    size = ov_pcm_total(&_vf, -1);
    size *= sizeof(char) * (isStereo() ? 4 : 2);
    if ((uint64_t)SIZE_MAX < (uint64_t)size)
        size = (ogg_int64_t)SIZE_MAX;
    return (size_t)size;
}

bool OOALSoundVorbisCodec::isStereo()
{
    return 1 < ov_info(&_vf, -1)->channels;
}

// The facade's -description wraps this as "<OOALSoundVorbisCodec 0x...>{...}", which is what this
// class's own -description printed. comments() reads the file through a non-const pointer, so
// it is reached through const_cast (as amendment oo-bhb9 item 5 does).
std::optional<std::string> OOALSoundVorbisCodec::descriptionComponents() const
{
    oo::PList commentList;
    if (const auto comments = const_cast<OOALSoundVorbisCodec*>(this)->comments()) {
        oo::PList::Dict dict;
        for (const auto& [key, value] : *comments)
            dict.emplace(key, oo::PList(value));
        commentList = oo::PList(std::move(dict));
    }
    return oo::str::format("\"%s\", comments=%s", _name.value_or("(null)").c_str(), oo::DescriptionOf(commentList).c_str());
}

long OOALSoundVorbisCodec::sampleRate()
{
    return ov_info(&_vf, -1)->rate;
}

void OOALSoundVorbisCodec::reset()
{
    if (!_readStarted) {
        return; // don't need to do anything
    }
    if (_seekableStream) {
        ov_pcm_seek(&_vf, 0);
        return;
    }
    // reset current file pointer in OXZ
    unzOpenCurrentFile(uf);
    // reopen OGG streamer
    ov_clear(&_vf);
    ov_callbacks _callbacks = {
        OOReadOXZVorbis, // read sequentially
        NULL, // no seek
        OOCloseOXZVorbis, // close file
        NULL, // no tell
    };
    ov_open_callbacks(this, &_vf, NULL, 0, _callbacks);
    _readStarted = false;
}

std::optional<std::string> OOALSoundVorbisCodec::name()
{
    return _name;
}

static size_t OOReadOXZVorbis(void* ptr, size_t size, size_t nmemb, void* datasource)
{
    OOALSoundVorbisCodec* src = (OOALSoundVorbisCodec*)datasource;
    size_t toRead = size * nmemb;
    void* buf = (void*)malloc(toRead);
    int err = UNZ_OK;
    err = unzReadCurrentFile(src->uf, buf, toRead);
    //	OO_LOG("sound.replay", "Read {} blocks, got {}", static_cast<int>(toRead), static_cast<int>(err));
    if (err > 0) {
        memcpy(ptr, buf, err);
    }
    if (err < 0) {
        return OV_EREAD;
    }
    return err;
}

int OOCloseOXZVorbis(void* /*datasource*/)
{
    //  doing this prevents replaying
    //	OOALSoundVorbisCodec *src = (OOALSoundVorbisCodec *)datasource;
    //	unzClose(src->uf);
    return 0;
}
