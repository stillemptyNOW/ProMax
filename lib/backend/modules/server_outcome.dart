import '../../core/protocol/packet.dart';

sealed class ServerOutcome {
  const ServerOutcome();

  bool get ok => this is ServerDone;
}

final class ServerDone extends ServerOutcome {
  const ServerDone();
}

final class ServerRejected extends ServerOutcome {
  const ServerRejected(this.message, {this.errorKey, this.notFound = false});

  final String message;
  final String? errorKey;
  final bool notFound;
}

final class ServerUnreachable extends ServerOutcome {
  const ServerUnreachable(this.reason);

  final String reason;
}

Future<ServerOutcome> runServerAction(Future<Packet> Function() request) async {
  try {
    final packet = await request();
    if (packet.isOk) return const ServerDone();
    return ServerRejected(
      messageFromErrorPayload(packet.payload),
      notFound: packet.cmd == CmdType.notFound,
    );
  } catch (e) {
    return outcomeOfError(e);
  }
}

ServerOutcome outcomeOfError(Object error) {
  if (error is PacketError && isPermanentSendFailure(error)) {
    return ServerRejected(error.message, errorKey: error.errorKey);
  }
  if (error is PacketError) return ServerUnreachable(error.message);
  return ServerUnreachable('$error');
}

String describeReply(Packet packet, {int limit = 300}) {
  final body = '${packet.payload}';
  final brief = body.length > limit ? '${body.substring(0, limit)}…' : body;
  return 'cmd ${packet.cmd}: $brief';
}

final class MessageDeletionReply {
  const MessageDeletionReply(this.outcome, {this.confirmed = const {}});

  factory MessageDeletionReply.fromPacket(Packet packet) =>
      MessageDeletionReply(
        const ServerDone(),
        confirmed: confirmedMessageIds(packet.payload),
      );

  final ServerOutcome outcome;
  final Set<String> confirmed;

  List<String> unconfirmedOf(Iterable<String> requested) => [
    for (final id in requested)
      if (int.tryParse(id) != null && !confirmed.contains(id)) id,
  ];

  static bool listsMessageIds(Object? payload) =>
      payload is Map && payload['messageIds'] is List;

  static Set<String> confirmedMessageIds(Object? payload) {
    if (payload is! Map) return const {};
    final ids = payload['messageIds'];
    if (ids is! List) return const {};
    return {
      for (final id in ids)
        if (_messageId(id) case final parsed?) '$parsed',
    };
  }

  static int? _messageId(Object? raw) => switch (raw) {
    int id => id,
    num id => id.toInt(),
    String id => int.tryParse(id),
    _ => null,
  };
}
