import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/chat_deletion_plan.dart';
import 'package:promax/backend/modules/server_outcome.dart';

void main() {
  group('which requests a chat deletion becomes', () {
    test('a dialog deleted for both erases the history for everyone', () {
      final plan = ChatDeletionPlan.of(chatType: 'DIALOG', forAll: true);
      expect(plan.clearForAll, isTrue);
      expect(plan.deleteForAll, isFalse);
    });

    test('a chat of unknown type is treated as a dialog', () {
      expect(
        ChatDeletionPlan.of(chatType: null, forAll: true),
        ChatDeletionPlan.eraseForPeer,
      );
    });

    test('a group removed for all members goes through chat deletion', () {
      final plan = ChatDeletionPlan.of(chatType: 'CHAT', forAll: true);
      expect(plan.clearForAll, isFalse);
      expect(plan.deleteForAll, isTrue);
    });

    test('a deletion only for me never touches the other side', () {
      for (final type in ['DIALOG', 'CHAT', 'CHANNEL', null]) {
        expect(
          ChatDeletionPlan.of(chatType: type, forAll: false),
          ChatDeletionPlan.forMe,
        );
      }
    });
  });

  group('running the plan', () {
    late List<String> sent;

    Future<ServerOutcome> run(
      ChatDeletionPlan plan, {
      ServerOutcome clear = const ServerDone(),
      ServerOutcome delete = const ServerDone(),
    }) => plan.run(
      clearHistoryForAll: () async {
        sent.add('clear:all');
        return clear;
      },
      deleteChat: ({required bool forAll}) async {
        sent.add(forAll ? 'delete:all' : 'delete:me');
        return delete;
      },
    );

    setUp(() => sent = []);

    test('the history is erased for both before the chat is removed', () async {
      final outcome = await run(ChatDeletionPlan.eraseForPeer);
      expect(outcome, isA<ServerDone>());
      expect(sent, ['clear:all', 'delete:me']);
    });

    test('a refused erase keeps the chat and reports the refusal', () async {
      final outcome = await run(
        ChatDeletionPlan.eraseForPeer,
        clear: const ServerRejected('нельзя'),
      );
      expect(outcome, isA<ServerRejected>());
      expect((outcome as ServerRejected).message, 'нельзя');
      expect(sent, ['clear:all']);
    });

    test('a lost erase is retried as a whole', () async {
      final outcome = await run(
        ChatDeletionPlan.eraseForPeer,
        clear: const ServerUnreachable('таймаут'),
      );
      expect(outcome, isA<ServerUnreachable>());
      expect(sent, ['clear:all']);
    });

    test('a refused removal after the erase is still reported', () async {
      final outcome = await run(
        ChatDeletionPlan.eraseForPeer,
        delete: const ServerRejected('нет доступа'),
      );
      expect(outcome, isA<ServerRejected>());
      expect(sent, ['clear:all', 'delete:me']);
    });

    test('a group removal sends one request for all members', () async {
      await run(ChatDeletionPlan.removeForMembers);
      expect(sent, ['delete:all']);
    });
  });
}
