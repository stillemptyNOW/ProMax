import 'package:flutter_test/flutter_test.dart';
import 'package:promax/core/calls/ice_privacy.dart';

const _host =
    'candidate:1 1 udp 2122260223 192.168.0.10 50000 typ host generation 0';
const _hostTcp =
    'candidate:2 1 tcp 1518280447 192.168.0.10 9 typ host tcptype active';
const _srflx =
    'candidate:3 1 udp 1686052607 203.0.113.5 50001 typ srflx '
    'raddr 192.168.0.10 rport 50000';
const _relay =
    'candidate:4 1 udp 41885439 198.51.100.9 3478 typ relay '
    'raddr 203.0.113.5 rport 50001';

void main() {
  test('host-кандидаты распознаются, остальные нет', () {
    expect(IcePrivacy.isHostCandidate(_host), isTrue);
    expect(IcePrivacy.isHostCandidate('a=$_hostTcp'), isTrue);
    expect(IcePrivacy.isHostCandidate(_srflx), isFalse);
    expect(IcePrivacy.isHostCandidate(_relay), isFalse);
    expect(IcePrivacy.isHostCandidate(null), isFalse);
  });

  test('из SDP вырезаются только host-кандидаты', () {
    const sdp =
        'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
        'a=$_host\r\na=$_hostTcp\r\na=$_srflx\r\na=$_relay\r\n'
        'a=end-of-candidates\r\n';
    final stripped = IcePrivacy.stripHostCandidates(sdp);
    expect(stripped, isNot(contains('192.168.0.10 50000 typ host')));
    expect(stripped, isNot(contains('typ host tcptype')));
    expect(stripped, contains('typ srflx'));
    expect(stripped, contains('typ relay'));
    expect(stripped, startsWith('v=0\r\nm=audio'));
    expect(stripped, endsWith('a=end-of-candidates\r\n'));
  });

  test('SDP без host-кандидатов не меняется', () {
    const sdp = 'v=0\na=$_relay\n';
    expect(IcePrivacy.stripHostCandidates(sdp), sdp);
  });

  test('relay включается только когда сервер дал TURN', () {
    final withTurn = [
      {'urls': 'stun:stun.example.org:3478'},
      {
        'urls': ['turn:turn.example.org:3478?transport=udp'],
        'username': 'u',
        'credential': 'c',
      },
    ];
    final stunOnly = [
      {'urls': 'stun:stun.example.org:3478'},
    ];
    expect(IcePrivacy.hasTurnServer(withTurn), isTrue);
    expect(IcePrivacy.hasTurnServer(stunOnly), isFalse);
    expect(IcePrivacy.useRelayOnly(withTurn, requested: true), isTrue);
    expect(IcePrivacy.useRelayOnly(withTurn, requested: false), isFalse);
    expect(IcePrivacy.useRelayOnly(stunOnly, requested: true), isFalse);
  });
}
