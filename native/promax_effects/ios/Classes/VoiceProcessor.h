#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>

class ProMaxVoiceProcessor {
 public:
  void configure(int mode, double sampleRate) {
    if (mode_ == mode && rate_ == sampleRate) return;
    mode_ = mode;
    rate_ = sampleRate > 0 ? sampleRate : 48000;
    ring_ = {};
    low_ = {};
    high_ = {};
    phase_ = 0.25;
    carrier_ = 0;
    write_ = 0;
    window_ = std::clamp(rate_ * 0.025, 128.0, 1800.0);
    ratio_ = mode == 1 ? std::pow(2.0, -5.0 / 12.0) : std::pow(2.0, 6.0 / 12.0);
    highAlpha_ = 1.0 - std::exp(-2.0 * pi * 300.0 / rate_);
    lowAlpha_ = 1.0 - std::exp(-2.0 * pi * 3000.0 / rate_);
  }

  void process(float** channels, std::size_t count, std::size_t frames) {
    if (mode_ == 0 || count == 0 || count > ring_.size()) return;
    for (std::size_t frame = 0; frame < frames; ++frame) {
      const double other = phase_ < 0.5 ? phase_ + 0.5 : phase_ - 0.5;
      const double weight = std::pow(std::sin(pi * phase_), 2);
      for (std::size_t channel = 0; channel < count; ++channel) {
        const float input = std::isfinite(channels[channel][frame]) ? channels[channel][frame] / 32768.0f : 0;
        float output = input;
        if (mode_ == 1 || mode_ == 2) {
          ring_[channel][write_] = input;
          output = static_cast<float>(read(channel, phase_) * weight + read(channel, other) * (1.0 - weight));
        } else if (mode_ == 3) {
          output = input * static_cast<float>(std::cos(carrier_));
        } else if (mode_ == 4) {
          high_[channel] += static_cast<float>(highAlpha_) * (input - high_[channel]);
          low_[channel] += static_cast<float>(lowAlpha_) * (input - high_[channel] - low_[channel]);
          output = std::tanh(low_[channel] * 2.0f) * 0.65f;
        }
        channels[channel][frame] = std::clamp(output, -0.98f, 0.98f) * 32768.0f;
      }
      write_ = (write_ + 1) % ring_[0].size();
      phase_ += (1.0 - ratio_) / window_;
      phase_ -= std::floor(phase_);
      carrier_ += 2.0 * pi * 45.0 / rate_;
      if (carrier_ >= 2.0 * pi) carrier_ -= 2.0 * pi;
    }
  }

 private:
  static constexpr double pi = 3.14159265358979323846;
  float read(std::size_t channel, double phase) const {
    double at = static_cast<double>(write_) - 16.0 - phase * window_;
    while (at < 0) at += ring_[channel].size();
    const auto left = static_cast<std::size_t>(at) % ring_[channel].size();
    const auto right = (left + 1) % ring_[channel].size();
    const float fraction = static_cast<float>(at - std::floor(at));
    return ring_[channel][left] * (1.0f - fraction) + ring_[channel][right] * fraction;
  }

  std::array<std::array<float, 4096>, 2> ring_{};
  std::array<float, 2> low_{};
  std::array<float, 2> high_{};
  int mode_ = 0;
  double rate_ = 0;
  double phase_ = 0.25;
  double carrier_ = 0;
  double window_ = 1200;
  double ratio_ = 1;
  double highAlpha_ = 0;
  double lowAlpha_ = 0;
  std::size_t write_ = 0;
};
