import 'package:flutter/material.dart';

import '../../../core/storage/app_database.dart';
import '../chats/chat_info_screen.dart';

class SelfProfilePreviewScreen extends StatelessWidget {
  const SelfProfilePreviewScreen({super.key, required this.profile});
  final ProfileData profile;

  @override
  Widget build(BuildContext context) => ChatInfoScreen(
    chatId: 0,
    name: '${profile.firstName} ${profile.lastName ?? ''}'.trim(),
    imageUrl: profile.baseUrl ?? '',
    chatType: 'DIALOG',
    dialogPeerId: profile.id,
    selfPreview: profile,
  );
}
