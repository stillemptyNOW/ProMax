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
