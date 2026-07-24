import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import '../data/database/database.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == 'checkForOverdueReviews') {
      try {
        final dbFolder = await getApplicationDocumentsDirectory();
        final file = p.join(dbFolder.path, 'note_review.db');
        final db = AppDatabase.forTesting(NativeDatabase(File(file)));

        final lastCheck = await db.getLastCheckTime();
        final now = DateTime.now();

        final count = await db.overdueCount(lastCheck, now);

        if (count > 0) {
          const androidDetails = AndroidNotificationDetails(
            'review_channel',
            '复习提醒',
            channelDescription: '笔记复习提醒',
            importance: Importance.high,
            priority: Priority.high,
          );
          const details = NotificationDetails(android: androidDetails);
          const initializationSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
          const settings = InitializationSettings(android: initializationSettings);
          final notifications = FlutterLocalNotificationsPlugin();
          await notifications.initialize(settings);
          await notifications.show(
            0,
            '复习时间到',
            '你有 $count 篇笔记需要复习',
            details,
            payload: '/review',
          );
        }
        await db.close();
      } catch (_) {}
    }
    return true;
  });
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  static void _onNotificationTap(NotificationResponse response) {}

  static Future<void> showReviewNotification(int count) async {
    const androidDetails = AndroidNotificationDetails(
      'review_channel',
      '复习提醒',
      channelDescription: '笔记复习提醒',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notifications.show(
      0,
      '复习时间到',
      '你有 $count 篇笔记需要复习',
      details,
      payload: '/review',
    );
  }

  static Future<void> schedulePeriodicCheck() async {
    await Workmanager().registerPeriodicTask(
      'review_check',
      'checkForOverdueReviews',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.not_required,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }
}
