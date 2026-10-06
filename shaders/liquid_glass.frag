#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform vec2 uRectOrigin;
uniform vec2 uRectSize;
uniform float uRadius;
uniform float uSpread;
uniform float uRefraction;
uniform float uChroma;
uniform float uSpecular;
uniform vec4 uTint;
uniform vec2 uLight;
uniform float uTintFeather;
uniform float uRimWidth;

uniform sampler2D uBackdrop;

out vec4 fragColor;

float roundedBoxSdf(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - radius;
}

vec2 surfaceNormal(vec2 p, vec2 halfSize, float radius) {
  vec2 unit = vec2(1.0, 0.0);
  float dx = roundedBoxSdf(p + unit.xy, halfSize, radius) -
             roundedBoxSdf(p - unit.xy, halfSize, radius);
  float dy = roundedBoxSdf(p + unit.yx, halfSize, radius) -
             roundedBoxSdf(p - unit.yx, halfSize, radius);
  return normalize(vec2(dx, dy) + vec2(1e-6));
}

const int TAPS = 5;

float lensProfile(float depth, float band) {
  float edge = 1.0 - clamp(depth / band, 0.0, 1.0);
  return edge * edge * (3.0 - 2.0 * edge) * edge;
}

vec3 sampleBackdrop(vec2 coord) {
  vec2 uv = coord / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uBackdrop, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
}

vec3 vibrance(vec3 color, float amount) {
  float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
  return mix(vec3(luma), color, amount);
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 halfSize = uRectSize * 0.5;
  vec2 center = uRectOrigin + halfSize;
  vec2 p = fragCoord - center;

  float radius = min(uRadius, min(halfSize.x, halfSize.y));
  float sd = roundedBoxSdf(p, halfSize, radius);

  if (sd > 0.0) {
    fragColor = vec4(sampleBackdrop(fragCoord), 1.0);
    return;
  }

  float depth = -sd;
  vec2 normal = surfaceNormal(p, halfSize, radius);
  float band = max(uSpread * min(halfSize.x, halfSize.y), 1.0);
  float lens = lensProfile(depth, band);
  float shift = uRefraction * lens;
  float aberration = uChroma * lens;

  vec3 refracted = vec3(0.0);
  for (int i = 0; i < TAPS; i++) {
    float offset = (float(i) / float(TAPS - 1) - 0.5) * (1.0 + shift * 0.35);
    vec2 base = fragCoord + normal * (shift + offset);
    if (aberration > 0.0) {
      refracted.r += sampleBackdrop(base + normal * shift * aberration).r;
      refracted.g += sampleBackdrop(base).g;
      refracted.b += sampleBackdrop(base - normal * shift * aberration).b;
    } else {
      refracted += sampleBackdrop(base);
    }
  }
  refracted = vibrance(refracted / float(TAPS), 1.18);

  float veil = smoothstep(0.0, 1.0, clamp(depth / max(uTintFeather, 1.0), 0.0, 1.0));
  vec3 color = mix(refracted, uTint.rgb, uTint.a * mix(0.55, 1.0, veil));

  vec2 light = normalize(uLight + vec2(1e-6));
  float facing = dot(normal, light);
  float rimWidth = max(uRimWidth, 1.0);
  float rim = 1.0 - smoothstep(0.0, rimWidth, depth);
  float hairline = 1.0 - smoothstep(0.0, rimWidth * 0.45, depth);

  float key = pow(max(facing, 0.0), 3.0);
  float bounce = pow(max(-facing, 0.0), 3.0) * 0.45;
  float specular = (key + bounce) * rim * uSpecular;
  float edgeGlow = hairline * uSpecular * 0.22;
  float lower = clamp(0.5 - 0.5 * dot(normal, light), 0.0, 1.0);
  float inner = (1.0 - smoothstep(0.0, band * 1.6, depth)) * lens * lower;

  color += vec3(specular + edgeGlow);
  color = mix(color, color * 0.88, inner * 0.3 * uSpecular);

  fragColor = vec4(clamp(color, vec3(0.0), vec3(1.0)), 1.0);
}
