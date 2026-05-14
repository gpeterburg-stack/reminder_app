import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'create_reminder_page.dart';

class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key});

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  List<Map<String, dynamic>> _alarms = [];
  List<Map<String, dynamic>> _medications = [];
  Map<String, List<int>> _notificationIds = {};
  bool _isLoading = true;
  
  final FlutterLocalNotificationsPlugin _notificationsPlugin = 
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _initializeNotifications();
    await _loadNotificationIds();
    await _loadMedications();
    await _loadAlarms();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _initializeNotifications() async {
    tz.initializeTimeZones();
    
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    
    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        if (response.payload != null) {
          debugPrint('Нажато уведомление с ID: ${response.payload}');
          _showMedicationInfoDialog(response.payload!);
        }
      },
    );
    
    await _requestAndroidPermissions();
  }

  void _showMedicationInfoDialog(String alarmId) {
    final alarm = _alarms.firstWhere(
      (a) => a['id'] == alarmId,
      orElse: () => {},
    );
    
    if (alarm.isEmpty) return;
    
    final medicationInfo = _getMedicationInfo(
      alarm['medicationId']?.toString() ?? '',
      alarm['medicationName']?.toString() ?? '',
      alarm['medicationDosage']?.toString() ?? ''
    );
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Время принять лекарство'),
        content: Text(medicationInfo),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestAndroidPermissions() async {
    if (Platform.isAndroid) {
      try {
        if (await Permission.notification.isDenied) {
          await Permission.notification.request();
        }
        
        if (await Permission.scheduleExactAlarm.isDenied) {
          await Permission.scheduleExactAlarm.request();
        }
        
        if (await Permission.ignoreBatteryOptimizations.isDenied) {
          await Permission.ignoreBatteryOptimizations.request();
        }
        
        debugPrint('✅ Все разрешения получены');
      } catch (e) {
        debugPrint('❌ Ошибка запроса разрешений: $e');
      }
    }
  }

  Future<bool> _hasExactAlarmPermission() async {
    if (Platform.isAndroid) {
      if (await Permission.scheduleExactAlarm.isGranted) {
        return true;
      }
      
      if (await Permission.scheduleExactAlarm.request().isGranted) {
        return true;
      }
      
      if (await Permission.scheduleExactAlarm.shouldShowRequestRationale) {
        _showExactAlarmPermissionDialog();
      }
      
      return false;
    }
    return true;
  }

  void _showExactAlarmPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Точные напоминания'),
        content: const Text(
          'Для работы точных напоминаний о лекарствах необходимо разрешить приложению использовать точные будильники. '
          'Вы будете перенаправлены в настройки.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text('Открыть настройки'),
          ),
        ],
      ),
    );
  }

  Future<bool> _checkPermissions() async {
    if (Platform.isAndroid) {
      final notificationGranted = await Permission.notification.isGranted;
      final exactAlarmGranted = await Permission.scheduleExactAlarm.isGranted;
      
      if (!notificationGranted || !exactAlarmGranted) {
        await _requestAndroidPermissions();
        return await Permission.notification.isGranted;
      }
      return true;
    }
    return true;
  }

  Future<void> _scheduleNotification(Map<String, dynamic> alarm) async {
    if (!alarm['enabled']) return;
    
    final hasExactPermission = await _hasExactAlarmPermission();
    if (!hasExactPermission) {
      debugPrint('⚠️ Нет разрешения на точные будильники');
      return;
    }
    
    final hasPermissions = await _checkPermissions();
    if (!hasPermissions) {
      debugPrint('❌ Нет разрешений для уведомлений');
      return;
    }
    
    final time = alarm['time'] as TimeOfDay;
    final days = alarm['days'] as List<int>;
    final medicationInfo = await _getMedicationInfoSafe(alarm);
    
    await _cancelNotification(alarm['id']);
    
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'medication_reminders',
      'Напоминания о лекарствах',
      channelDescription: 'Уведомления о необходимости принять лекарство',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );
    
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );
    
    List<int> newNotificationIds = [];
    final alarmId = alarm['id'].toString();
    
    for (int day in days) {
      final now = DateTime.now();
      var scheduledDate = DateTime(
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      );
      
      int dayDifference = day - scheduledDate.weekday;
      if (dayDifference < 0) {
        dayDifference += 7;
      }
      scheduledDate = scheduledDate.add(Duration(days: dayDifference));
      
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 7));
      }
      
      int notificationId = (alarmId.hashCode + day).abs() % 1000000;
      if (notificationId == 0) notificationId = day + 1;
      
      try {
        await _notificationsPlugin.zonedSchedule(
          notificationId,
          'Время принять лекарство',
          medicationInfo,
          tz.TZDateTime.from(scheduledDate, tz.local),
          notificationDetails,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          payload: alarm['id'],
          androidAllowWhileIdle: true,
          matchDateTimeComponents: DateTimeComponents.time,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        newNotificationIds.add(notificationId);
        debugPrint('✅ Уведомление $notificationId запланировано на $scheduledDate для лекарства: $medicationInfo');
      } catch (e) {
        debugPrint('❌ Ошибка планирования для дня $day: $e');
      }
    }
    
    if (newNotificationIds.isNotEmpty) {
      _notificationIds[alarm['id']] = newNotificationIds;
      await _saveNotificationIds();
    }
  }

  Future<String> _getMedicationInfoSafe(Map<String, dynamic> alarm) async {
    final medicationId = alarm['medicationId']?.toString() ?? '';
    final medicationName = alarm['medicationName']?.toString() ?? '';
    final medicationDosage = alarm['medicationDosage']?.toString() ?? '';
    
    if (medicationId.isNotEmpty) {
      final medication = _medications.firstWhere(
        (med) => med['id'] == medicationId,
        orElse: () => {},
      );
      
      if (medication.isNotEmpty) {
        final name = medication['name']?.toString() ?? '';
        final dosage = medication['dosage']?.toString() ?? '';
        return '$name • $dosage';
      } else {
        debugPrint('⚠️ Лекарство с ID $medicationId не найдено в списке');
        if (medicationName.isNotEmpty) {
          return '$medicationName • $medicationDosage';
        }
      }
    }
    
    final name = medicationName.isNotEmpty ? medicationName : 'Неизвестное лекарство';
    final dosage = medicationDosage.isNotEmpty ? medicationDosage : '';
    return dosage.isNotEmpty ? '$name • $dosage' : name;
  }

  Future<void> _cancelNotification(String alarmId) async {
    try {
      List<int>? ids = _notificationIds[alarmId];
      
      if (ids != null && ids.isNotEmpty) {
        for (int id in ids) {
          await _notificationsPlugin.cancel(id);
          debugPrint('🗑 Отменено уведомление с ID: $id');
        }
        _notificationIds.remove(alarmId);
        await _saveNotificationIds();
      } else {
        final alarmIdInt = alarmId.hashCode;
        for (int day = 1; day <= 7; day++) {
          int possibleId = (alarmIdInt + day).abs() % 1000000;
          if (possibleId == 0) possibleId = day;
          await _notificationsPlugin.cancel(possibleId);
        }
        debugPrint('🗑 Отменены возможные уведомления для $alarmId');
      }
    } catch (e) {
      debugPrint('❌ Ошибка отмены уведомлений для $alarmId: $e');
    }
  }

  Future<void> _saveNotificationIds() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/notification_ids.json');
      Map<String, List<int>> idsToSave = {};
      _notificationIds.forEach((key, value) {
        idsToSave[key] = List<int>.from(value);
      });
      await file.writeAsString(jsonEncode(idsToSave));
    } catch (e) {
      debugPrint('❌ Ошибка сохранения ID уведомлений: $e');
    }
  }

  Future<void> _loadNotificationIds() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/notification_ids.json');
      
      if (await file.exists()) {
        final contents = await file.readAsString();
        if (contents.isNotEmpty) {
          final Map<String, dynamic> decoded = jsonDecode(contents);
          _notificationIds = decoded.map((key, value) => 
            MapEntry(key, List<int>.from(value))
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Ошибка загрузки ID уведомлений: $e');
    }
  }

  Future<void> _scheduleAllNotifications() async {
    debugPrint('🔄 Планирование всех уведомлений...');
    int scheduledCount = 0;
    
    for (var alarm in _alarms) {
      if (alarm['enabled']) {
        final medicationId = alarm['medicationId']?.toString() ?? '';
        if (medicationId.isNotEmpty) {
          final medicationExists = _medications.any((med) => med['id'] == medicationId);
          if (!medicationExists) {
            debugPrint('⚠️ Пропуск напоминания: лекарство с ID $medicationId не найдено');
            continue;
          }
        }
        
        await _scheduleNotification(alarm);
        scheduledCount++;
      }
    }
    
    debugPrint('✅ Запланировано уведомлений: $scheduledCount');
    await _checkPendingNotifications();
  }

  Future<void> _checkPendingNotifications() async {
    final pending = await _notificationsPlugin.pendingNotificationRequests();
    debugPrint('📋 Всего ожидающих уведомлений: ${pending.length}');
  }

  Future<void> _clearAllNotifications() async {
    await _notificationsPlugin.cancelAll();
    _notificationIds.clear();
    await _saveNotificationIds();
    debugPrint('🗑 Все уведомления очищены');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Все уведомления очищены')),
      );
    }
  }

  Future<void> _loadMedications() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/medications.json');
      
      if (await file.exists()) {
        final contents = await file.readAsString();
        
        if (contents.isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(contents);
          setState(() {
            _medications = jsonList.map((item) {
              return {
                'id': item['id'] ?? '',
                'name': item['name'] ?? '',
                'dosage': item['dosage'] ?? '',
              };
            }).toList();
          });
          debugPrint('📦 Загружено лекарств: ${_medications.length}');
        }
      }
    } catch (e) {
      debugPrint('❌ Ошибка при загрузке лекарств: $e');
    }
  }

  Future<void> _loadAlarms() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/alarms.json');
      
      if (await file.exists()) {
        final contents = await file.readAsString();
        
        if (contents.isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(contents);
          
          final validAlarms = jsonList.where((item) {
            final medicationId = item['medicationId']?.toString() ?? '';
            if (medicationId.isEmpty) return true;
            return _medications.any((med) => med['id'] == medicationId);
          }).toList();
          
          if (validAlarms.length != jsonList.length) {
            debugPrint('⚠️ Удалено ${jsonList.length - validAlarms.length} невалидных напоминаний');
          }
          
          setState(() {
            _alarms = validAlarms.map((item) {
              final timeData = item['time'];
              int hour = 0;
              int minute = 0;
              
              if (timeData != null) {
                hour = timeData['hour'] ?? 0;
                minute = timeData['minute'] ?? 0;
              }
              
              return {
                'id': item['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
                'time': TimeOfDay(hour: hour, minute: minute),
                'days': item['days'] != null ? List<int>.from(item['days']) : [],
                'medicationId': item['medicationId']?.toString() ?? '',
                'medicationName': item['medicationName']?.toString() ?? '',
                'medicationDosage': item['medicationDosage']?.toString() ?? '',
                'enabled': item['enabled'] ?? true,
              };
            }).toList();
          });
          
          if (validAlarms.length != jsonList.length) {
            await _saveAlarmsToFile();
          }
          
          debugPrint('⏰ Загружено напоминаний: ${_alarms.length}');
          await _scheduleAllNotifications();
        } else {
          _addTestAlarms();
        }
      } else {
        _addTestAlarms();
      }
    } catch (e) {
      debugPrint('❌ Ошибка при загрузке напоминаний: $e');
      _addTestAlarms();
    }
  }

  void _addTestAlarms() {
    debugPrint('➕ Добавление тестовых напоминаний');
    setState(() {
      _alarms = [
        {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'time': const TimeOfDay(hour: 7, minute: 30),
          'days': [1, 2, 3, 4, 5],
          'medicationId': '',
          'medicationName': 'Аспирин',
          'medicationDosage': '1 таблетка',
          'enabled': true,
        },
        {
          'id': (DateTime.now().millisecondsSinceEpoch + 1).toString(),
          'time': const TimeOfDay(hour: 9, minute: 0),
          'days': [1, 3, 5],
          'medicationId': '',
          'medicationName': 'Парацетамол',
          'medicationDosage': '3 таблетки',
          'enabled': true,
        },
        {
          'id': (DateTime.now().millisecondsSinceEpoch + 2).toString(),
          'time': const TimeOfDay(hour: 22, minute: 0),
          'days': [1, 2, 3, 4, 5, 6, 7],
          'medicationId': '',
          'medicationName': 'Витамин D',
          'medicationDosage': '1 капсула',
          'enabled': false,
        },
      ];
    });
    
    _saveAlarmsToFile();
    _scheduleAllNotifications();
  }

  Future<void> _saveAlarmsToFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/alarms.json');
      
      final List<Map<String, dynamic>> jsonList = _alarms.map((alarm) {
        return {
          'id': alarm['id'],
          'time': {
            'hour': alarm['time'].hour,
            'minute': alarm['time'].minute,
          },
          'days': alarm['days'],
          'medicationId': alarm['medicationId'] ?? '',
          'medicationName': alarm['medicationName'] ?? '',
          'medicationDosage': alarm['medicationDosage'] ?? '',
          'enabled': alarm['enabled'] ?? true,
        };
      }).toList();
      
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      debugPrint('❌ Ошибка при сохранении напоминания: $e');
    }
  }

  String _getMedicationInfo(String medicationId, String medicationName, String medicationDosage) {
    if (medicationId.isNotEmpty) {
      final medication = _medications.firstWhere(
        (med) => med['id'] == medicationId,
        orElse: () => {},
      );
      
      if (medication.isNotEmpty) {
        final name = medication['name']?.toString() ?? '';
        final dosage = medication['dosage']?.toString() ?? '';
        return '$name • $dosage';
      }
    }
    
    final name = medicationName.isNotEmpty ? medicationName : 'Неизвестное лекарство';
    final dosage = medicationDosage.isNotEmpty ? medicationDosage : '';
    return dosage.isNotEmpty ? '$name • $dosage' : name;
  }

  String _formatDays(List<int> days) {
    if (days.isEmpty) return 'Не выбрано';
    if (days.length == 7) return 'Ежедневно';
    
    final dayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    if (days.length == 5 && days.every((d) => d >= 1 && d <= 5)) {
      return 'Пн-Пт';
    }
    if (days.length == 2 && days.contains(6) && days.contains(7)) {
      return 'Сб-Вс';
    }
    
    return days.map((d) => dayNames[d - 1]).join(', ');
  }

  void _addAlarm(Map<String, dynamic> alarm) async {
    debugPrint('➕ Добавление нового напоминания');
    setState(() {
      _alarms.add(alarm);
    });
    await _saveAlarmsToFile();
    await _scheduleNotification(alarm);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Напоминание добавлено'), duration: Duration(seconds: 2)),
      );
    }
  }

  void _updateAlarm(String id, Map<String, dynamic> updatedAlarm) async {
    debugPrint('✏️ Обновление напоминания: $id');
    setState(() {
      final index = _alarms.indexWhere((alarm) => alarm['id'] == id);
      if (index != -1) {
        _alarms[index] = updatedAlarm;
      }
    });
    await _saveAlarmsToFile();
    await _scheduleNotification(updatedAlarm);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Напоминание обновлено'), duration: Duration(seconds: 2)),
      );
    }
  }

  void _deleteAlarm(String id) async {
    debugPrint('🗑 Удаление напоминания: $id');
    await _cancelNotification(id);
    
    setState(() {
      _alarms.removeWhere((alarm) => alarm['id'] == id);
    });
    await _saveAlarmsToFile();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Напоминание удалено'), duration: Duration(seconds: 2)),
      );
    }
  }

  void _toggleAlarm(String id, bool value) async {
    debugPrint('🔄 Переключение напоминания $id: ${value ? "Вкл" : "Выкл"}');
    setState(() {
      final index = _alarms.indexWhere((alarm) => alarm['id'] == id);
      if (index != -1) {
        _alarms[index]['enabled'] = value;
      }
    });
    
    if (value) {
      final alarm = _alarms.firstWhere((alarm) => alarm['id'] == id);
      await _scheduleNotification(alarm);
    } else {
      await _cancelNotification(id);
    }
    
    await _saveAlarmsToFile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Text(
                          'Напоминания',
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () async {
                            await _scheduleAllNotifications();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Уведомления перепланированы')),
                              );
                            }
                          },
                          tooltip: 'Перепланировать уведомления',
                        ),
                        IconButton(
                          icon: const Icon(Icons.clear_all),
                          onPressed: _clearAllNotifications,
                          tooltip: 'Очистить все уведомления',
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _alarms.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.alarm_off, size: 100, color: Color.fromARGB(255, 117, 255, 170)),
                                const SizedBox(height: 20),
                                const Text('Нет напоминаний', style: TextStyle(fontSize: 24)),
                                const SizedBox(height: 10),
                                const Text('Нажмите + чтобы создать напоминание', style: TextStyle(fontSize: 16, color: Colors.grey)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _alarms.length,
                            itemBuilder: (context, index) {
                              final alarm = _alarms[index];
                              return Dismissible(
                                key: Key(alarm['id']),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  color: Colors.red,
                                  child: const Icon(Icons.delete, color: Colors.white),
                                ),
                                onDismissed: (direction) => _deleteAlarm(alarm['id']),
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: Icon(
                                      Icons.alarm,
                                      size: 40,
                                      color: alarm['enabled'] ? Colors.green : Colors.grey,
                                    ),
                                    title: Row(
                                      children: [
                                        Text(
                                          '${alarm['time'].hour.toString().padLeft(2, '0')}:${alarm['time'].minute.toString().padLeft(2, '0')}',
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: alarm['enabled'] ? Colors.black : Colors.grey,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _getMedicationInfo(
                                              alarm['medicationId']?.toString() ?? '',
                                              alarm['medicationName']?.toString() ?? '',
                                              alarm['medicationDosage']?.toString() ?? ''
                                            ),
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: alarm['enabled'] ? Colors.black87 : Colors.grey,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      _formatDays(alarm['days'] ?? []),
                                      style: TextStyle(color: alarm['enabled'] ? Colors.black54 : Colors.grey),
                                    ),
                                    trailing: Switch(
                                      value: alarm['enabled'] ?? true,
                                      onChanged: (value) => _toggleAlarm(alarm['id'], value),
                                      activeColor: Colors.green,
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => CreateReminderPage(
                                            alarm: alarm,
                                            medications: _medications,
                                            onSave: (updatedAlarm) => _updateAlarm(alarm['id'], updatedAlarm),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateReminderPage(
                medications: _medications,
                onSave: _addAlarm,
              ),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}