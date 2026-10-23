#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstring>

constexpr double kProMaxPi = 3.14159265358979323846;

enum ProMaxMaskAnchor : int {
  ProMaxMaskAnchorEyes = 0,
  ProMaxMaskAnchorEachEye = 1,
  ProMaxMaskAnchorForehead = 2,
  ProMaxMaskAnchorNose = 3,
  ProMaxMaskAnchorFace = 4,
  ProMaxMaskAnchorMouth = 5,
};

inline bool promaxMaskAnchorNamed(const char* name, int& anchor) {
  static const struct {
    const char* name;
    int anchor;
  } kAnchors[] = {
      {"eyes", ProMaxMaskAnchorEyes},         {"eachEye", ProMaxMaskAnchorEachEye},
      {"forehead", ProMaxMaskAnchorForehead}, {"nose", ProMaxMaskAnchorNose},
      {"face", ProMaxMaskAnchorFace},         {"mouth", ProMaxMaskAnchorMouth},
  };
  if (!name) return false;
  for (const auto& entry : kAnchors) {
    if (std::strcmp(entry.name, name) == 0) {
      anchor = entry.anchor;
      return true;
    }
  }
  return false;
}

struct ProMaxMaskSpec {
  int anchor = ProMaxMaskAnchorEyes;
  double width = 2;
  double aspect = 1;
  double offsetX = 0;
  double offsetY = 0;
  double pivotX = 0.5;
  double pivotY = 0.5;
  double depth = 0;
};

struct ProMaxFaceSample {
  double leftX = 0, leftY = 0;
  double rightX = 0, rightY = 0;
  double noseX = 0, noseY = 0;
  double mouthX = 0, mouthY = 0;
  double pitch = NAN;
};

struct ProMaxFacePose {
  double x = 0, y = 0;
  double scale = 0;
  double roll = 0;
  double yaw = 0;
  double pitch = 0;
  double nose = 0;
  double mouth = 0;
  double alpha = 0;
};

struct ProMaxMaskQuad {
  double topLeftX = 0, topLeftY = 0;
  double topRightX = 0, topRightY = 0;
  double bottomRightX = 0, bottomRightY = 0;
  double bottomLeftX = 0, bottomLeftY = 0;
  double alpha = 0;
};

class ProMaxOneEuro {
 public:
  ProMaxOneEuro(double minCutoff = 1.2, double beta = 0.5, double derivativeCutoff = 1.0)
      : minCutoff_(minCutoff), beta_(beta), derivativeCutoff_(derivativeCutoff) {}

  bool ready() const { return ready_; }
  double value() const { return value_; }
  double derivative() const { return derivative_; }

  void reset(double value, double time) {
    ready_ = true;
    value_ = value;
    derivative_ = 0;
    time_ = time;
  }

  double filter(double value, double time, double unit) {
    if (!ready_) {
      reset(value, time);
      return value_;
    }
    const double elapsed = std::max(time - time_, 1e-3);
    const double rawDerivative = (value - value_) / elapsed;
    derivative_ += smoothing(derivativeCutoff_, elapsed) * (rawDerivative - derivative_);
    const double cutoff = minCutoff_ + beta_ * std::fabs(derivative_) / std::max(unit, 1e-6);
    value_ += smoothing(cutoff, elapsed) * (value - value_);
    time_ = time;
    return value_;
  }

  double predict(double time, double horizon) const {
    return value_ + derivative_ * std::clamp(time - time_, 0.0, horizon);
  }

 private:
  static double smoothing(double cutoff, double elapsed) {
    const double tau = 1.0 / (2 * kProMaxPi * cutoff);
    return 1.0 / (1.0 + tau / elapsed);
  }

  double minCutoff_;
  double beta_;
  double derivativeCutoff_;
  bool ready_ = false;
  double value_ = 0;
  double derivative_ = 0;
  double time_ = 0;
};

struct ProMaxFaceMeasurement {
  double x = 0, y = 0;
  double scale = 0;
  double roll = 0;
  double yaw = 0;
  double pitch = 0;
  double nose = 0;
  double mouth = 0;
};

