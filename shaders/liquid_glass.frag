#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform vec2 uCenter;
uniform vec2 uHalfSize;
uniform vec4 uRadii;
uniform float uThickness;
uniform float uRefractIndex;
uniform float uIntensity;
uniform float uChroma;
uniform float uSaturation;
uniform vec4 uFill;
uniform float uFlipY;

uniform sampler2D uBackdrop;

out vec4 fragColor;

float roundedRectSdf(vec2 p, vec4 radii) {
  radii.xy = (p.x > 0.0) ? radii.xy : radii.zw;
  radii.x = (p.y > 0.0) ? radii.x : radii.y;
  vec2 q = abs(p) - uHalfSize + radii.x;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radii.x;
}

vec3 sampleBackdrop(vec2 coord) {
  vec2 uv = coord / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  if (uFlipY > 0.5) {
    uv.y = 1.0 - uv.y;
  }
#endif
  return texture(uBackdrop, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
}

vec2 refraction(vec2 p, float sd) {
  if (sd >= 0.0 || uThickness <= 0.0) {
    return vec2(0.0);
  }
  float sdX = roundedRectSdf(p + vec2(1.0, 0.0), uRadii);
  float sdY = roundedRectSdf(p + vec2(0.0, 1.0), uRadii);
  float nCos = max(uThickness + sd, 0.0) / uThickness;
  float nSin = sqrt(max(1.0 - nCos * nCos, 0.0));
  vec3 normal = normalize(vec3((sdX - sd) * nCos, (sdY - sd) * nCos, nSin));
  vec3 bent = refract(vec3(0.0, 0.0, -1.0), normal, 1.0 / uRefractIndex);
  float height = sd < -uThickness
      ? uThickness
      : sqrt(max(sd * (-2.0 * uThickness - sd), 0.0));
  float travel = (height + 8.0 * uThickness) / max(-bent.z, 0.001);
  return bent.xy * travel * uIntensity;
}

void main() {
  vec2 coord = FlutterFragCoord().xy;
  vec2 p = coord - uCenter;
  float sd = roundedRectSdf(p, uRadii);
  vec2 shift = refraction(p, sd);

  vec3 color;
  if (uChroma > 0.0) {
    color = vec3(
      sampleBackdrop(coord + shift * (1.0 + uChroma)).r,
      sampleBackdrop(coord + shift).g,
      sampleBackdrop(coord + shift * (1.0 - uChroma)).b
    );
  } else {
    color = sampleBackdrop(coord + shift);
  }

  float luma = dot(color, vec3(0.213, 0.715, 0.072));
  color = clamp(mix(vec3(luma), color, uSaturation), 0.0, 1.0);

  fragColor = vec4(uFill.rgb + color * (1.0 - uFill.a), 1.0);
}
