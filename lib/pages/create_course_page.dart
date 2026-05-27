import 'package:flutter/material.dart';
import 'profile_page.dart';
import 'medications_page.dart';

class CreateCoursePage extends StatefulWidget {
  final List<Medication> medications;
  final MedicationCourse? editingCourse;
  
  const CreateCoursePage({
    super.key, 
    required this.medications,
    this.editingCourse,
  });

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
  void initState() {
    super.initState();
    if (widget.editingCourse != null) {
      _loadCourseData();
    }
  }
  
  void _loadCourseData() {
    final course = widget.editingCourse!;
    
    _selectedMedication = widget.medications.firstWhere(
      (med) => med.id == course.medicationId,
      orElse: () => widget.medications.first,
    );
    
    _startDate = course.startDate;
    _reminderTimes.addAll(course.reminderTimes);
    
    if (course.endDate != null) {
      _useCustomEndDate = true;
      _customEndDate = course.endDate;
    } else {
      _durationType = course.durationType;
      if (course.durationValue != null) {
        _durationValue = course.durationValue!;
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editingCourse == null ? 'Новый курс лечения' : 'Редактировать курс'),
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
                                  if (_durationValue < 1) _durationValue = 1;
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
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Время приема (будильник)',
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
                          child: const Icon(Icons.alarm_add, color: Colors.black),
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
                          'Нажмите + чтобы добавить время приема\n(будильник будет срабатывать каждый день)',
                          textAlign: TextAlign.center,
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
                          avatar: const Icon(Icons.alarm, size: 18),
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
                  
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          
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
                onPressed: _createCourse,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 117, 255, 170),
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  widget.editingCourse == null ? 'Создать курс с напоминаниями' : 'Сохранить изменения',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
    if (_selectedMedication == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите лекарство'), duration: Duration(seconds: 2)),
      );
      return;
    }
    
    if (_useCustomEndDate && _customEndDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите дату окончания'), duration: Duration(seconds: 2)),
      );
      return;
    }
    
    if (_reminderTimes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте хотя бы одно время приема'), duration: Duration(seconds: 2)),
      );
      return;
    }
    
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
      id: widget.editingCourse?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      medicationId: _selectedMedication!.id,
      medicationName: _selectedMedication!.name,
      dosage: _selectedMedication!.dosage,
      startDate: _startDate,
      endDate: endDate,
      durationType: durationType,
      durationValue: durationValue,
      reminderTimes: _reminderTimes,
      isActive: true,
      completedAt: widget.editingCourse?.completedAt,
    );
    
    Navigator.pop(context, course);
  }
}