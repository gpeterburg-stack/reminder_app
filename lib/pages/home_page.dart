import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'profile_page.dart'; // Импортируем для доступа к MedicationCourse

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  MedicationCourse? _activeCourse;
  List<TimeOfDay> _takenTimes = [];
  
  // Информация о текущем приеме
  TimeOfDay? _nextReminderTime;
  int _takenCount = 0;
  int _totalDailyDoses = 0;

  @override
  void initState() {
    super.initState();
    _loadActiveCourse();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadActiveCourse();
  }

  Future<void> _loadActiveCourse() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final coursesFile = File('${directory.path}/medication_courses.json');
      
      if (await coursesFile.exists()) {
        final String data = await coursesFile.readAsString();
        if (data.isNotEmpty) {
          final List<dynamic> jsonData = json.decode(data);
          final allCourses = jsonData.map((item) => MedicationCourse.fromJson(item)).toList();
          
          // Ищем активный курс (не просроченный и не завершенный)
          MedicationCourse? activeCourse;
        try {
          activeCourse = allCourses.firstWhere(
            (course) => course.isActive && !course.isExpired,
          );
        } catch (e) {
          activeCourse = null;
        }
          
          setState(() {
            _activeCourse = activeCourse;
          });
          
          if (_activeCourse != null) {
            await _loadTodayProgress();
          }
        }
      }
    } catch (e) {
      print('Ошибка загрузки курса: $e');
    }
  }
  
  Future<void> _loadTodayProgress() async {
    if (_activeCourse == null) return;
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final progressFile = File('${directory.path}/medication_progress.json');
      
      final today = DateTime.now();
      final todayKey = '${today.year}-${today.month}-${today.day}-${_activeCourse!.id}';
      
      if (await progressFile.exists()) {
        final String data = await progressFile.readAsString();
        if (data.isNotEmpty) {
          final Map<String, dynamic> progressData = json.decode(data);
          if (progressData.containsKey(todayKey)) {
            final takenTimesRaw = progressData[todayKey] as List;
            _takenTimes = takenTimesRaw.map((timeStr) {
              final parts = timeStr.split(':');
              return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
            }).toList();
          } else {
            _takenTimes = [];
          }
        } else {
          _takenTimes = [];
        }
      } else {
        _takenTimes = [];
      }
      
      // Используем reminderTimes из MedicationCourse
      _totalDailyDoses = _activeCourse!.reminderTimes.length;
      _takenCount = _takenTimes.length;
      _progress = _totalDailyDoses > 0 ? _takenCount / _totalDailyDoses : 0.0;
      
      _findNextReminderTime();
      
      setState(() {});
    } catch (e) {
      print('Ошибка загрузки прогресса: $e');
    }
  }
  
  Future<void> _saveTodayProgress() async {
    if (_activeCourse == null) return;
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final progressFile = File('${directory.path}/medication_progress.json');
      
      final today = DateTime.now();
      final todayKey = '${today.year}-${today.month}-${today.day}-${_activeCourse!.id}';
      
      Map<String, dynamic> progressData = {};
      if (await progressFile.exists()) {
        final String data = await progressFile.readAsString();
        if (data.isNotEmpty) {
          progressData = json.decode(data);
        }
      }
      
      final takenTimesStr = _takenTimes.map((time) => '${time.hour}:${time.minute}').toList();
      progressData[todayKey] = takenTimesStr;
      
      await progressFile.writeAsString(json.encode(progressData));
    } catch (e) {
      print('Ошибка сохранения прогресса: $e');
    }
  }
  
  void _findNextReminderTime() {
    if (_activeCourse == null || _activeCourse!.reminderTimes.isEmpty) {
      _nextReminderTime = null;
      return;
    }
    
    final now = TimeOfDay.now();
    final todayReminders = _activeCourse!.reminderTimes;
    
    // Находим следующее время приема, которое еще не принято
    for (var reminder in todayReminders) {
      if (!_isTimeTaken(reminder)) {
        // Если время еще не наступило или наступило, но не принято
        if (reminder.hour > now.hour || 
            (reminder.hour == now.hour && reminder.minute >= now.minute)) {
          _nextReminderTime = reminder;
          return;
        }
      }
    }
    
    // Если все приемы на сегодня выполнены
    _nextReminderTime = null;
  }
  
  bool _isTimeTaken(TimeOfDay time) {
    return _takenTimes.any((taken) => taken.hour == time.hour && taken.minute == time.minute);
  }
  
  bool _canTakeMedication() {
    if (_activeCourse == null) return false;
    if (_takenCount >= _totalDailyDoses) return false;
    
    final now = TimeOfDay.now();
    // Проверяем, есть ли непринятое время, которое уже наступило
    for (var reminder in _activeCourse!.reminderTimes) {
      if (!_isTimeTaken(reminder)) {
        if (reminder.hour < now.hour || 
            (reminder.hour == now.hour && reminder.minute <= now.minute)) {
          return true;
        }
      }
    }
    return false;
  }
  
  void _takeMedication() {
    if (!_canTakeMedication()) {
      _showSnackBar('Сейчас нет запланированного приема лекарства');
      return;
    }
    
    final now = TimeOfDay.now();
    
    setState(() {
      _takenTimes.add(now);
      _takenCount = _takenTimes.length;
      _progress = _totalDailyDoses > 0 ? _takenCount / _totalDailyDoses : 0.0;
      _findNextReminderTime();
    });
    
    _saveTodayProgress();
    _showSnackBar('✓ Прием лекарства подтвержден!');
  }
  
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: message.contains('✓') ? Colors.green : Colors.grey,
      ),
    );
  }
  
  String _getMedicationInfo() {
    if (_activeCourse == null) {
      return 'Нет активного\nкурса лечения';
    }
    // Используем medicationName и dosage из MedicationCourse
    return '${_activeCourse!.medicationName}\n${_activeCourse!.dosage}';
  }
  
  String _getProgressStatus() {
    if (_activeCourse == null) {
      return 'Создайте курс\nв профиле';
    }
    if (_takenCount >= _totalDailyDoses) {
      return 'Все приемы\nвыполнены! 🎉';
    }
    if (_nextReminderTime != null) {
      return 'Следующий прием\nв ${_nextReminderTime!.hour.toString().padLeft(2, '0')}:${_nextReminderTime!.minute.toString().padLeft(2, '0')}';
    }
    return 'Приемов\nсегодня нет';
  }

  double _progress = 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Круг с прогрессом
                  Transform.translate(
                    offset: const Offset(0, -80),
                    child: SizedBox(
                      width: 250,
                      height: 250,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 250,
                            height: 250,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFE0E0E0),
                            ),
                          ),
                          SizedBox(
                            width: 250,
                            height: 250,
                            child: CircularProgressIndicator(
                              value: _progress,
                              strokeWidth: 12,
                              backgroundColor: Colors.transparent,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color.fromARGB(255, 117, 255, 170),
                              ),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(_progress * 100).toInt()}%',
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _getMedicationInfo(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (_activeCourse != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '$_takenCount / $_totalDailyDoses',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Статус следующего приема
                  if (_activeCourse != null && _activeCourse!.reminderTimes.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: _takenCount >= _totalDailyDoses 
                            ? Colors.green.shade50 
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        _getProgressStatus(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _takenCount >= _totalDailyDoses 
                              ? Colors.green.shade700 
                              : Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                  
                  // Список времени приема (из reminderTimes)
                  if (_activeCourse != null && _activeCourse!.reminderTimes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Расписание приема:',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: _activeCourse!.reminderTimes.map((time) {
                              final isTaken = _isTimeTaken(time);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isTaken 
                                      ? Colors.green.shade100 
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isTaken 
                                        ? Colors.green.shade300 
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isTaken ? Icons.check_circle : Icons.access_time,
                                      size: 16,
                                      color: isTaken ? Colors.green : Colors.grey,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        decoration: isTaken ? TextDecoration.lineThrough : null,
                                        color: isTaken ? Colors.green.shade700 : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Кнопка подтверждения приема
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 100),
                child: ElevatedButton(
                  onPressed: _takeMedication,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 15,
                    ),
                    backgroundColor: _canTakeMedication()
                        ? const Color.fromARGB(255, 117, 255, 170)
                        : Colors.grey.shade400,
                    foregroundColor: Colors.black,
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  child: Text(
                    _activeCourse == null 
                        ? 'Нет активного курса'
                        : (_takenCount >= _totalDailyDoses 
                            ? 'Сегодня все приемы выполнены ✓' 
                            : 'Подтвердить прием лекарства'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}