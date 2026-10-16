abstract final class IcePrivacy {
  static final RegExp _hostCandidate = RegExp(
    r'^(?:a=)?candidate:\S+(?:\s+\S+){5}\s+typ\s+host(?:\s|$)',
  );

  static bool isHostCandidate(String? candidate) {
    if (candidate == null) return false;
    return _hostCandidate.hasMatch(candidate.trim());
  }

  static String stripHostCandidates(String sdp) {
    if (!sdp.contains('typ host')) return sdp;
    final separator = sdp.contains('\r\n') ? '\r\n' : '\n';
    final lines = sdp.split(separator);
    final kept = [
      for (final line in lines)
        if (!line.startsWith('a=candidate:') || !isHostCandidate(line)) line,
    ];
    return kept.join(separator);
  }

  static bool hasTurnServer(List iceServers) {
    for (final server in iceServers.whereType<Map>()) {
      final urls = server['urls'] ?? server['url'];
      final list = urls is List ? urls : [urls];
      for (final url in list) {
        final value = url?.toString().trim().toLowerCase() ?? '';
        if (value.startsWith('turn:') || value.startsWith('turns:')) {
          return true;
        }
      }
    }
    return false;
  }

  static bool useRelayOnly(List iceServers, {required bool requested}) =>
      requested && hasTurnServer(iceServers);
}