inline bool promaxMeasureFace(const ProMaxFaceSample& sample, ProMaxFaceMeasurement& out) {
  double ax = sample.leftX, ay = sample.leftY;
  double bx = sample.rightX, by = sample.rightY;
  const double values[] = {ax, ay, bx, by, sample.noseX, sample.noseY, sample.mouthX, sample.mouthY};
  for (double value : values) {
    if (!std::isfinite(value)) return false;
  }
  const double eyeX = (ax + bx) / 2;
  const double eyeY = (ay + by) / 2;
  const double upX = eyeX - sample.mouthX;
  const double upY = eyeY - sample.mouthY;
  if ((bx - ax) * upY - (by - ay) * upX < 0) {
    std::swap(ax, bx);
    std::swap(ay, by);
  }
  const double spanX = bx - ax;
  const double spanY = by - ay;
  const double projected = std::hypot(spanX, spanY);
  if (projected < 4) return false;
  const double ux = spanX / projected;
  const double uy = spanY / projected;
  const double vx = -uy;
  const double vy = ux;
  const double noseShift = ((sample.noseX - eyeX) * ux + (sample.noseY - eyeY) * uy) / projected;
  const double yaw = std::asin(std::clamp(noseShift / 0.55, -1.0, 1.0));
  const double scale = projected / std::max(std::cos(yaw), 0.6);
  out.x = eyeX;
  out.y = eyeY;
  out.scale = scale;
  out.roll = std::atan2(spanY, spanX);
  out.yaw = yaw;
  out.pitch = std::isfinite(sample.pitch) ? std::clamp(sample.pitch, -kProMaxPi / 2, kProMaxPi / 2) : 0;
  out.nose = std::clamp(((eyeX - sample.noseX) * vx + (eyeY - sample.noseY) * vy) / scale, 0.2, 1.6);
  out.mouth = std::clamp(((eyeX - sample.mouthX) * vx + (eyeY - sample.mouthY) * vy) / scale, 0.5, 2.2);
  return true;
}

class ProMaxFaceTrack {
 public:
  static constexpr double kHorizon = 0.066;
  static constexpr double kFadeIn = 0.12;
  static constexpr double kHold = 0.25;
  static constexpr double kFadeOut = 0.15;

  ProMaxFaceTrack()
      : x_(1.2, 0.5), y_(1.2, 0.5), scale_(1.0, 0.3), roll_(1.0, 0.4), yaw_(1.0, 0.3), pitch_(1.0, 0.3),
        nose_(0.6, 0.1), mouth_(0.6, 0.1) {}

  bool active() const { return active_; }
  double lastSeen() const { return lastSeen_; }
  double x() const { return x_.value(); }
  double y() const { return y_.value(); }
  double scale() const { return std::exp(scale_.value()); }

  void observe(const ProMaxFaceMeasurement& measurement, double time) {
    const bool fresh = !active_ || time - lastSeen_ > kHold + kFadeOut;
    if (fresh) {
      appeared_ = time;
      restart(measurement, time);
    } else {
      const double current = scale();
      const double jump = std::hypot(measurement.x - x(), measurement.y - y()) / current;
      const double ratio = measurement.scale / current;
      const double since = time - lastSeen_;
      if (since > kHold) {
        const double visible = std::clamp(1 - (since - kHold) / kFadeOut, 0.0, 1.0);
        appeared_ = time - visible * kFadeIn;
      }
      if (jump > 1 || ratio > 1.5 || ratio < 1 / 1.5) {
        restart(measurement, time);
      } else {
        const double unit = current;
        x_.filter(measurement.x, time, unit);
        y_.filter(measurement.y, time, unit);
        scale_.filter(std::log(measurement.scale), time, 1);
        double roll = measurement.roll;
        while (roll - roll_.value() > kProMaxPi) roll -= 2 * kProMaxPi;
        while (roll - roll_.value() < -kProMaxPi) roll += 2 * kProMaxPi;
        roll_.filter(roll, time, 1);
        yaw_.filter(measurement.yaw, time, 1);
        pitch_.filter(measurement.pitch, time, 1);
        nose_.filter(measurement.nose, time, 1);
        mouth_.filter(measurement.mouth, time, 1);
      }
    }
    active_ = true;
    lastSeen_ = time;
  }

