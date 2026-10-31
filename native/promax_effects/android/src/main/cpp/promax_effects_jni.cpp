#include <jni.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <mutex>
#include <new>

#include "MaskPose.h"
#include "VoiceProcessor.h"

namespace {

constexpr int kSampleStride = 9;
constexpr int kSpecSize = 8;
constexpr int kQuadStride = 9;
constexpr std::size_t kQuadCapacity = ProMaxMaskTracker::kCapacity * 2;

struct ProMaxTrackerHandle {
  std::mutex lock;
  ProMaxMaskTracker tracker;
};

ProMaxTrackerHandle* trackerFrom(jlong handle) { return reinterpret_cast<ProMaxTrackerHandle*>(handle); }

ProMaxVoiceProcessor* voiceFrom(jlong handle) { return reinterpret_cast<ProMaxVoiceProcessor*>(handle); }

}

extern "C" {

JNIEXPORT jint JNICALL Java_promax_effects_NativeEffects_maskAnchor(JNIEnv* env, jobject, jstring name) {
  if (!name) return -1;
  const char* chars = env->GetStringUTFChars(name, nullptr);
  if (!chars) return -1;
  int anchor = -1;
  const bool known = promaxMaskAnchorNamed(chars, anchor);
  env->ReleaseStringUTFChars(name, chars);
  return known ? anchor : -1;
}

JNIEXPORT jlong JNICALL Java_promax_effects_NativeEffects_voiceCreate(JNIEnv*, jobject) {
  return reinterpret_cast<jlong>(new (std::nothrow) ProMaxVoiceProcessor());
}

JNIEXPORT void JNICALL Java_promax_effects_NativeEffects_voiceDestroy(JNIEnv*, jobject, jlong handle) {
  delete voiceFrom(handle);
}

JNIEXPORT void JNICALL Java_promax_effects_NativeEffects_voiceProcess(JNIEnv* env, jobject, jlong handle, jint mode,
                                                                     jint rate, jobject buffer, jint frames) {
  ProMaxVoiceProcessor* voice = voiceFrom(handle);
  if (!voice || !buffer || frames <= 0 || mode < 0 || mode > 4) return;
  auto* data = static_cast<float*>(env->GetDirectBufferAddress(buffer));
  const jlong capacity = env->GetDirectBufferCapacity(buffer);
  if (!data || capacity <= 0) return;
  const auto available = static_cast<std::size_t>(capacity) / sizeof(float);
  const std::size_t count = std::min(static_cast<std::size_t>(frames), available);
  if (count == 0) return;
  voice->configure(mode, rate > 0 ? rate : static_cast<double>(count) * 100.0);
  float* channels[2] = {data, nullptr};
  voice->process(channels, 1, count);
}

JNIEXPORT jlong JNICALL Java_promax_effects_NativeEffects_trackerCreate(JNIEnv*, jobject) {
  return reinterpret_cast<jlong>(new (std::nothrow) ProMaxTrackerHandle());
}

JNIEXPORT void JNICALL Java_promax_effects_NativeEffects_trackerDestroy(JNIEnv*, jobject, jlong handle) {
  delete trackerFrom(handle);
}

JNIEXPORT void JNICALL Java_promax_effects_NativeEffects_trackerReset(JNIEnv*, jobject, jlong handle) {
  ProMaxTrackerHandle* tracker = trackerFrom(handle);
  if (!tracker) return;
  std::lock_guard<std::mutex> guard(tracker->lock);
  tracker->tracker.reset();
}

JNIEXPORT void JNICALL Java_promax_effects_NativeEffects_trackerUpdate(JNIEnv* env, jobject, jlong handle,
                                                                      jdoubleArray samples, jint count, jdouble time) {
  ProMaxTrackerHandle* tracker = trackerFrom(handle);
  if (!tracker || !samples || count < 0) return;
  const jsize length = env->GetArrayLength(samples);
  const std::size_t faces = std::min<std::size_t>(
      {static_cast<std::size_t>(count), ProMaxMaskTracker::kCapacity, static_cast<std::size_t>(length / kSampleStride)});
  jdouble values[ProMaxMaskTracker::kCapacity * kSampleStride];
  if (faces > 0) env->GetDoubleArrayRegion(samples, 0, static_cast<jsize>(faces * kSampleStride), values);
  ProMaxFaceSample parsed[ProMaxMaskTracker::kCapacity];
  for (std::size_t index = 0; index < faces; ++index) {
    const jdouble* sample = values + index * kSampleStride;
    parsed[index].leftX = sample[0];
    parsed[index].leftY = sample[1];
    parsed[index].rightX = sample[2];
    parsed[index].rightY = sample[3];
    parsed[index].noseX = sample[4];
    parsed[index].noseY = sample[5];
    parsed[index].mouthX = sample[6];
    parsed[index].mouthY = sample[7];
    parsed[index].pitch = sample[8];
  }
  std::lock_guard<std::mutex> guard(tracker->lock);
  tracker->tracker.update(parsed, faces, time);
}

JNIEXPORT jint JNICALL Java_promax_effects_NativeEffects_trackerQuads(JNIEnv* env, jobject, jlong handle, jdouble time,
                                                                     jdoubleArray spec, jdoubleArray out) {
  ProMaxTrackerHandle* tracker = trackerFrom(handle);
  if (!tracker || !spec || !out || env->GetArrayLength(spec) < kSpecSize) return 0;
  const std::size_t capacity =
      std::min(kQuadCapacity, static_cast<std::size_t>(env->GetArrayLength(out) / kQuadStride));
  if (capacity == 0) return 0;
  jdouble values[kSpecSize];
  env->GetDoubleArrayRegion(spec, 0, kSpecSize, values);
  ProMaxMaskSpec mask;
  mask.anchor = static_cast<int>(values[0]);
  mask.width = values[1];
  mask.aspect = values[2];
  mask.offsetX = values[3];
  mask.offsetY = values[4];
  mask.pivotX = values[5];
  mask.pivotY = values[6];
  mask.depth = values[7];
  ProMaxFacePose poses[ProMaxMaskTracker::kCapacity];
  std::size_t faces = 0;
  {
    std::lock_guard<std::mutex> guard(tracker->lock);
    faces = tracker->tracker.poses(time, poses, ProMaxMaskTracker::kCapacity);
  }
  ProMaxMaskQuad quads[kQuadCapacity];
  std::size_t count = 0;
  for (std::size_t face = 0; face < faces && count < capacity; ++face) {
    count += promaxMaskQuads(mask, poses[face], quads + count, capacity - count);
  }
  jdouble result[kQuadCapacity * kQuadStride];
  for (std::size_t index = 0; index < count; ++index) {
    const ProMaxMaskQuad& quad = quads[index];
    jdouble* slot = result + index * kQuadStride;
    slot[0] = quad.topLeftX;
    slot[1] = quad.topLeftY;
    slot[2] = quad.topRightX;
    slot[3] = quad.topRightY;
    slot[4] = quad.bottomRightX;
    slot[5] = quad.bottomRightY;
    slot[6] = quad.bottomLeftX;
    slot[7] = quad.bottomLeftY;
    slot[8] = quad.alpha;
  }
  if (count > 0) env->SetDoubleArrayRegion(out, 0, static_cast<jsize>(count * kQuadStride), result);
  return static_cast<jint>(count);
}

}
