import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'create_course_page.dart';
import 'medications_page.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class MedicationCourse {
  final String id;
  final String medicationId;
  final String medicationName;
  final String dosage;
  final DateTime startDate;
  final DateTime? endDate;
  final CourseDurationType durationType;
  final int? durationValue;
  final List<TimeOfDay> reminderTimes;
  final bool isActive;
  final DateTime? completedAt;

  MedicationCourse({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    required this.dosage,
    required this.startDate,
    this.endDate,
    required this.durationType,
    this.durationValue,
    required this.reminderTimes,
    required this.isActive,
    this.completedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'medicationId': medicationId,
      'medicationName': medicationName,
      'dosage': dosage,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'durationType': durationType.toString(),
      'durationValue': durationValue,
      'reminderTimes': reminderTimes.map((t) => '${t.hour}:${t.minute}').toList(),
      'isActive': isActive,
      'completedAt': completedAt?.toIso8601String(),
    };
  }

  factory MedicationCourse.fromJson(Map<String, dynamic> json) {
    List<TimeOfDay> times = [];
    if (json['reminderTimes'] != null) {
      times = (json['reminderTimes'] as List).map((t) {
        final parts = t.split(':');
        return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }).toList();
    }

    return MedicationCourse(
      id: json['id'],
      medicationId: json['medicationId'],
      medicationName: json['medicationName'],
      dosage: json['dosage'],
      startDate: DateTime.parse(json['startDate']),
      endDate: json['endDate'] != null ? DateTime.parse(json['endDate']) : null,
      durationType: CourseDurationType.values.firstWhere(
        (e) => e.toString() == json['durationType'],
        orElse: () => CourseDurationType.unlimited,
      ),
      durationValue: json['durationValue'],
      reminderTimes: times,
      isActive: json['isActive'],
      completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt']) : null,
    );
  }

  bool get isExpired {
    if (!isActive) return true;
    if (endDate != null) {
      return DateTime.now().isAfter(endDate!);
    }
    return false;
  }
}

enum CourseDurationType {
  unlimited,
  days,
  weeks,
  months,
  years,
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with SingleTickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _diseaseController = TextEditingController();
  
  String _profileName = '';
  String _age = '';
  String _weight = '';
  List<String> _chronicDiseases = [];
  bool _isEditing = false;
  bool _hasProfile = false;
  
  List<MedicationCourse> _activeCourses = [];
  List<MedicationCourse> _completedCourses = [];
  late TabController _tabController;
  
  File? _profileFile;
  File? _coursesFile;
  
