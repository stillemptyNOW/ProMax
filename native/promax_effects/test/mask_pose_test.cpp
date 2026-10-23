#include "../ios/Classes/MaskPose.h"
#include <cassert>
#include <cmath>
#include <random>

ProMaxFaceSample face(double x, double y, double iod, double roll) {
  const double ux = std::cos(roll), uy = std::sin(roll);
  const double vx = -uy, vy = ux;
  ProMaxFaceSample sample;
  sample.leftX = x - ux * iod / 2;
  sample.leftY = y - uy * iod / 2;
  sample.rightX = x + ux * iod / 2;
  sample.rightY = y + uy * iod / 2;
  sample.noseX = x - vx * iod * 0.7;
  sample.noseY = y - vy * iod * 0.7;
  sample.mouthX = x - vx * iod * 1.15;
  sample.mouthY = y - vy * iod * 1.15;
  return sample;
}

bool near(double a, double b, double tolerance) { return std::fabs(a - b) <= tolerance; }

void testMeasurementIsOrderIndependent() {
  ProMaxFaceSample sample = face(320, 240, 100, 0.3);
  ProMaxFaceMeasurement direct, swapped;
  assert(promaxMeasureFace(sample, direct));
  std::swap(sample.leftX, sample.rightX);
  std::swap(sample.leftY, sample.rightY);
  assert(promaxMeasureFace(sample, swapped));
  assert(near(direct.roll, 0.3, 1e-9) && near(swapped.roll, 0.3, 1e-9));
  assert(near(direct.scale, 100, 1e-9));
  assert(near(direct.nose, 0.7, 1e-9) && near(direct.mouth, 1.15, 1e-9));
  assert(near(direct.yaw, 0, 1e-9));
  ProMaxFaceSample tiny = face(10, 10, 2, 0);
  assert(!promaxMeasureFace(tiny, direct));
  ProMaxFaceSample broken = face(10, 10, 50, 0);
  broken.noseX = NAN;
  assert(!promaxMeasureFace(broken, direct));
}

void testSmoothingReducesJitter() {
  ProMaxMaskTracker tracker;
  std::mt19937 random(7);
  std::normal_distribution<double> noise(0, 3);
  double rawError = 0, smoothError = 0;
  for (int frame = 0; frame < 150; ++frame) {
    const double time = frame / 15.0;
    ProMaxFaceSample sample = face(400 + noise(random), 300 + noise(random), 120, 0);
    tracker.update(&sample, 1, time);
    ProMaxFacePose pose;
    assert(tracker.poses(time, &pose, 1) == (frame > 0 ? 1u : 0u));
    if (frame > 30) {
      rawError += std::hypot((sample.leftX + sample.rightX) / 2 - 400, (sample.leftY + sample.rightY) / 2 - 300);
      smoothError += std::hypot(pose.x - 400, pose.y - 300);
    }
  }
  assert(smoothError < rawError * 0.7);
}

void testFadeInHoldAndFadeOut() {
  ProMaxMaskTracker tracker;
  ProMaxFaceSample sample = face(200, 200, 80, 0);
  ProMaxFacePose pose;
  tracker.update(&sample, 1, 10.0);
  assert(tracker.poses(10.0, &pose, 1) == 0 || pose.alpha < 0.05);
  assert(tracker.poses(10.06, &pose, 1) == 1 && near(pose.alpha, 0.5, 0.01));
  tracker.update(&sample, 1, 10.2);
  assert(tracker.poses(10.2, &pose, 1) == 1 && near(pose.alpha, 1, 1e-9));
  assert(tracker.poses(10.4, &pose, 1) == 1 && near(pose.alpha, 1, 1e-9));
  assert(tracker.poses(10.525, &pose, 1) == 1 && near(pose.alpha, 0.5, 0.01));
  assert(tracker.poses(10.7, &pose, 1) == 0);
  tracker.update(&sample, 1, 11.0);
  assert(tracker.poses(11.0, &pose, 1) == 0 || pose.alpha < 0.05);
}

void testJumpResetsFilter() {
  ProMaxMaskTracker tracker;
  ProMaxFacePose pose;
  for (int frame = 0; frame < 20; ++frame) {
    ProMaxFaceSample sample = face(200, 200, 80, 0);
    tracker.update(&sample, 1, frame / 15.0);
  }
  ProMaxFaceSample moved = face(296, 200, 80, 0);
  tracker.update(&moved, 1, 20 / 15.0);
  assert(tracker.poses(20 / 15.0, &pose, 1) == 1);
  assert(near(pose.x, 296, 1e-6) && near(pose.alpha, 1, 1e-9));
  ProMaxFaceSample grown = face(296, 200, 130, 0);
  tracker.update(&grown, 1, 21 / 15.0);
  assert(tracker.poses(21 / 15.0, &pose, 1) == 1);
  assert(near(pose.scale, 130, 1e-6));
}

void testTwoFacesKeepTheirTracks() {
  ProMaxMaskTracker tracker;
  ProMaxFacePose poses[2];
  for (int frame = 0; frame < 30; ++frame) {
    ProMaxFaceSample samples[2] = {face(150 + frame, 200, 60, 0), face(500 - frame, 220, 70, 0)};
    if (frame % 2) std::swap(samples[0], samples[1]);
    tracker.update(samples, 2, frame / 15.0);
  }
  assert(tracker.poses(29 / 15.0, poses, 2) == 2);
  const double left = std::min(poses[0].x, poses[1].x);
  const double right = std::max(poses[0].x, poses[1].x);
  assert(near(left, 179, 3) && near(right, 471, 3));
}

