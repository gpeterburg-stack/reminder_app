import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
  bool _isLoading = true;
  
  late FlutterLocalNotificationsPlugin _notificationsPlugin;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    _notificationsPlugin = FlutterLocalNotificationsPlugin();
    await _initializeNotifications();
    await _requestPermissions();
    await _loadMedications();
    await _loadAlarms();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _initializeNotifications() async {
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
    
    await _createNotificationChannel();
  }

  Future<void> _createNotificationChannel() async {
    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'medication_channel',
        'Напоминания о лекарствах',
        description: 'Уведомления о необходимости принять лекарство',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
        showBadge: true,
      );
      
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
              
      await androidImplementation?.createNotificationChannel(channel);
      debugPrint('Канал уведомлений создан');
    }
  }

  // ТЕСТОВОЕ УВЕДОМЛЕНИЕ - РАБОТАЕТ
  Future<void> _sendTestNotification() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'medication_channel',
      'Напоминания о лекарствах',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    
    await _notificationsPlugin.show(
      999,
      'Тестовое уведомление',
      'Если вы видите это - уведомления работают!',
      details,
    );
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      try {
        if (await Permission.notification.isDenied) {
          await Permission.notification.request();
        }
        
        if (await Permission.scheduleExactAlarm.isDenied) {
          await Permission.scheduleExactAlarm.request();
        }
        
        debugPrint('Разрешения проверены');
      } catch (e) {
        debugPrint('Ошибка запроса разрешений: $e');
      }
    }
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
            child: const Text('Принял(а)'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Напомнить позже'),
          ),
        ],
      ),
    );
  }

  // ОБЫЧНОЕ УВЕДОМЛЕНИЕ - ИСПОЛЬЗУЕТ ТОТ ЖЕ МЕТОД, ЧТО И ТЕСТОВОЕ
  Future<void> _scheduleNotification(Map<String, dynamic> alarm) async {
    if (!alarm['enabled']) return;
    
    final time = alarm['time'] as TimeOfDay;
    final days = alarm['days'] as List<int>;
    final medicationInfo = await _getMedicationInfoSafe(alarm);
    
    // ТЕ ЖЕ НАСТРОЙКИ, ЧТО И В ТЕСТОВОМ УВЕДОМЛЕНИИ
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'medication_channel',
      'Напоминания о лекарствах',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );
    
    final alarmId = alarm['id'].toString();
    final now = DateTime.now();
    
    // Для каждого выбранного дня недели
    for (int day in days) {
      // Вычисляем дату следующего приема
      DateTime scheduledDate = DateTime(
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      );
      
      int daysToAdd = day - now.weekday;
      if (daysToAdd < 0) {
        daysToAdd += 7;
      }
      if (daysToAdd == 0 && scheduledDate.isBefore(now)) {
        daysToAdd = 7;
      }
      
      scheduledDate = scheduledDate.add(Duration(days: daysToAdd));
      
      // Уникальный ID для каждого уведомления
      int notificationId = (alarmId.hashCode + day).abs() % 1000;
      
      // Используем ТОТ ЖЕ МЕТОД show, что и в тестовом уведомлении
      // Но с задержкой (schedule)
      final timeUntilNotification = scheduledDate.difference(now);
      
      if (timeUntilNotification.inSeconds > 0) {
        Future.delayed(timeUntilNotification, () async {
          await _notificationsPlugin.show(
            notificationId,
            'Время принять лекарство',
            medicationInfo,
            notificationDetails,
            payload: alarmId,
          );
          debugPrint('Уведомление отправлено для ${_getDayName(day)} в ${time.format(context)}');
        });
        
        debugPrint('Запланировано на ${_getDayName(day)} через ${timeUntilNotification.inHours}ч ${timeUntilNotification.inMinutes.remainder(60)}мин');
      }
    }
  }

  String _getDayName(int day) {
    const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return days[day - 1];
  }

  Future<String> _getMedicationInfoSafe(Map<String, dynamic> alarm) async {
    final medicationId = alarm['medicationId']?.toString() ?? '';
    final medicationName = alarm['medicationName']?.toString() ?? '';
    
    if (medicationId.isNotEmpty) {
      final medication = _medications.firstWhere(
        (med) => med['id'] == medicationId,
        orElse: () => {},
      );
      
      if (medication.isNotEmpty) {
        final name = medication['name']?.toString() ?? '';
        final dosage = medication['dosage']?.toString() ?? '';
        return 'Примите: $name • $dosage';
      }
    }
    
    final name = medicationName.isNotEmpty ? medicationName : 'Неизвестное лекарство';
    return 'Примите: $name';
  }

  Future<void> _scheduleAllNotifications() async {
    debugPrint('Планирование всех уведомлений...');
    
    for (var alarm in _alarms) {
      if (alarm['enabled']) {
        await _scheduleNotification(alarm);
      }
    }
    
    // Отправляем тестовое для проверки
    await _sendTestNotification();
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
          debugPrint('Загружено лекарств: ${_medications.length}');
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки лекарств: $e');
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
          
          setState(() {
            _alarms = jsonList.map((item) {
              final timeData = item['time'];
              int hour = 0;
              int minute = 0;
              
              if (timeData is Map) {
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
          
          debugPrint('Загружено напоминаний: ${_alarms.length}');
          await _scheduleAllNotifications();
        }
      }
    } catch (e) {
      debugPrint('Ошибка загрузки напоминаний: $e');
    }
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
      debugPrint('Напоминания сохранены');
    } catch (e) {
      debugPrint('Ошибка сохранения: $e');
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
    debugPrint('Добавление нового напоминания');
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
    debugPrint('Обновление напоминания: $id');
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
    setState(() {
      _alarms.removeWhere((alarm) => alarm['id'] == id);
    });
    await _saveAlarmsToFile();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🗑 Напоминание удалено'), duration: Duration(seconds: 2)),
      );
    }
  }

  void _toggleAlarm(String id, bool value) async {
    debugPrint('Переключение напоминания $id: ${value ? "Вкл" : "Выкл"}');
    setState(() {
      final index = _alarms.indexWhere((alarm) => alarm['id'] == id);
      if (index != -1) {
        _alarms[index]['enabled'] = value;
      }
    });
    
    await _saveAlarmsToFile();
    
    if (value) {
      final alarm = _alarms.firstWhere((alarm) => alarm['id'] == id);
      await _scheduleNotification(alarm);
    }
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
                          icon: const Icon(Icons.notifications_active),
                          onPressed: () async {
                            await _scheduleAllNotifications();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Уведомления перепланированы')),
                            );
                          },
                          tooltip: 'Перепланировать уведомления',
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
                                  elevation: 2,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: Icon(
                                      alarm['enabled'] ? Icons.notifications_active : Icons.notifications_off,
                                      size: 40,
                                      color: alarm['enabled'] ? Color.fromARGB(255, 117, 255, 170) : Colors.grey,
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
                                      activeColor: Color.fromARGB(255, 117, 255, 170),
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