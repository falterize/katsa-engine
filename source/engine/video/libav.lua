-- LuaJIT binding to the FFmpeg shared libraries (libavformat, libavcodec, libswscale,
-- libswresample, libavutil). The libraries are optional: `Libav.load()` returns nil and a message
-- when they are not installed, and the engine keeps running without video.
--
-- Supported: FFmpeg 5.1 or newer (libavcodec 59 and up). Only the leading fields of a few structs are
-- declared, the ones whose layout did not change between 5.1 and 7.x (AVPacket, AVStream,
-- AVCodecParameters, the head of AVFormatContext); AVFrame differs from FFmpeg 8 on and is declared
-- twice. Everything else goes through function calls and AVOption getters.
local ffi = require('ffi')
local Native = require('source.katsa.core.native')

ffi.cdef([[
typedef struct AVRational { int num; int den; } AVRational;
typedef struct AVChannelLayout { int order; int nb_channels; uint64_t mask; void* opaque; } AVChannelLayout;
typedef struct AVPacket {
    void* buf; int64_t pts; int64_t dts; uint8_t* data; int size; int stream_index; int flags;
} AVPacket;
typedef struct AVFrameOld {
    uint8_t* data[8]; int linesize[8]; uint8_t** extended_data; int width; int height;
    int nb_samples; int format; int key_frame; int pict_type; AVRational sample_aspect_ratio; int64_t pts;
} AVFrameOld;
typedef struct AVFrameNew {
    uint8_t* data[8]; int linesize[8]; uint8_t** extended_data; int width; int height;
    int nb_samples; int format; int pict_type; AVRational sample_aspect_ratio; int64_t pts;
} AVFrameNew;
typedef struct AVCodecParameters {
    int codec_type; int codec_id; uint32_t codec_tag; uint8_t* extradata; int extradata_size;
    int format; int64_t bit_rate; int bits_per_coded_sample; int bits_per_raw_sample; int profile;
    int level; int width; int height;
} AVCodecParameters;
typedef struct AVStream {
    void* av_class; int index; int id; AVCodecParameters* codecpar; void* priv_data;
    AVRational time_base; int64_t start_time; int64_t duration; int64_t nb_frames; int disposition;
} AVStream;
typedef struct AVFormatContext {
    void* av_class; void* iformat; void* oformat; void* priv_data; void* pb; int ctx_flags;
    unsigned nb_streams; AVStream** streams; char* url; int64_t start_time; int64_t duration;
} AVFormatContext;

unsigned avformat_version(void);
int avformat_open_input(AVFormatContext** ps, const char* url, void* fmt, void** options);
int avformat_find_stream_info(AVFormatContext* ic, void** options);
void avformat_close_input(AVFormatContext** s);
int av_read_frame(AVFormatContext* s, AVPacket* pkt);
int avformat_seek_file(AVFormatContext* s, int stream_index, int64_t min_ts, int64_t ts,
    int64_t max_ts, int flags);

unsigned avcodec_version(void);
AVPacket* av_packet_alloc(void);
void av_packet_free(AVPacket** pkt);
void av_packet_unref(AVPacket* pkt);
const void* avcodec_find_decoder(int id);
void* avcodec_alloc_context3(const void* codec);
void avcodec_free_context(void** ctx);
int avcodec_parameters_to_context(void* ctx, const AVCodecParameters* par);
int avcodec_open2(void* ctx, const void* codec, void** options);
int avcodec_send_packet(void* ctx, const AVPacket* pkt);
int avcodec_receive_frame(void* ctx, void* frame);
void avcodec_flush_buffers(void* ctx);

unsigned avutil_version(void);
void* av_frame_alloc(void);
void av_frame_free(void** frame);
void av_frame_unref(void* frame);
int av_opt_get_int(void* obj, const char* name, int flags, int64_t* out);
int av_opt_get_chlayout(void* obj, const char* name, int flags, AVChannelLayout* out);
void av_channel_layout_default(AVChannelLayout* layout, int nb_channels);
void av_channel_layout_uninit(AVChannelLayout* layout);
void av_log_set_level(int level);
int av_strerror(int errnum, char* buffer, size_t size);

typedef struct SwsContext SwsContext;
SwsContext* sws_getContext(int srcW, int srcH, int srcFormat, int dstW, int dstH, int dstFormat,
    int flags, void* srcFilter, void* dstFilter, const double* param);
int sws_scale(SwsContext* c, const uint8_t* const* srcSlice, const int* srcStride, int srcSliceY,
    int srcSliceH, uint8_t* const* dst, const int* dstStride);
void sws_freeContext(SwsContext* c);

typedef struct SwrContext SwrContext;
int swr_alloc_set_opts2(SwrContext** ps, const AVChannelLayout* out_ch_layout, int out_sample_fmt,
    int out_sample_rate, const AVChannelLayout* in_ch_layout, int in_sample_fmt, int in_sample_rate,
    int log_offset, void* log_ctx);
int swr_init(SwrContext* s);
int swr_convert(SwrContext* s, uint8_t** out, int out_count, const uint8_t** in, int in_count);
int64_t swr_get_delay(SwrContext* s, int64_t base);
void swr_free(SwrContext** s);
]])

local Libav = {
    -- AVMediaType and a few enum values the decoder passes around.
    VIDEO = 0,
    AUDIO = 1,
    PIX_FMT_RGBA = 26,
    SAMPLE_FMT_S16 = 1,
    NOPTS = ffi.cast('int64_t', 0x8000000000000000ULL),
    SEEK_BACKWARD = 1,
    AGAIN = -11, -- AVERROR(EAGAIN) on every supported platform
    EOF = -541478725, -- AVERROR_EOF: -MKTAG('E','O','F',' ')
}

local libraries, failure

-- Returns { format, codec, util, scale, resample, frameType } or nil plus the reason.
function Libav.load()
    if libraries ~= nil then
        return libraries or nil, failure
    end
    local loaded = {}
    for key, name in pairs({
        util = 'AVUtil',
        codec = 'AVCodec',
        format = 'AVFormat',
        scale = 'SWScale',
        resample = 'SWResample',
    }) do
        local library, message = Native.load(name)
        if not library then
            libraries, failure = false, message
            return nil, message
        end
        loaded[key] = library
    end
    local major = loaded.codec.avcodec_version() / 65536
    if major < 59 then
        libraries = false
        failure = ('FFmpeg is too old (libavcodec %d); 5.1 or newer is needed'):format(major)
        return nil, failure
    end
    -- FFmpeg 8 (avutil 60) dropped AVFrame.key_frame, which moved pts.
    loaded.frameType = loaded.util.avutil_version() / 65536 >= 60 and 'AVFrameNew*' or 'AVFrameOld*'
    loaded.util.av_log_set_level(-8) -- quiet: no per-file chatter on stderr
    libraries = loaded
    return loaded
end

function Libav.available()
    return Libav.load() ~= nil
end

-- Message for a negative AVERROR code.
function Libav.describe(code)
    local lib = assert(Libav.load())
    local buffer = ffi.new('char[128]')
    lib.util.av_strerror(code, buffer, 128)
    return ffi.string(buffer)
end

return Libav