void testQuadsFollowTheHead() {
  ProMaxFacePose pose;
  pose.x = 100;
  pose.y = 100;
  pose.scale = 50;
  pose.mouth = 1.1;
  pose.nose = 0.7;
  pose.alpha = 1;
  ProMaxMaskSpec glasses;
  glasses.width = 2;
  ProMaxMaskQuad quads[2];
  assert(promaxMaskQuads(glasses, pose, quads, 2) == 1);
  assert(near(quads[0].topLeftX, 50, 1e-9) && near(quads[0].topLeftY, 150, 1e-9));
  assert(near(quads[0].bottomRightX, 150, 1e-9) && near(quads[0].bottomRightY, 50, 1e-9));
  ProMaxMaskSpec hearts;
  hearts.anchor = ProMaxMaskAnchorEachEye;
  hearts.width = 0.8;
  assert(promaxMaskQuads(hearts, pose, quads, 2) == 2);
  assert(near((quads[0].topLeftX + quads[0].bottomRightX) / 2, 75, 1e-9));
  assert(near((quads[1].topLeftX + quads[1].bottomRightX) / 2, 125, 1e-9));
  ProMaxMaskSpec crown;
  crown.anchor = ProMaxMaskAnchorForehead;
  crown.pivotY = 1;
  assert(promaxMaskQuads(crown, pose, quads, 1) == 1);
  assert(near(quads[0].bottomLeftY, 100 + 50 * 1.1 * 0.9, 1e-9));
  ProMaxMaskSpec mustache;
  mustache.anchor = ProMaxMaskAnchorMouth;
  mustache.width = 1.5;
  mustache.aspect = 0.5;
  mustache.offsetY = 0.2;
  assert(promaxMaskQuads(mustache, pose, quads, 1) == 1);
  assert(near((quads[0].topLeftY + quads[0].bottomLeftY) / 2, 100 - 50 * 1.1 + 50 * 0.2, 1e-9));
  assert(near(quads[0].topRightX - quads[0].topLeftX, 75, 1e-9));
  assert(near(quads[0].topLeftY - quads[0].bottomLeftY, 37.5, 1e-9));
  ProMaxMaskSpec snout;
  snout.anchor = ProMaxMaskAnchorNose;
  snout.width = 1;
  assert(promaxMaskQuads(snout, pose, quads, 1) == 1);
  assert(near((quads[0].topLeftY + quads[0].bottomLeftY) / 2, 100 - 50 * 0.7, 1e-9));
  pose.alpha = 0.25;
  assert(promaxMaskQuads(snout, pose, quads, 1) == 1 && near(quads[0].alpha, 0.25, 1e-12));
  pose.alpha = 1;
  ProMaxMaskSpec broken;
  broken.width = 0;
  assert(promaxMaskQuads(broken, pose, quads, 1) == 0);
  assert(promaxMaskQuads(glasses, pose, quads, 0) == 0);
  pose.roll = kProMaxPi / 2;
  assert(promaxMaskQuads(glasses, pose, quads, 1) == 1);
  assert(near(quads[0].topLeftX, 50, 1e-9) && near(quads[0].topLeftY, 50, 1e-9));
  pose.roll = 0;
  pose.yaw = 0.5;
  ProMaxMaskSpec deep = glasses;
  deep.depth = 0.3;
  assert(promaxMaskQuads(deep, pose, quads, 1) == 1);
  const double center = (quads[0].topLeftX + quads[0].topRightX) / 2;
  assert(center > 100);
  assert(quads[0].topRightX - quads[0].topLeftX < 100);
  assert(quads[0].topRightY - quads[0].bottomRightY < quads[0].topLeftY - quads[0].bottomLeftY);
}

void testReacquiredFaceFadesBackIn() {
  ProMaxMaskTracker tracker;
  ProMaxFaceSample sample = face(200, 200, 80, 0);
  ProMaxFacePose pose;
  tracker.update(&sample, 1, 0.0);
  tracker.update(&sample, 1, 0.2);
  assert(tracker.poses(0.525, &pose, 1) == 1 && near(pose.alpha, 0.5, 0.01));
  tracker.update(&sample, 1, 0.525);
  assert(tracker.poses(0.525, &pose, 1) == 1 && near(pose.alpha, 0.5, 0.01));
  assert(tracker.poses(0.585, &pose, 1) == 1 && near(pose.alpha, 1, 1e-9));
}

void testAnchorNames() {
  int anchor = -1;
  assert(promaxMaskAnchorNamed("eyes", anchor) && anchor == ProMaxMaskAnchorEyes);
  assert(promaxMaskAnchorNamed("eachEye", anchor) && anchor == ProMaxMaskAnchorEachEye);
  assert(promaxMaskAnchorNamed("forehead", anchor) && anchor == ProMaxMaskAnchorForehead);
  assert(promaxMaskAnchorNamed("nose", anchor) && anchor == ProMaxMaskAnchorNose);
  assert(promaxMaskAnchorNamed("mouth", anchor) && anchor == ProMaxMaskAnchorMouth);
  assert(promaxMaskAnchorNamed("face", anchor) && anchor == ProMaxMaskAnchorFace);
  assert(!promaxMaskAnchorNamed("chin", anchor) && anchor == ProMaxMaskAnchorFace);
  assert(!promaxMaskAnchorNamed(nullptr, anchor));
}

int main() {
  testMeasurementIsOrderIndependent();
  testSmoothingReducesJitter();
  testFadeInHoldAndFadeOut();
  testJumpResetsFilter();
  testTwoFacesKeepTheirTracks();
  testQuadsFollowTheHead();
  testReacquiredFaceFadesBackIn();
  testAnchorNames();
  return 0;
}
