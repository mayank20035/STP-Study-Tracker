import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

/// Rings the "target reached" alarm. Behind an interface so the store can be
/// tested without the notification plugin.
abstract class AlarmScheduler {
  /// Schedule the alarm to ring at [at] (replaces any earlier schedule).
  Future<void> schedule(DateTime at, {required String title, required String body});

  /// Cancel a scheduled alarm and silence one that is ringing.
  Future<void> cancel();

  /// Ring right now (used when the app itself notices the target first).
  Future<void> ringNow({required String title, required String body});

  /// Whether the alarm notification is currently showing / ringing.
  Future<bool> isRinging();

  /// Ask for notification / exact-alarm permissions if needed.
  Future<void> ensurePermissions();
}

class NoopAlarmScheduler implements AlarmScheduler {
  @override
  Future<void> schedule(DateTime at, {required String title, required String body}) async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<void> ringNow({required String title, required String body}) async {}
  @override
  Future<bool> isRinging() async => false;
  @override
  Future<void> ensurePermissions() async {}
}

/// Real implementation using an insistent, alarm-stream notification that
/// keeps ringing until the user presses Stop.
class NotificationAlarmScheduler implements AlarmScheduler {
  NotificationAlarmScheduler();

  static const int alarmId = 4242;
  static const String stopActionId = 'stop_alarm';
  static const String extendActionId = 'extend_alarm';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _askedPermissions = false;

  /// Called when the user taps the notification or one of its buttons.
  void Function(String? actionId)? onResponse;

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    if (!_supported || _ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_stp')),
      onDidReceiveNotificationResponse: (r) => onResponse?.call(r.actionId),
    );
    _ready = true;
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      // Let the UI settle, then report how the app was opened.
      Timer(const Duration(milliseconds: 500),
          () => onResponse?.call(launch!.notificationResponse?.actionId));
    }
  }

  NotificationDetails get _details => NotificationDetails(
        android: AndroidNotificationDetails(
          'stp_target_alarm_v1',
          'Target alarms',
          channelDescription: 'Rings when a To-Do book target is reached',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          sound: const RawResourceAndroidNotificationSound('alarm'),
          playSound: true,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 800, 400, 800, 400, 800]),
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          // FLAG_INSISTENT: repeat the sound until the notification is dismissed.
          additionalFlags: Int32List.fromList([4]),
          visibility: NotificationVisibility.public,
          actions: const [
            AndroidNotificationAction(stopActionId, '⏹ Stop', cancelNotification: true, showsUserInterface: true),
            AndroidNotificationAction(extendActionId, '+15 min', cancelNotification: true, showsUserInterface: true),
          ],
        ),
      );

  @override
  Future<void> ensurePermissions() async {
    if (!_supported || _askedPermissions) return;
    _askedPermissions = true;
    await init();
    try {
      await _android?.requestNotificationsPermission();
      await _android?.requestFullScreenIntentPermission();
    } catch (_) {}
  }

  @override
  Future<void> schedule(DateTime at, {required String title, required String body}) async {
    if (!_supported) return;
    await init();
    await _plugin.cancel(id: alarmId);
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    try {
      await _plugin.zonedSchedule(
        id: alarmId,
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        notificationDetails: _details,
        androidScheduleMode:
            exact ? AndroidScheduleMode.alarmClock : AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
      );
    } catch (e) {
      debugPrint('Alarm schedule failed: $e');
    }
  }

  @override
  Future<void> cancel() async {
    if (!_supported) return;
    await init();
    await _plugin.cancel(id: alarmId);
  }

  @override
  Future<void> ringNow({required String title, required String body}) async {
    if (!_supported) return;
    await init();
    if (await isRinging()) return;
    await _plugin.show(id: alarmId, title: title, body: body, notificationDetails: _details);
  }

  @override
  Future<bool> isRinging() async {
    if (!_supported) return false;
    await init();
    try {
      final active = await _android?.getActiveNotifications() ?? const [];
      return active.any((n) => n.id == alarmId);
    } catch (_) {
      return false;
    }
  }
}
