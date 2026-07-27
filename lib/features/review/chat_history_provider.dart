import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/database/database.dart';
import '../settings/settings_provider.dart';

class ChatSession {
  final DateTime date;
  final List<ChatMessage> messages;

  ChatSession({required this.date, required this.messages});
}

final chatHistoryProvider = FutureProvider<List<ChatSession>>((ref) async {
  final db = ref.read(databaseProvider);
  final messages = await db.allMessages();

  final groups = <String, List<ChatMessage>>{};
  for (final msg in messages) {
    final key = DateFormat('yyyy-MM-dd').format(msg.createdAt);
    groups.putIfAbsent(key, () => []).add(msg);
  }

  final sessions = groups.entries.map((e) {
    final date = DateTime.parse(e.key);
    return ChatSession(date: date, messages: e.value);
  }).toList();

  sessions.sort((a, b) => b.date.compareTo(a.date));
  return sessions;
});
