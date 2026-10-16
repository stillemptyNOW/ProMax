class ReadReceipt {
  const ReadReceipt({
    required this.userId,
    required this.prevMark,
    required this.mark,
    required this.readAt,
  });

  final int userId;
  final int prevMark;
  final int mark;
  final int readAt;

  bool covers(int messageTime) => prevMark < messageTime && messageTime <= mark;

  @override
  bool operator ==(Object other) =>
      other is ReadReceipt &&
      other.userId == userId &&
      other.prevMark == prevMark &&
      other.mark == mark &&
      other.readAt == readAt;

  @override
  int get hashCode => Object.hash(userId, prevMark, mark, readAt);

  @override
  String toString() => 'ReadReceipt($userId, $prevMark..$mark @ $readAt)';
}
