#include "../ios/Classes/VoiceProcessor.h"
#include <cassert>
#include <vector>

double amplitude(const std::vector<float>& data, double frequency, int rate) {
  double real = 0, imaginary = 0;
  for (std::size_t i = rate / 4; i < data.size(); ++i) {
    real += data[i] * std::cos(2 * 3.141592653589793 * frequency * i / rate);
    imaginary += data[i] * std::sin(2 * 3.141592653589793 * frequency * i / rate);
  }
  return std::hypot(real, imaginary);
}

int main() {
  for (int rate : {16000, 48000}) {
    for (int mode = 0; mode <= 4; ++mode) {
      ProMaxVoiceProcessor processor;
      processor.configure(mode, rate);
      std::vector<float> left(rate), right(rate);
      for (int i = 0; i < rate; ++i) left[i] = right[i] = 8000 * std::sin(2 * 3.141592653589793 * 440 * i / rate);
      const auto original = left;
      for (int offset = 0; offset < rate; offset += rate / 100) {
        float* channels[] = {left.data() + offset, right.data() + offset};
        processor.process(channels, 2, rate / 100);
      }
      for (int i = 0; i < rate; ++i) {
        assert(std::isfinite(left[i]) && std::abs(left[i]) <= 32768);
        assert(left[i] == right[i]);
      }
      if (mode == 0) assert(left == original);
      if (mode == 1 || mode == 2) {
        const double shifted = 440 * std::pow(2.0, (mode == 1 ? -5.0 : 6.0) / 12.0);
        assert(amplitude(left, shifted, rate) > amplitude(left, 440, rate) * 3);
      }
      if (mode == 3) assert(amplitude(left, 485, rate) > amplitude(left, 440, rate) * 3);
    }
  }
  ProMaxVoiceProcessor processor;
  processor.configure(4, 48000);
  float silence[480] = {};
  float* channel[] = {silence};
  processor.process(channel, 1, 480);
  for (float sample : silence) assert(sample == 0);
}
