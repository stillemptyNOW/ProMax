abstract final class CallsIdentity {
  static String? device({
    required bool spoofed,
    required bool hideRealDevice,
    required String deviceName,
    String? spoofUserAgent,
    String? manufacturer,
    String? model,
  }) {
    if (!spoofed) {
      if (hideRealDevice) return null;
      if (manufacturer != null &&
          manufacturer.isNotEmpty &&
          model != null &&
          model.isNotEmpty) {
        return '$manufacturer/$model';
      }
    }
    final parts = deviceName.trim().split(RegExp(r'\s+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return null;
    final fallbackModel = parts.length > 1
        ? parts.sublist(1).join(' ')
        : parts.first;
    return '${parts.first}/'
        '${modelFromUserAgent(spoofUserAgent) ?? fallbackModel}';
  }

  static String osVersion({
    required bool spoofed,
    required bool hideRealDevice,
    required String osVersion,
    int? sdkInt,
  }) {
    if (!spoofed && !hideRealDevice && sdkInt != null && sdkInt > 0) {
      return '$sdkInt';
    }
    final release = RegExp(
      r'^Android\s+(\d+)',
    ).firstMatch(osVersion.trim())?.group(1);
    return '${androidSdkForRelease(int.tryParse(release ?? ''))}';
  }

  static String? modelFromUserAgent(String? userAgent) {
    if (userAgent == null || userAgent.isEmpty) return null;
    final match = RegExp(r'Android\s+[\d.]+;\s*([^;)]+)').firstMatch(userAgent);
    final model = match
        ?.group(1)
        ?.replaceFirst(RegExp(r'\s+Build/.*$'), '')
        .trim();
    return model == null || model.isEmpty ? null : model;
  }

  static int androidSdkForRelease(int? release) => switch (release) {
    null => 34,
    <= 9 => 28,
    10 => 29,
    11 => 30,
    12 => 31,
    13 => 33,
    14 => 34,
    15 => 35,
    _ => 36,
  };
}
