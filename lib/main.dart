import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/notification_service.dart';
import 'services/permission_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  await NotificationService.schedulePeriodicCheck();
  await PermissionService.requestStoragePermission();
  runApp(const ProviderScope(child: NoteReviewApp()));
}
