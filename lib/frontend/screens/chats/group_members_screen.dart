import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../contacts/open_contact_profile.dart';
import 'chat_admin/chat_admin_widgets.dart';
import 'chat_admin/members_list.dart';
import 'chat_admin/members_pager.dart';

class GroupMembersScreen extends StatefulWidget {
  final int chatId;

  const GroupMembersScreen({super.key, required this.chatId});

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  late final MembersPager _members = MembersPager(chatId: widget.chatId);

  @override
  void initState() {
    super.initState();
    _members.loadMore();
  }

  @override
  void dispose() {
    _members.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AdminScaffold(
      title: l10n.proMaxSearchMembers,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: MemberSearchField(
              onChanged: (value) => _members.query = value,
            ),
          ),
          Expanded(
            child: MembersList(
              controller: _members,
              emptyLabel: l10n.proMaxNoMembers,
              itemBuilder: (context, member) => AdminMemberTile(
                id: member.id,
                name: member.fullName ?? member.name,
                avatarUrl: member.avatarUrl,
                subtitle: memberPresenceLabel(l10n, member),
                onTap: () => openContactDialogProfile(
                  context,
                  contactId: member.id,
                  name: member.fullName ?? member.name ?? '${member.id}',
                  avatarUrl: member.avatarUrl,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
