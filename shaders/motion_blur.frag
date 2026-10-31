#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform vec2 uStreak;
uniform float uTaps;

uniform sampler2D uInput;

out vec4 fragColor;

const int kMaxTaps = 24;

float interleavedNoise(vec2 coord) {
  return fract(52.9829189 * fract(dot(coord, vec2(0.06711056, 0.00583715))));
}

void main() {
  vec2 coord = FlutterFragCoord().xy;
  vec2 uv = coord / uSize;
  vec2 streak = uStreak / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
  streak.y = -streak.y;
#endif
  float taps = clamp(uTaps, 2.0, float(kMaxTaps));
  float jitter = interleavedNoise(coord) - 0.5;
  vec4 sum = vec4(0.0);
  float total = 0.0;
  for (int i = 0; i < kMaxTaps; i++) {
    float index = float(i);
    if (index >= taps) {
      break;
    }
    float t = (index + 0.5 + jitter) / taps - 0.5;
    float weight = 1.0 - abs(t);
    vec2 at = clamp(uv + streak * t, vec2(0.0), vec2(1.0));
    sum += texture(uInput, at) * weight;
    total += weight;
  }
  fragColor = sum / total;
}
