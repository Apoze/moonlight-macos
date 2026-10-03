#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <mutex>
#include <vector>

// Observation-only state shared with Metal callbacks. It has no renderer,
// window, SDL or GPU pointers and can safely outlive renderer destruction.
namespace MetalPresentation {
struct ClockSample {
    double mediaSeconds = 0;
    uint64_t beforeUs = 0;
    uint64_t afterUs = 0;

    uint64_t translate(double seconds, uint64_t observedUs) const
    {
        if (!std::isfinite(seconds) || seconds <= 0 || !std::isfinite(mediaSeconds) ||
            mediaSeconds <= 0 || afterUs < beforeUs || afterUs - beforeUs > 1000) return 0;
        const double translated = double(beforeUs) + double(afterUs - beforeUs) / 2 +
                                  (seconds - mediaSeconds) * 1000000;
        if (translated <= 0 || translated > double(observedUs) + 1000) return 0;
        return static_cast<uint64_t>(translated);
    }
};

struct Record {
    uint64_t serial = 0, drawable = 0, decoderUs = 0, prepareUs = 0;
    uint64_t submitUs = 0, presentedUs = 0, observedUs = 0, uncertaintyUs = 0;
    int64_t rtp = 0;
    double submitMedia = 0, presentedMedia = 0;
    uint64_t displaySequence = 0;
    double displayTimestamp = 0, displayTarget = 0, displayObserved = 0;
    bool callback = false;
};

class State {
public:
    explicit State(size_t capacity) : m_Records(std::max<size_t>(1, capacity)) {}

    uint64_t submit(Record record)
    {
        std::lock_guard<std::mutex> lock(m_Mutex);
        record.serial = ++m_Submitted;
        m_Records[(record.serial - 1) % m_Records.size()] = record;
        return record.serial;
    }

    void presented(uint64_t serial, double media, uint64_t observed, const ClockSample& clock)
    {
        std::lock_guard<std::mutex> lock(m_Mutex);
        auto& record = m_Records[(serial - 1) % m_Records.size()];
        if (record.serial != serial || record.callback) return;
        record.callback = true;
        record.presentedMedia = media;
        record.observedUs = observed;
        record.uncertaintyUs = clock.afterUs >= clock.beforeUs ? clock.afterUs - clock.beforeUs : 0;
        const auto translated = clock.translate(media, observed);
        // A zero timestamp is an unavailable/skipped presentation, not a zero
        // latency sample. Reject pre-submission events and stale correlations.
        if (translated >= record.submitUs && media >= record.submitMedia &&
            media - record.submitMedia < 2.0) {
            record.presentedUs = translated;
            if (serial > m_Latest.serial) m_Latest = record;
        }
    }

    Record latest() const { std::lock_guard<std::mutex> lock(m_Mutex); return m_Latest; }

    std::vector<Record> snapshot() const
    {
        std::lock_guard<std::mutex> lock(m_Mutex);
        std::vector<Record> result;
        const auto count = std::min<uint64_t>(m_Submitted, m_Records.size());
        result.reserve(count);
        for (uint64_t id = m_Submitted - count + 1; id <= m_Submitted; ++id)
            result.push_back(m_Records[(id - 1) % m_Records.size()]);
        return result;
    }

private:
    mutable std::mutex m_Mutex;
    std::vector<Record> m_Records;
    uint64_t m_Submitted = 0;
    Record m_Latest;
};
} // namespace MetalPresentation