  bool pose(double time, ProMaxFacePose& out) {
    if (!active_) return false;
    const double since = time - lastSeen_;
    if (since > kHold + kFadeOut) {
      active_ = false;
      return false;
    }
    const double fadeIn = std::clamp((time - appeared_) / kFadeIn, 0.0, 1.0);
    const double fadeOut = since <= kHold ? 1.0 : std::clamp(1 - (since - kHold) / kFadeOut, 0.0, 1.0);
    out.x = x_.predict(time, kHorizon);
    out.y = y_.predict(time, kHorizon);
    out.scale = std::exp(scale_.predict(time, kHorizon));
    out.roll = roll_.predict(time, kHorizon);
    out.yaw = std::clamp(yaw_.predict(time, kHorizon), -kProMaxPi / 2, kProMaxPi / 2);
    out.pitch = std::clamp(pitch_.predict(time, kHorizon), -kProMaxPi / 2, kProMaxPi / 2);
    out.nose = nose_.value();
    out.mouth = mouth_.value();
    const double turn = std::max(std::fabs(out.yaw), std::fabs(out.pitch)) * 180 / kProMaxPi;
    const double turnFade = std::clamp((65 - turn) / 15, 0.0, 1.0);
    out.alpha = fadeIn * fadeOut * turnFade;
    return out.alpha > 0.001;
  }

 private:
  void restart(const ProMaxFaceMeasurement& measurement, double time) {
    x_.reset(measurement.x, time);
    y_.reset(measurement.y, time);
    scale_.reset(std::log(measurement.scale), time);
    roll_.reset(measurement.roll, time);
    yaw_.reset(measurement.yaw, time);
    pitch_.reset(measurement.pitch, time);
    nose_.reset(measurement.nose, time);
    mouth_.reset(measurement.mouth, time);
  }

  ProMaxOneEuro x_, y_, scale_, roll_, yaw_, pitch_, nose_, mouth_;
  bool active_ = false;
  double appeared_ = 0;
  double lastSeen_ = 0;
};

class ProMaxMaskTracker {
 public:
  static constexpr std::size_t kCapacity = 2;

  void reset() {
    for (auto& track : tracks_) track = ProMaxFaceTrack();
  }

  void update(const ProMaxFaceSample* samples, std::size_t count, double time) {
    bool claimed[kCapacity] = {false, false};
    for (std::size_t index = 0; index < std::min(count, kCapacity); ++index) {
      ProMaxFaceMeasurement measurement;
      if (!promaxMeasureFace(samples[index], measurement)) continue;
      std::size_t best = kCapacity;
      double bestDistance = 0;
      for (std::size_t slot = 0; slot < kCapacity; ++slot) {
        const auto& track = tracks_[slot];
        if (claimed[slot] || !track.active()) continue;
        const double distance = std::hypot(measurement.x - track.x(), measurement.y - track.y()) / track.scale();
        if (distance < 1.5 && (best == kCapacity || distance < bestDistance)) {
          best = slot;
          bestDistance = distance;
        }
      }
      if (best == kCapacity) {
        for (std::size_t slot = 0; slot < kCapacity; ++slot) {
          if (!claimed[slot] && !tracks_[slot].active()) {
            best = slot;
            break;
          }
        }
      }
      if (best == kCapacity) {
        double oldest = 0;
        for (std::size_t slot = 0; slot < kCapacity; ++slot) {
          if (claimed[slot]) continue;
          if (best == kCapacity || tracks_[slot].lastSeen() < oldest) {
            best = slot;
            oldest = tracks_[slot].lastSeen();
          }
        }
        if (best != kCapacity) tracks_[best] = ProMaxFaceTrack();
      }
      if (best == kCapacity) continue;
      claimed[best] = true;
      tracks_[best].observe(measurement, time);
    }
  }

