import 'package:flutter_test/flutter_test.dart';
import 'package:promax/backend/modules/chat_deletion_plan.dart';
import 'package:promax/backend/modules/server_outcome.dart';

void main() {
  group('which requests a chat deletion becomes', () {
    test('a dialog deleted for both erases the history for everyone', () {
      expect(
        ChatDeletionPlan.of(chatType: 'DIALOG', forAll: true),
        ChatDeletionPlan.eraseForPeer,
      );
      expect(ChatDeletionPlan.eraseForPeer.clearForAll, isTrue);
      expect(ChatDeletionPlan.eraseForPeer.deleteForAll, isFalse);
    });

    test('a chat of unknown type gets no plan for everyone', () {
      expect(ChatDeletionPlan.of(chatType: null, forAll: true), isNull);
    });

    test('a group removed for all members goes through chat deletion', () {
      for (final type in ['CHAT', 'CHANNEL']) {
        expect(
          ChatDeletionPlan.of(chatType: type, forAll: true),
          ChatDeletionPlan.removeForMembers,
        );
      }
      expect(ChatDeletionPlan.removeForMembers.clearForAll, isFalse);
      expect(ChatDeletionPlan.removeForMembers.deleteForAll, isTrue);
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

    Future<ChatDeletionResult> run(
      ChatDeletionPlan plan, {
      ServerOutcome clear = const ServerDone(),
      ServerOutcome delete = const ServerDone(),
      bool historyErased = false,
    }) => plan.run(
      historyErased: historyErased,
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
      final result = await run(ChatDeletionPlan.eraseForPeer);
      expect(result.outcome, isA<ServerDone>());
      expect(result.historyErased, isTrue);
      expect(sent, ['clear:all', 'delete:me']);
    });

    test('a refused erase keeps the chat and reports the refusal', () async {
      final result = await run(
        ChatDeletionPlan.eraseForPeer,
        clear: const ServerRejected('нельзя'),
      );
      expect((result.outcome as ServerRejected).message, 'нельзя');
      expect(result.historyErased, isFalse);
      expect(sent, ['clear:all']);
    });

    test('a lost erase is retried as a whole', () async {
      final result = await run(
        ChatDeletionPlan.eraseForPeer,
        clear: const ServerUnreachable('таймаут'),
      );
      expect(result.outcome, isA<ServerUnreachable>());
      expect(result.historyErased, isFalse);
      expect(sent, ['clear:all']);
    });

    test(
      'a refused removal after the erase says the history is gone',
      () async {
        final result = await run(
          ChatDeletionPlan.eraseForPeer,
          delete: const ServerRejected('нет доступа'),
        );
        expect(result.outcome, isA<ServerRejected>());
        expect(result.historyErased, isTrue);
        expect(sent, ['clear:all', 'delete:me']);
      },
    );

    test('a retry after the erase only removes the chat', () async {
      final result = await run(
        ChatDeletionPlan.eraseForPeer,
        historyErased: true,
      );
      expect(result.outcome, isA<ServerDone>());
      expect(result.historyErased, isTrue);
      expect(sent, ['delete:me']);
    });

    test('a retry that finds the chat already gone is done', () async {
      final result = await run(
        ChatDeletionPlan.eraseForPeer,
        historyErased: true,
        delete: const ServerRejected('нет чата', notFound: true),
      );
      expect(result.outcome, isA<ServerDone>());
      expect(sent, ['delete:me']);
    });

    test('a removal for me alone that finds no chat is reported', () async {
      final result = await run(
        ChatDeletionPlan.forMe,
        delete: const ServerRejected('нет чата', notFound: true),
      );
      expect(result.outcome, isA<ServerRejected>());
    });

    test('a group removal sends one request for all members', () async {
      final result = await run(ChatDeletionPlan.removeForMembers);
      expect(result.historyErased, isFalse);
      expect(sent, ['delete:all']);
    });
  });
}
