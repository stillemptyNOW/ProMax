import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:promax/core/config/promax_settings.dart';
import 'package:promax/core/storage/local_read_state.dart';
import 'package:promax/core/utils/names.dart';
import 'package:promax/models/contact_info.dart';
import 'package:promax/backend/modules/chats.dart';
import 'package:promax/frontend/screens/chats/chat_admin/members_pager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'profile names keep a surname when the legacy name is first name only',
    () {
      final info = ContactInfo.fromMap({
        'id': 101,
        'names': [
          {
            'type': 'ONEME',
            'name': 'Alice',
            'firstName': 'Alice',
            'lastName': 'Synthetic',
          },
        ],
      });
      expect(info.displayName, 'Alice Synthetic');
    },
  );

  test('a custom single-word name never acquires the profile surname', () {
    final name = contactNameForSave(
      firstName: ' Ally ',
      lastName: '',
      profileFirstName: 'Alice',
      profileLastName: 'Synthetic',
    );
    expect(name, (firstName: 'Ally', lastName: ''));
    final info = ContactInfo.fromMap({
      'names': [
        {'type': 'ONEME', 'firstName': 'Alice', 'lastName': 'Synthetic'},
        {
          'type': 'CUSTOM',
          'firstName': name.firstName,
          'lastName': name.lastName,
        },
      ],
    });
    expect(info.fullName, 'Ally');
  });

  test('an entirely cleared alias restores the complete profile name', () {
    expect(
      contactNameForSave(
        firstName: '',
        lastName: ' ',
        profileFirstName: 'Alice',
        profileLastName: 'Synthetic',
      ),
      (firstName: 'Alice', lastName: 'Synthetic'),
    );
  });

  test('locally viewed messages stay read after an older server snapshot', () {
    expect(
      localUnreadCount(
        serverUnread: 8,
        locallyRead: 8,
        localMark: 500,
        lastMessageTime: 500,
      ),
      0,
    );
    expect(
      localUnreadCount(
        serverUnread: 10,
        locallyRead: 8,
        localMark: 500,
        lastMessageTime: 600,
      ),
      2,
    );
    expect(
      localUnreadCount(
        serverUnread: 1,
        locallyRead: 8,
        localMark: 500,
        lastMessageTime: 600,
      ),
      0,
    );
  });

  test('the selected quick reaction survives a restart', () async {
    SharedPreferences.setMockInitialValues({});
    await ProMaxSettings.setQuickReaction('🔥');
    ProMaxSettings.quickReaction.value = '❤️';
    await ProMaxSettings.load();
    expect(ProMaxSettings.quickReaction.value, '🔥');
    expect(ProMaxSettings.recordDebugLogs.value, false);
    await ProMaxSettings.setQuickReaction('');
    expect(ProMaxSettings.quickReaction.value, '🔥');
  });

  test('a repeated member page does not conceal later members', () async {
    final requested = <int>[];
    final pager = MembersPager(
      chatId: -101,
      loadPage: (marker) async {
        requested.add(marker);
        return switch (marker) {
          0 => const ChatMembersPage(
            members: [
              ChatMemberEntry(
                id: 101,
                name: 'Alice Synthetic',
                presenceStatus: 0,
              ),
            ],
            marker: 50,
          ),
          50 => const ChatMembersPage(
            members: [
              ChatMemberEntry(
                id: 101,
                name: 'Alice Synthetic',
                presenceStatus: 0,
              ),
            ],
            marker: 100,
          ),
          _ => const ChatMembersPage(
            members: [
              ChatMemberEntry(
                id: 102,
                name: 'Bob Synthetic',
                presenceStatus: 0,
              ),
            ],
            marker: 100,
          ),
        };
      },
    );
    addTearDown(pager.dispose);
    await pager.loadMore();
    await pager.loadMore();
    expect(pager.end, false);
    await pager.loadMore();
    expect(pager.members.map((member) => member.id), [101, 102]);
    expect(requested, [0, 50, 100]);
  });
}
