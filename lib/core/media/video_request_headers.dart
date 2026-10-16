import '../privacy/neutral_user_agent.dart';

/// Headers for a remote video request.
///
/// Links bound to a client (`srcAg=UNKNOWN_ANDROID` and the like) are
/// checked by the CDN against the `User-Agent` of the request, and a
/// mismatch is answered with HTTP 400. The link is issued for the Android
/// handshake identity, so the agent sent to the CDN must read as Android.
/// Only the product token of the session agent is kept and marked as
/// Android: the device model, OS build and screen of the session agent
/// never reach the CDN. Players never fall back to their own agent, which
/// on iOS names the iPhone.
Map<String, String> videoRequestHeaders(
  Uri uri, {
  required String? sessionUserAgent,
}) {
  if (!_isAgentBound(uri)) return const {};
  final userAgent = sessionUserAgent?.trim();
  if (userAgent == null || userAgent.isEmpty) return const {};
  return {'User-Agent': cdnUserAgent(userAgent)};
}

/// The agent sent to the CDN for a session agent.
String cdnUserAgent(String sessionUserAgent) =>
    NeutralUserAgent.cdnFromSession(sessionUserAgent);

const _agentBoundHosts = ['okcdn.ru', 'vkuser.net'];

bool _isAgentBound(Uri uri) {
  if (uri.queryParameters.containsKey('srcAg')) return true;
  final host = uri.host.toLowerCase();
  return _agentBoundHosts.any(
    (domain) => host == domain || host.endsWith('.$domain'),
  );
}
