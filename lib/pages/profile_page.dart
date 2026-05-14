import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'medications_page.dart';

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
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadProfile();
    _loadCourses();
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _diseaseController.dispose();
    _tabController.dispose();
    super.dispose();
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
          
          // Проверяем и обновляем статусы курсов
          for (var course in allCourses) {
            if (course.isActive && course.isExpired) {
              course = MedicationCourse(
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
            }
          }
          
          setState(() {
            _activeCourses = allCourses.where((c) => c.isActive && !c.isExpired).toList();
            _completedCourses = allCourses.where((c) => !c.isActive || c.isExpired).toList();
          });
          
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
              if (_profileFile != null && await _profileFile!.exists()) {
                await _profileFile!.delete();
              }
              setState(() {
                _profileName = '';
                _age = '';
                _weight = '';
                _chronicDiseases = [];
                _hasProfile = false;
                _isEditing = true;
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
    // Загружаем список лекарств
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
      _showSnackBar('Курс лечения добавлен');
    }
  }
  
  void _completeCourse(MedicationCourse course) async {
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
    _showSnackBar('Курс завершен и перемещен в историю');
  }
  
  void _deleteCourse(MedicationCourse course) async {
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
        // Профиль пользователя
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
        
        // Табы с курсами
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
                if (isActive && daysLeft != null)
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
            
            // Информация о курсе
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

// Страница создания курса с фиксированной кнопкой
class CreateCoursePage extends StatefulWidget {
  final List<Medication> medications;
  
  const CreateCoursePage({super.key, required this.medications});

  @override
  State<CreateCoursePage> createState() => _CreateCoursePageState();
}

class _CreateCoursePageState extends State<CreateCoursePage> {
  Medication? _selectedMedication;
  CourseDurationType _durationType = CourseDurationType.unlimited;
  int _durationValue = 1;
  DateTime _startDate = DateTime.now();
  DateTime? _customEndDate;
  bool _useCustomEndDate = false;
  final List<TimeOfDay> _reminderTimes = [];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Новый курс лечения'),
        backgroundColor: const Color.fromARGB(255, 117, 255, 170),
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Выбор лекарства
                  const Text(
                    'Выберите лекарство',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButton<Medication>(
                      isExpanded: true,
                      hint: const Text('Выберите лекарство'),
                      value: _selectedMedication,
                      items: widget.medications.map((med) {
                        return DropdownMenuItem(
                          value: med,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(med.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                              Text(med.dosage, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedMedication = value;
                        });
                      },
                      underline: const SizedBox(),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Дата начала
                  const Text(
                    'Дата начала курса',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _startDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) {
                        setState(() {
                          _startDate = date;
                          if (_useCustomEndDate && _customEndDate != null && _customEndDate!.isBefore(date)) {
                            _customEndDate = date.add(const Duration(days: 1));
                          }
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.grey),
                          const SizedBox(width: 12),
                          Text(
                            '${_startDate.day.toString().padLeft(2, '0')}.${_startDate.month.toString().padLeft(2, '0')}.${_startDate.year}',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Выбор способа установки длительности
                  const Text(
                    'Способ установки длительности',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        RadioListTile<bool>(
                          title: const Text('Использовать период'),
                          value: false,
                          groupValue: _useCustomEndDate,
                          onChanged: (value) {
                            setState(() {
                              _useCustomEndDate = value!;
                            });
                          },
                        ),
                        RadioListTile<bool>(
                          title: const Text('Выбрать дату окончания'),
                          value: true,
                          groupValue: _useCustomEndDate,
                          onChanged: (value) {
                            setState(() {
                              _useCustomEndDate = value!;
                              if (_useCustomEndDate && _customEndDate == null) {
                                _customEndDate = _startDate.add(const Duration(days: 7));
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Вариант 1: Выбор периода
                  if (!_useCustomEndDate) ...[
                    const Text(
                      'Длительность курса',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButton<CourseDurationType>(
                        isExpanded: true,
                        value: _durationType,
                        items: const [
                          DropdownMenuItem(
                            value: CourseDurationType.unlimited,
                            child: Text('Бессрочно'),
                          ),
                          DropdownMenuItem(
                            value: CourseDurationType.days,
                            child: Text('Дни'),
                          ),
                          DropdownMenuItem(
                            value: CourseDurationType.weeks,
                            child: Text('Недели'),
                          ),
                          DropdownMenuItem(
                            value: CourseDurationType.months,
                            child: Text('Месяцы'),
                          ),
                          DropdownMenuItem(
                            value: CourseDurationType.years,
                            child: Text('Годы'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _durationType = value!;
                          });
                        },
                        underline: const SizedBox(),
                      ),
                    ),
                    
                    if (_durationType != CourseDurationType.unlimited) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: _durationValue.toString(),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Количество',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _durationValue = int.tryParse(value) ?? 1;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(_getDurationLabel()),
                          ),
                        ],
                      ),
                    ],
                    
                    if (_durationType != CourseDurationType.unlimited) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.event, color: Colors.blue.shade700),
                            const SizedBox(width: 12),
                            Text(
                              'Дата окончания: ${_formatDate(_calculateEndDate())}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  
                  // Вариант 2: Ручной выбор даты окончания
                  if (_useCustomEndDate) ...[
                    const Text(
                      'Дата окончания курса',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _customEndDate ?? _startDate.add(const Duration(days: 7)),
                          firstDate: _startDate.add(const Duration(days: 1)),
                          lastDate: DateTime(2100),
                        );
                        if (date != null) {
                          setState(() {
                            _customEndDate = date;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event_available, color: Colors.grey),
                            const SizedBox(width: 12),
                            Text(
                              _customEndDate != null 
                                  ? _formatDate(_customEndDate!)
                                  : 'Выберите дату',
                              style: TextStyle(
                                fontSize: 16,
                                color: _customEndDate != null ? Colors.black : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    if (_customEndDate != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange.shade700),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Длительность курса: ${_calculateDurationInDays()} ${_getDaysLabel(_calculateDurationInDays())}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  
                  const SizedBox(height: 24),
                  
                  // Время напоминаний
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Время приема',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        onPressed: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (time != null) {
                            setState(() {
                              _reminderTimes.add(time);
                              _reminderTimes.sort((a, b) {
                                if (a.hour != b.hour) return a.hour.compareTo(b.hour);
                                return a.minute.compareTo(b.minute);
                              });
                            });
                          }
                        },
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
                  
                  const SizedBox(height: 12),
                  
                  if (_reminderTimes.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          'Нажмите + чтобы добавить время приема',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _reminderTimes.asMap().entries.map((entry) {
                        final index = entry.key;
                        final time = entry.value;
                        return Chip(
                          avatar: const Icon(Icons.access_time, size: 18),
                          label: Text(
                            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                          ),
                          onDeleted: () {
                            setState(() {
                              _reminderTimes.removeAt(index);
                            });
                          },
                        );
                      }).toList(),
                    ),
                  
                  // Добавляем отступ снизу для контента
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          
          // Фиксированная кнопка внизу
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: ElevatedButton(
                onPressed: _canCreateCourse() ? _createCourse : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 117, 255, 170),
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Создать курс',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  bool _canCreateCourse() {
    if (_selectedMedication == null) return false;
    if (_useCustomEndDate && _customEndDate == null) return false;
    return true;
  }
  
  String _getDurationLabel() {
    switch (_durationType) {
      case CourseDurationType.days:
        return _durationValue == 1 ? 'день' : 
               _durationValue < 5 ? 'дня' : 'дней';
      case CourseDurationType.weeks:
        return _durationValue == 1 ? 'неделя' : 
               _durationValue < 5 ? 'недели' : 'недель';
      case CourseDurationType.months:
        return _durationValue == 1 ? 'месяц' : 
               _durationValue < 5 ? 'месяца' : 'месяцев';
      case CourseDurationType.years:
        return _durationValue == 1 ? 'год' : 
               _durationValue < 5 ? 'года' : 'лет';
      default:
        return '';
    }
  }
  
  String _getDaysLabel(int days) {
    if (days == 1) return 'день';
    if (days >= 2 && days <= 4) return 'дня';
    return 'дней';
  }
  
  DateTime _calculateEndDate() {
    switch (_durationType) {
      case CourseDurationType.days:
        return _startDate.add(Duration(days: _durationValue));
      case CourseDurationType.weeks:
        return _startDate.add(Duration(days: _durationValue * 7));
      case CourseDurationType.months:
        return DateTime(
          _startDate.year,
          _startDate.month + _durationValue,
          _startDate.day,
        );
      case CourseDurationType.years:
        return DateTime(
          _startDate.year + _durationValue,
          _startDate.month,
          _startDate.day,
        );
      default:
        return _startDate;
    }
  }
  
  int _calculateDurationInDays() {
    if (_customEndDate == null) return 0;
    return _customEndDate!.difference(_startDate).inDays;
  }
  
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
  
  void _createCourse() {
    DateTime? endDate;
    CourseDurationType durationType;
    int? durationValue;
    
    if (_useCustomEndDate) {
      endDate = _customEndDate;
      durationType = CourseDurationType.unlimited;
      durationValue = null;
    } else {
      if (_durationType == CourseDurationType.unlimited) {
        endDate = null;
      } else {
        endDate = _calculateEndDate();
      }
      durationType = _durationType;
      durationValue = _durationType != CourseDurationType.unlimited ? _durationValue : null;
    }
    
    final course = MedicationCourse(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      medicationId: _selectedMedication!.id,
      medicationName: _selectedMedication!.name,
      dosage: _selectedMedication!.dosage,
      startDate: _startDate,
      endDate: endDate,
      durationType: durationType,
      durationValue: durationValue,
      reminderTimes: _reminderTimes,
      isActive: true,
      completedAt: null,
    );
    
    Navigator.pop(context, course);
  }
}