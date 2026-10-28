import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications for the download queue.
///
/// * Android: ongoing notification with a real progress bar, kept alive by a
///   foreground service, with a "Parar" action.
/// * Windows: toast with a native progress bar that is updated in place.
/// * Linux: a single notification that is replaced as the queue advances.
/// * macOS: Dock badge with `done/total`; iOS and macOS get a notification
///   when the queue finishes (the system has no progress notifications).
///
/// Every call is best-effort: a notification problem never interrupts a
/// download.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _progressId = 1001;
  static const _doneId = 1002;
  static const _channelProgress = 'downloads_progress';
  static const _channelDone = 'downloads_done';
  static const _stopAction = 'stop_download';
  static const _dock = MethodChannel('dock_badge');
  static const _appName = 'Playlist MP3';
  static const _appId = 'com.example.youtube_playlist_mp3';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  VoidCallback? _onStop;
  ValueChanged<String?>? _onOpen;
  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool _foreground = false;

  bool get _supported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows ||
      Platform.isLinux;

  /// [onStop] is called when the user taps "Parar" in the notification.
  Future<void> init({
    VoidCallback? onStop,
    ValueChanged<String?>? onOpen,
  }) async {
    _onStop = onStop;
    _onOpen = onOpen;
    if (_ready || !_supported) return;
    try {
      await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('ic_stat_music'),
          iOS: const DarwinInitializationSettings(),
          macOS: const DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(
            defaultActionName: 'Abrir',
            defaultIcon: AssetsLinuxIcon('assets/icon/logo.png'),
          ),
          windows: const WindowsInitializationSettings(
            appName: _appName,
            appUserModelId: _appId,
            guid: '6f1d2c4e-8b7a-4c55-9d3e-2a9f0b1c7e41',
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          if (response.actionId == _stopAction) {
            _onStop?.call();
          } else {
            _onOpen?.call(response.payload);
          }
        },
      );
      _ready = true;
      await _requestPermission();
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        _onOpen?.call(response.payload);
      }
    } catch (e) {
      debugPrint('Notificações indisponíveis: $e');
    }
  }

  Future<void> _requestPermission() async {
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  // ----------------------------------------------------------------- queue

  /// Called when the queue starts.
  Future<void> start({required String playlist, required int total}) async {
    _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    await update(
      playlist: playlist,
      done: 0,
      total: total,
      current: null,
      currentFraction: 0,
      force: true,
    );
  }

  /// Updates the progress. Throttled, so it is safe to call very often.
  Future<void> update({
    required String playlist,
    required int done,
    required int total,
    required String? current,
    required double currentFraction,
    bool force = false,
  }) async {
    if (!_ready && !Platform.isMacOS) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastUpdate).inMilliseconds < 900) return;
    _lastUpdate = now;

    final overall = total == 0
        ? 0.0
        : ((done + currentFraction.clamp(0, 1)) / total).clamp(0.0, 1.0);
    final percent = (overall * 100).round();
    final title = 'A baixar · $playlist';
    final body = current == null
        ? '$done de $total concluídos'
        : '$done de $total · $current';

    try {
      if (Platform.isMacOS) {
        await _dock.invokeMethod('setBadge', '$done/$total');
      } else if (Platform.isAndroid) {
        final details = AndroidNotificationDetails(
          _channelProgress,
          'Progresso dos downloads',
          channelDescription: 'Mostra o progresso da playlist a ser baixada',
          icon: 'ic_stat_music',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: false,
          showProgress: true,
          maxProgress: 100,
          progress: percent,
          subText: '$percent%',
          category: AndroidNotificationCategory.progress,
          actions: const [AndroidNotificationAction(_stopAction, 'Parar')],
        );
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (!_foreground) {
          await android?.startForegroundService(
            id: _progressId,
            title: title,
            body: body,
            notificationDetails: details,
            foregroundServiceTypes: {
              AndroidServiceForegroundType.foregroundServiceTypeDataSync,
            },
          );
          _foreground = true;
        } else {
          await _plugin.show(
            id: _progressId,
            title: title,
            body: body,
            notificationDetails: NotificationDetails(android: details),
          );
        }
      } else if (Platform.isWindows) {
        final bar = WindowsProgressBar(
          id: 'queue',
          status: current ?? 'A preparar…',
          value: overall,
          title: '$done de $total',
          label: '$percent%',
        );
        if (!_foreground) {
          await _plugin.show(
            id: _progressId,
            title: title,
            body: body,
            notificationDetails: NotificationDetails(
              windows: WindowsNotificationDetails(progressBars: [bar]),
            ),
          );
          _foreground = true;
        } else {
          await _plugin
              .resolvePlatformSpecificImplementation<
                FlutterLocalNotificationsWindows
              >()
              ?.updateProgressBar(
                notificationId: _progressId,
                progressBar: bar,
              );
        }
      } else if (Platform.isLinux) {
        await _plugin.show(
          id: _progressId,
          title: title,
          body: '$body ($percent%)',
          notificationDetails: NotificationDetails(
            linux: LinuxNotificationDetails(
              urgency: LinuxNotificationUrgency.low,
              category: LinuxNotificationCategory.transfer,
              suppressSound: true,
              resident: true,
            ),
          ),
        );
      } else if (Platform.isIOS) {
        // iOS has no native progress bar for local notifications. Reusing the
        // same notification ID keeps one quiet, updating entry in Notification
        // Centre instead of spamming one notification per track.
        await _plugin.show(
          id: _progressId,
          title: title,
          body: '$body ($percent%)',
          notificationDetails: const NotificationDetails(
            iOS: DarwinNotificationDetails(
              presentAlert: false,
              presentBadge: true,
              presentSound: false,
            ),
          ),
        );
      }
      // iOS / macOS: the system has no progress notifications.
    } catch (e) {
      debugPrint('Falha ao atualizar a notificação: $e');
    }
  }

  /// Called when the queue ends (finished, stopped or failed).
  Future<void> finish({
    required String playlist,
    required int done,
    required int failed,
    required int total,
    required bool stopped,
    String? location,
    String? folderPath,
  }) async {
    try {
      if (Platform.isMacOS) {
        await _dock.invokeMethod('setBadge', failed > 0 ? '!' : '');
      }
      if (_foreground && Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.stopForegroundService();
      }
      _foreground = false;
      if (!_ready) return;
      await _plugin.cancel(id: _progressId);

      final complete = !stopped && done == total;
      final title = complete
          ? 'Playlist concluída'
          : stopped
          ? 'Download interrompido'
          : 'Download terminado com erros';
      final body = StringBuffer(
        complete
            ? '$total músicas guardadas'
            : '$done de $total músicas guardadas',
      );
      if (failed > 0) body.write(' · $failed com erro');
      if (location != null && location.isNotEmpty) body.write('\n$location');
      body.write('\n$playlist');

      await _plugin.show(
        id: _doneId,
        title: title,
        body: body.toString(),
        payload: jsonEncode({
          'folder': folderPath ?? location,
          'playlist': playlist,
        }),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelDone,
            'Downloads concluídos',
            channelDescription: 'Avisa quando uma playlist termina',
            icon: 'ic_stat_music',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body.toString()),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBanner: true,
            presentList: true,
          ),
          macOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
            presentBanner: true,
            presentList: true,
          ),
          linux: const LinuxNotificationDetails(
            category: LinuxNotificationCategory.transferComplete,
          ),
          windows: const WindowsNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('Falha ao mostrar a notificação final: $e');
    }
  }
}