  // Хранилище для запланированных таймеров
  List<Timer> _scheduledTimers = [];
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initNotifications();
    _loadProfile();
    _loadCourses();
  }
  
  @override
  void dispose() {
    // Отменяем все таймеры при закрытии
    for (var timer in _scheduledTimers) {
      timer.cancel();
    }
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _diseaseController.dispose();
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _initNotifications() async {
    // Настройка для Android
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
    
    // Создаем канал для уведомлений (Android 8+)
    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'medication_channel',
        'Напоминания о лекарствах',
        description: 'Канал для напоминаний о приеме лекарств',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      );
      
      final androidPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(channel);
    }
  }
  
  // Простой метод для отправки уведомления
  Future<void> _showNotification(String title, String body, int id) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'medication_channel',
      'Напоминания о лекарствах',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );
    
    const DarwinNotificationDetails iOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );
    
    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      details,
    );
    
    debugPrint('🔔 Уведомление отправлено: $title');
  }
  
  // Планирование уведомлений с помощью Timer
  void _scheduleReminders(MedicationCourse course) {
    if (!course.isActive || course.isExpired) return;
    
    final now = DateTime.now();
    final endDate = course.endDate;
    
    debugPrint('📢 Планирование уведомлений для: ${course.medicationName}');
    
    for (var time in course.reminderTimes) {
      // Вычисляем следующее время приема
      DateTime nextTime = DateTime(
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      );
      
      // Если время уже прошло сегодня, планируем на завтра
      if (nextTime.isBefore(now)) {
        nextTime = nextTime.add(const Duration(days: 1));
      }
      
      // Проверяем, не выходит ли за дату окончания
      if (endDate != null && nextTime.isAfter(endDate)) {
        continue;
      }
      
      final notificationId = (course.id.hashCode + time.hour * 60 + time.minute).abs() % 100000;
      
      // Создаем таймер для первого уведомления
      final delay = nextTime.difference(now);
      if (delay.inSeconds > 0) {
        Timer(delay, () {
          _showNotification(
            'Время принять лекарство 💊',
            '${course.medicationName} - ${course.dosage}',
            notificationId,
          );
          
          // После отправки планируем следующее на завтра
          _scheduleDailyReminder(course, time, notificationId);
        });
        
        _scheduledTimers.add(Timer(delay, () {}));
        debugPrint('⏰ Запланировано на ${nextTime.hour}:${nextTime.minute} (через ${delay.inHours}ч ${delay.inMinutes.remainder(60)}мин)');
      }
    }
  }
  
  // Планирование ежедневных напоминаний
  void _scheduleDailyReminder(MedicationCourse course, TimeOfDay time, int baseId) {
    if (!course.isActive || course.isExpired) return;
    
    final now = DateTime.now();
    final endDate = course.endDate;
    
    // Планируем на завтра
    DateTime tomorrow = DateTime(
      now.year,
      now.month,
      now.day + 1,
      time.hour,
      time.minute,
    );
    
    // Проверяем дату окончания
    if (endDate != null && tomorrow.isAfter(endDate)) {
      debugPrint('❌ Курс закончился, уведомления отменены');
      return;
    }
    
    final delay = tomorrow.difference(now);
    if (delay.inSeconds > 0) {
      Timer(delay, () {
        _showNotification(
          'Время принять лекарство 💊',
          '${course.medicationName} - ${course.dosage}',
          baseId,
        );
        
        // Рекурсивно планируем следующий день
        _scheduleDailyReminder(course, time, baseId);
      });
      
      debugPrint('🔄 Запланировано повторение на завтра в ${time.hour}:${time.minute}');
    }
  }
  
  void _rescheduleAllReminders() {
    // Отменяем все существующие таймеры
    for (var timer in _scheduledTimers) {
      timer.cancel();
    }
    _scheduledTimers.clear();
    
    // Планируем новые для всех активных курсов
    for (var course in _activeCourses) {
      if (course.isActive && !course.isExpired) {
        _scheduleReminders(course);
      }
    }
    
    // Показываем тестовое уведомление
    _showNotification(
      '✅ Напоминания активированы',
      'Все напоминания о лекарствах настроены',
      999999,
    );
    
    debugPrint('✅ Все уведомления перепланированы');
  }
  
  Future<void> _cancelAllReminders() async {
    for (var timer in _scheduledTimers) {
      timer.cancel();
    }
    _scheduledTimers.clear();
    await flutterLocalNotificationsPlugin.cancelAll();
    debugPrint('❌ Все уведомления отменены');
  }
  
  Future<void> _getProfileFile() async {
    final directory = await getApplicationDocumentsDirectory();
    _profileFile = File('${directory.path}/profile.json');
    _coursesFile = File('${directory.path}/medication_courses.json');
  }
  
  Future<void> _loadProfile() async {
    await _getProfileFile();
    
    if (_profileFile != null && await _profileFile!.exists()) {
      try {
        final String data = await _profileFile!.readAsString();
        final Map<String, dynamic> jsonData = json.decode(data);
        
        setState(() {
          _profileName = jsonData['name'] ?? '';
          _age = jsonData['age'] ?? '';
          _weight = jsonData['weight'] ?? '';
          _chronicDiseases = List<String>.from(jsonData['chronicDiseases'] ?? []);
          _hasProfile = true;
          _isEditing = false;
        });
      } catch (e) {
        print('Ошибка загрузки профиля: $e');
      }
    } else {
      setState(() {
        _hasProfile = false;
        _isEditing = true;
      });
    }
  }
  
  Future<void> _loadCourses() async {
    await _getProfileFile();
    
    if (_coursesFile != null && await _coursesFile!.exists()) {
      try {
        final String data = await _coursesFile!.readAsString();
        if (data.isNotEmpty) {
          final List<dynamic> jsonData = json.decode(data);
          final allCourses = jsonData.map((item) => MedicationCourse.fromJson(item)).toList();
          
          List<MedicationCourse> updatedCourses = [];
          for (var course in allCourses) {
            if (course.isActive && course.isExpired) {
              final updatedCourse = MedicationCourse(
                id: course.id,
                medicationId: course.medicationId,
                medicationName: course.medicationName,
                dosage: course.dosage,
                startDate: course.startDate,
                endDate: course.endDate,
                durationType: course.durationType,
                durationValue: course.durationValue,
                reminderTimes: course.reminderTimes,
                isActive: false,
                completedAt: DateTime.now(),
              );
              updatedCourses.add(updatedCourse);
            } else {
              updatedCourses.add(course);
            }
          }
          
          setState(() {
            _activeCourses = updatedCourses.where((c) => c.isActive && !c.isExpired).toList();
            _completedCourses = updatedCourses.where((c) => !c.isActive || c.isExpired).toList();
          });
          
          // Планируем уведомления после загрузки
          _rescheduleAllReminders();
          await _saveCourses();
        }
      } catch (e) {
        print('Ошибка загрузки курсов: $e');
      }
    }
  }
  
  Future<void> _saveProfile() async {
    if (_nameController.text.isEmpty) {
      _showSnackBar('Пожалуйста, введите имя');
      return;
    }
    
    if (_ageController.text.isEmpty) {
      _showSnackBar('Пожалуйста, введите возраст');
      return;
    }
    
    if (_weightController.text.isEmpty) {
      _showSnackBar('Пожалуйста, введите вес');
      return;
    }
    
    final Map<String, dynamic> profileData = {
      'name': _nameController.text,
      'age': _ageController.text,
      'weight': _weightController.text,
      'chronicDiseases': _chronicDiseases,
    };
    
    try {
      await _getProfileFile();
      await _profileFile!.writeAsString(json.encode(profileData));
      
      setState(() {
        _profileName = _nameController.text;
        _age = _ageController.text;
        _weight = _weightController.text;
        _hasProfile = true;
        _isEditing = false;
      });
      
      _showSnackBar('Профиль успешно сохранен');
    } catch (e) {
      _showSnackBar('Ошибка сохранения профиля: $e');
    }
  }
  
  Future<void> _saveCourses() async {
    try {
      final allCourses = [..._activeCourses, ..._completedCourses];
      final jsonList = allCourses.map((c) => c.toJson()).toList();
      await _coursesFile!.writeAsString(json.encode(jsonList));
    } catch (e) {
      print('Ошибка сохранения курсов: $e');
    }
  }
  
  void _addChronicDisease() {
    if (_diseaseController.text.isNotEmpty) {
      setState(() {
        _chronicDiseases.add(_diseaseController.text);
        _diseaseController.clear();
      });
    } else {
      _showSnackBar('Введите название заболевания');
    }
  }
  
  void _removeChronicDisease(int index) {
    setState(() {
      _chronicDiseases.removeAt(index);
    });
    _showSnackBar('Заболевание удалено');
  }
  
  void _editProfile() {
    _nameController.text = _profileName;
    _ageController.text = _age;
    _weightController.text = _weight;
    
    setState(() {
      _isEditing = true;
    });
  }
  
  void _cancelEditing() {
    if (!_hasProfile) {
      setState(() {
        _isEditing = true;
      });
    } else {
      setState(() {
        _isEditing = false;
      });
    }
    _clearControllers();
  }
  
  void _clearControllers() {
    _nameController.clear();
    _ageController.clear();
    _weightController.clear();
    _diseaseController.clear();
  }
  
  Future<void> _deleteProfile() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление профиля'),
        content: const Text('Вы уверены, что хотите удалить профиль? Все данные будут потеряны.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              await _cancelAllReminders();
              
              if (_profileFile != null && await _profileFile!.exists()) {
                await _profileFile!.delete();
              }
              if (_coursesFile != null && await _coursesFile!.exists()) {
                await _coursesFile!.delete();
              }
              setState(() {
                _profileName = '';
                _age = '';
                _weight = '';
                _chronicDiseases = [];
                _hasProfile = false;
                _isEditing = true;
                _activeCourses = [];
                _completedCourses = [];
              });
              _clearControllers();
              Navigator.pop(context);
              _showSnackBar('Профиль удален');
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
  
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _addCourse() async {
    final medicationsFile = File('${(await getApplicationDocumentsDirectory()).path}/medications.json');
    List<Medication> medications = [];
    
    if (await medicationsFile.exists()) {
      final contents = await medicationsFile.readAsString();
      if (contents.isNotEmpty) {
        final List<dynamic> jsonList = json.decode(contents);
        medications = jsonList.map((item) => Medication.fromJson(item)).toList();
      }
    }
    
    if (medications.isEmpty) {
      _showSnackBar('Сначала добавьте лекарства в разделе "Лекарства"');
      return;
    }
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateCoursePage(medications: medications),
      ),
    );
    
    if (result != null && result is MedicationCourse) {
      setState(() {
        _activeCourses.add(result);
      });
      await _saveCourses();
      _scheduleReminders(result);
      _showSnackBar('Курс лечения добавлен. Установлены напоминания!');
    }
  }
  
  Future<void> _editCourse(MedicationCourse course) async {
    final medicationsFile = File('${(await getApplicationDocumentsDirectory()).path}/medications.json');
    List<Medication> medications = [];
    
    if (await medicationsFile.exists()) {
      final contents = await medicationsFile.readAsString();
      if (contents.isNotEmpty) {
        final List<dynamic> jsonList = json.decode(contents);
        medications = jsonList.map((item) => Medication.fromJson(item)).toList();
      }
    }
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateCoursePage(
          medications: medications,
          editingCourse: course,
        ),
      ),
    );
    
    if (result != null && result is MedicationCourse) {
      setState(() {
        final index = _activeCourses.indexWhere((c) => c.id == course.id);
        if (index != -1) {
          _activeCourses[index] = result;
        }
      });
      await _saveCourses();
      _rescheduleAllReminders();
      _showSnackBar('Курс лечения обновлен');
    }
  }
  
  Future<void> _completeCourse(MedicationCourse course) async {
    setState(() {
      _activeCourses.remove(course);
      final completedCourse = MedicationCourse(
        id: course.id,
        medicationId: course.medicationId,
        medicationName: course.medicationName,
        dosage: course.dosage,
        startDate: course.startDate,
        endDate: course.endDate,
        durationType: course.durationType,
        durationValue: course.durationValue,
        reminderTimes: course.reminderTimes,
        isActive: false,
        completedAt: DateTime.now(),
      );
      _completedCourses.add(completedCourse);
    });
    await _saveCourses();
    _rescheduleAllReminders();
    _showSnackBar('Курс завершен. Напоминания отключены.');
  }
  
  Future<void> _deleteCourse(MedicationCourse course) async {
    setState(() {
      _completedCourses.remove(course);
    });
    await _saveCourses();
    _showSnackBar('Курс удален из истории');
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мой профиль'),
        backgroundColor: const Color.fromARGB(255, 117, 255, 170),
        foregroundColor: Colors.black,
        actions: [
          if (_hasProfile && !_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _editProfile,
              tooltip: 'Редактировать профиль',
            ),
          if (_hasProfile && !_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteProfile,
              tooltip: 'Удалить профиль',
            ),
        ],
      ),
      body: _isEditing ? _buildEditForm() : _buildMainView(),
    );
  }
  
  Widget _buildMainView() {
    if (!_hasProfile) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.person_outline,
              size: 80,
              color: Color.fromARGB(255, 117, 255, 170),
            ),
            const SizedBox(height: 20),
            const Text(
              'Профиль не создан',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            const Text(
              'Создайте профиль, чтобы начать',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 117, 255, 170),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Создать профиль',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _profileName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 117, 255, 170).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Активен',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildInfoChip(Icons.cake, '$_age лет'),
                  const SizedBox(width: 16),
                  _buildInfoChip(Icons.fitness_center, '$_weight кг'),
                ],
              ),
              if (_chronicDiseases.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _chronicDiseases.map((disease) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.medical_services, size: 16, color: Colors.orange.shade700),
                          const SizedBox(width: 6),
                          Text(
                            disease,
                            style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
        
        TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color.fromARGB(255, 117, 255, 170),
          tabs: const [
            Tab(text: 'Активные курсы'),
            Tab(text: 'История'),
          ],
        ),
        
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildActiveCoursesTab(),
              _buildHistoryTab(),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildInfoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
      ],
    );
  }
  
  Widget _buildActiveCoursesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Текущие курсы лечения',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: _addCourse,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 117, 255, 170),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add, color: Colors.black),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _activeCourses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.medication_liquid,
                        size: 80,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Нет активных курсов',
                        style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Нажмите + чтобы добавить курс',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _activeCourses.length,
                  itemBuilder: (context, index) {
                    final course = _activeCourses[index];
                    return _buildCourseCard(course, isActive: true);
                  },
                ),
        ),
      ],
    );
  }
  
  Widget _buildHistoryTab() {
    return _completedCourses.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history,
                  size: 80,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  'История пуста',
                  style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Завершенные курсы появятся здесь',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _completedCourses.length,
            itemBuilder: (context, index) {
              final course = _completedCourses[index];
              return _buildCourseCard(course, isActive: false);
            },
          );
  }
  
  Widget _buildCourseCard(MedicationCourse course, {required bool isActive}) {
    final daysLeft = course.endDate != null 
        ? course.endDate!.difference(DateTime.now()).inDays 
        : null;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 117, 255, 170).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.medication,
                    color: isActive 
                        ? const Color.fromARGB(255, 117, 255, 170)
                        : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.medicationName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isActive ? Colors.black : Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        course.dosage,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isActive && daysLeft != null && daysLeft > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: daysLeft <= 3 ? Colors.orange.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$daysLeft дн.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: daysLeft <= 3 ? Colors.orange.shade700 : Colors.green.shade700,
                      ),
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  'Начало: ${_formatDate(course.startDate)}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
            
            if (course.endDate != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.event, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Text(
                    'Окончание: ${_formatDate(course.endDate!)}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
            
            if (course.reminderTimes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: course.reminderTimes.map((time) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time, size: 14, color: Colors.blue.shade700),
                        const SizedBox(width: 4),
                        Text(
                          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.notifications_active, size: 12, color: Colors.blue.shade700),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
            
            if (isActive) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _editCourse(course),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Редактировать'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _completeCourse(course),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Завершить'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ],
            
            if (!isActive && course.completedAt != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.green.shade600),
                  const SizedBox(width: 8),
                  Text(
                    'Завершен: ${_formatDate(course.completedAt!)}',
                    style: TextStyle(fontSize: 13, color: Colors.green.shade600),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => _deleteCourse(course),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: Colors.red.shade400,
                    tooltip: 'Удалить из истории',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
    
  Widget _buildEditForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Icon(
              Icons.person_add,
              size: 80,
              color: Color.fromARGB(255, 117, 255, 170),
            ),
          ),
          
          const SizedBox(height: 30),
          
          const Text(
            'Основная информация',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Имя *',
              hintText: 'Введите ваше имя',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          TextField(
            controller: _ageController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Возраст *',
              hintText: 'Введите ваш возраст',
              prefixIcon: const Icon(Icons.cake_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          TextField(
            controller: _weightController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Вес (кг) *',
              hintText: 'Введите ваш вес',
              prefixIcon: const Icon(Icons.fitness_center),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          const Text(
            'Хронические заболевания',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Добавьте заболевания, которые могут влиять на прием лекарств',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _diseaseController,
                  decoration: InputDecoration(
                    hintText: 'Введите заболевание',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  onSubmitted: (_) => _addChronicDisease(),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 117, 255, 170),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(Icons.add, color: Colors.black),
                  onPressed: _addChronicDisease,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          if (_chronicDiseases.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Добавленные заболевания:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._chronicDiseases.asMap().entries.map((entry) {
                    int index = entry.key;
                    String disease = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.medical_services,
                              size: 18,
                              color: Color.fromARGB(255, 117, 255, 170),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                disease,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => _removeChronicDisease(index),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              splashRadius: 20,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ],
          
          const SizedBox(height: 32),
          
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelEditing,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Colors.grey.shade400),
                  ),
                  child: const Text(
                    'Отмена',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 117, 255, 170),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _hasProfile ? 'Сохранить' : 'Создать профиль',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}