  std::size_t poses(double time, ProMaxFacePose* out, std::size_t capacity) {
    std::size_t count = 0;
    for (auto& track : tracks_) {
      if (count >= capacity) break;
      if (track.pose(time, out[count])) ++count;
    }
    return count;
  }

 private:
  ProMaxFaceTrack tracks_[kCapacity];
};

inline std::size_t promaxMaskQuads(const ProMaxMaskSpec& spec, const ProMaxFacePose& pose, ProMaxMaskQuad* out,
                                   std::size_t capacity) {
  if (capacity == 0 || pose.scale <= 0 || spec.width <= 0 || spec.aspect <= 0) return 0;
  const double s = pose.scale;
  const double ux = std::cos(pose.roll);
  const double uy = std::sin(pose.roll);
  const double vx = -uy;
  const double vy = ux;
  double anchors[2][2] = {{pose.x, pose.y}, {pose.x, pose.y}};
  std::size_t anchorCount = 1;
  switch (spec.anchor) {
    case ProMaxMaskAnchorEachEye:
      anchors[0][0] = pose.x - ux * s * 0.5;
      anchors[0][1] = pose.y - uy * s * 0.5;
      anchors[1][0] = pose.x + ux * s * 0.5;
      anchors[1][1] = pose.y + uy * s * 0.5;
      anchorCount = 2;
      break;
    case ProMaxMaskAnchorForehead:
      anchors[0][0] = pose.x + vx * s * pose.mouth * 0.9;
      anchors[0][1] = pose.y + vy * s * pose.mouth * 0.9;
      break;
    case ProMaxMaskAnchorNose:
      anchors[0][0] = pose.x - vx * s * pose.nose;
      anchors[0][1] = pose.y - vy * s * pose.nose;
      break;
    case ProMaxMaskAnchorFace:
      anchors[0][0] = pose.x - vx * s * pose.mouth * 0.35;
      anchors[0][1] = pose.y - vy * s * pose.mouth * 0.35;
      break;
    case ProMaxMaskAnchorMouth:
      anchors[0][0] = pose.x - vx * s * pose.mouth;
      anchors[0][1] = pose.y - vy * s * pose.mouth;
      break;
    default:
      break;
  }
  const double turn = std::sin(pose.yaw);
  const double squeezeX = std::max(std::cos(pose.yaw), 0.35);
  const double squeezeY = std::max(std::cos(pose.pitch), 0.5);
  const double perspective = 0.15 * turn;
  const double width = spec.width * s * squeezeX;
  const double height = spec.width * spec.aspect * s * squeezeY;
  const double cosAngle = ux;
  const double sinAngle = uy;
  std::size_t count = 0;
  for (std::size_t index = 0; index < anchorCount && count < capacity; ++index) {
    const double shiftX = spec.offsetX + turn * spec.depth;
    const double centerX = anchors[index][0] + ux * s * shiftX + vx * s * spec.offsetY;
    const double centerY = anchors[index][1] + uy * s * shiftX + vy * s * spec.offsetY;
    double corners[4][2];
    const double cornerX[4] = {0, 1, 1, 0};
    const double cornerY[4] = {0, 0, 1, 1};
    for (int corner = 0; corner < 4; ++corner) {
      const double side = cornerX[corner] > 0.5 ? 1 - perspective : 1 + perspective;
      const double localX = (cornerX[corner] - spec.pivotX) * width;
      const double localY = (spec.pivotY - cornerY[corner]) * height * side;
      corners[corner][0] = centerX + localX * cosAngle - localY * sinAngle;
      corners[corner][1] = centerY + localX * sinAngle + localY * cosAngle;
    }
    ProMaxMaskQuad& quad = out[count++];
    quad.topLeftX = corners[0][0];
    quad.topLeftY = corners[0][1];
    quad.topRightX = corners[1][0];
    quad.topRightY = corners[1][1];
    quad.bottomRightX = corners[2][0];
    quad.bottomRightY = corners[2][1];
    quad.bottomLeftX = corners[3][0];
    quad.bottomLeftY = corners[3][1];
    quad.alpha = pose.alpha;
  }
  return count;
}
