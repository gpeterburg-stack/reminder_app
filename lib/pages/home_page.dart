import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  MedicationCourse? _activeCourse;
  List<TimeOfDay> _takenTimes = [];
  
  TimeOfDay? _nextReminderTime;
  int _takenCount = 0;
  int _totalDailyDoses = 0;
  double _progress = 0.0;
  
  List<MedicationNote> _notes = [];

  @override
  void initState() {
    super.initState();
    _loadActiveCourse();
    _loadNotes();
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
    
    for (var reminder in todayReminders) {
      if (!_isTimeTaken(reminder)) {
        if (reminder.hour > now.hour || 
            (reminder.hour == now.hour && reminder.minute >= now.minute)) {
          _nextReminderTime = reminder;
          return;
        }
      }
    }
    
    _nextReminderTime = null;
  }
  
  bool _isTimeTaken(TimeOfDay time) {
    return _takenTimes.any((taken) => taken.hour == time.hour && taken.minute == time.minute);
  }
  
  bool _canTakeMedication() {
    if (_activeCourse == null) return false;
    if (_takenCount >= _totalDailyDoses) return false;
    
    final now = TimeOfDay.now();
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
    
    _showNoteDialog(isFromMedication: true);
  }
  
  void _showNoteDialog({required bool isFromMedication}) {
    final TextEditingController noteController = TextEditingController();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(isFromMedication ? 'Запись о состоянии' : 'Новая заметка'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isFromMedication 
                  ? 'Как вы себя чувствуете после приема?'
                  : 'Введите вашу заметку',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                hintText: isFromMedication 
                    ? 'Введите ваше состояние...' 
                    : 'Введите заметку...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              maxLines: 3,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (isFromMedication) {
                _confirmTakeMedication();
              }
            },
            child: const Text('Пропустить'),
          ),
          ElevatedButton(
            onPressed: () {
              final noteText = noteController.text.trim();
              if (noteText.isNotEmpty) {
                _saveNote(noteText, isFromMedication);
              }
              Navigator.pop(context);
              if (isFromMedication) {
                _confirmTakeMedication();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 117, 255, 170),
              foregroundColor: Colors.black,
            ),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
  
  void _confirmTakeMedication() {
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
  
  void _saveNote(String noteText, bool isFromMedication) {
    final now = DateTime.now();
    final note = MedicationNote(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      medicationId: isFromMedication && _activeCourse != null ? _activeCourse!.id : '',
      medicationName: isFromMedication && _activeCourse != null ? _activeCourse!.medicationName : 'Общая заметка',
      dosage: isFromMedication && _activeCourse != null ? _activeCourse!.dosage : '',
      dateTime: now,
      note: noteText,
      isFromMedication: isFromMedication,
    );
    
    setState(() {
      _notes.add(note);
    });
    
    _saveNotesToFile();
    
    if (!isFromMedication) {
      _showSnackBar('✅ Заметка добавлена');
    }
  }
  
  Future<void> _loadNotes() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final notesFile = File('${directory.path}/medication_notes.json');
      
      if (await notesFile.exists()) {
        final String data = await notesFile.readAsString();
        if (data.isNotEmpty) {
          final List<dynamic> jsonData = json.decode(data);
          setState(() {
            _notes = jsonData.map((item) => MedicationNote.fromJson(item)).toList();
          });
        }
      }
    } catch (e) {
      print('Ошибка загрузки заметок: $e');
    }
  }
  
  Future<void> _saveNotesToFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final notesFile = File('${directory.path}/medication_notes.json');
      final jsonList = _notes.map((note) => note.toJson()).toList();
      await notesFile.writeAsString(json.encode(jsonList));
    } catch (e) {
      print('Ошибка сохранения заметок: $e');
    }
  }
  
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: message.contains('✓') || message.contains('✅') ? Colors.green : Colors.grey,
      ),
    );
  }
  
  String _getMedicationInfo() {
    if (_activeCourse == null) {
      return 'Нет активного\nкурса лечения';
    }
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
                  
                  if (_activeCourse != null && _activeCourse!.reminderTimes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                  
                  if (_activeCourse != null && _activeCourse!.reminderTimes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                          const SizedBox(height: 6),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: _activeCourse!.reminderTimes.map((time) {
                                final isTaken = _isTimeTaken(time);
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  margin: const EdgeInsets.only(right: 8),
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
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 60),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
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
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _showNotesDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.note, size: 16, color: Colors.blue.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Заметки (${_notes.length})',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showNotesDialog() {
    final TextEditingController noteController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.note, color: Colors.blue),
                const SizedBox(width: 8),
                const Text('Мои заметки'),
              ],
            ),
            content: Container(
              width: double.maxFinite,
              height: 450,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: noteController,
                          decoration: InputDecoration(
                            hintText: 'Новая заметка...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onSubmitted: (value) {
                            _addNoteFromDialog(value, setStateDialog);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          _addNoteFromDialog(noteController.text, setStateDialog);
                        },
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(255, 117, 255, 170),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.add, color: Colors.black, size: 20),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _notes.isEmpty
                        ? const Center(
                            child: Text('Нет заметок'),
                          )
                        : ListView.builder(
                            itemCount: _notes.length,
                            itemBuilder: (context, index) {
                              final note = _notes[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: note.isFromMedication 
                                        ? const Color.fromARGB(255, 117, 255, 170)
                                        : Colors.blue.shade100,
                                    child: Icon(
                                      note.isFromMedication 
                                          ? Icons.medication
                                          : Icons.note,
                                      size: 18,
                                      color: note.isFromMedication 
                                          ? Colors.black
                                          : Colors.blue.shade700,
                                    ),
                                  ),
                                  title: Text(
                                    note.isFromMedication 
                                        ? '💊 ${note.medicationName}'
                                        : '📝 Общая заметка',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        note.note,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      Text(
                                        '${_formatDate(note.dateTime)} ${_formatTime(note.dateTime)}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _notes.removeAt(index);
                                      });
                                      _saveNotesToFile();
                                      setStateDialog(() {});
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Закрыть'),
              ),
            ],
          );
        },
      ),
    );
  }
  
  void _addNoteFromDialog(String text, StateSetter setStateDialog) {
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Введите текст заметки'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    _saveNote(text.trim(), false);
    
    setStateDialog(() {});
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Заметка добавлена'),
        duration: Duration(seconds: 1),
        backgroundColor: Colors.green,
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
  
  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class MedicationNote {
  final String id;
  final String medicationId;
  final String medicationName;
  final String dosage;
  final DateTime dateTime;
  final String note;
  final bool isFromMedication;

  MedicationNote({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    required this.dosage,
    required this.dateTime,
    required this.note,
    required this.isFromMedication,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'medicationId': medicationId,
      'medicationName': medicationName,
      'dosage': dosage,
      'dateTime': dateTime.toIso8601String(),
      'note': note,
      'isFromMedication': isFromMedication,
    };
  }

  factory MedicationNote.fromJson(Map<String, dynamic> json) {
    return MedicationNote(
      id: json['id'],
      medicationId: json['medicationId'],
      medicationName: json['medicationName'],
      dosage: json['dosage'],
      dateTime: DateTime.parse(json['dateTime']),
      note: json['note'],
      isFromMedication: json['isFromMedication'] ?? false,
    );
  }
}