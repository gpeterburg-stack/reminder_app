import 'package:flutter/material.dart';

class CreateReminderPage extends StatefulWidget {
  final Map<String, dynamic>? alarm;
  final List<Map<String, dynamic>> medications;
  final Function(Map<String, dynamic>) onSave;

  const CreateReminderPage({
    super.key,
    this.alarm,
    required this.medications,
    required this.onSave,
  });

  @override
  State<CreateReminderPage> createState() => _CreateReminderPageState();
}

class _CreateReminderPageState extends State<CreateReminderPage> {
  final _formKey = GlobalKey<FormState>();
  
  late TimeOfDay _selectedTime;
  late List<int> _selectedDays;
  late String _selectedMedicationId;
  late String _selectedMedicationName;
  late bool _isEnabled;

  final List<String> _weekDays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  void initState() {
    super.initState();
    
    if (widget.alarm != null) {
      _selectedTime = widget.alarm!['time'];
      _selectedDays = List<int>.from(widget.alarm!['days']);
      _selectedMedicationId = widget.alarm!['medicationId'] ?? '';
      _selectedMedicationName = widget.alarm!['medicationName'] ?? '';
      _isEnabled = widget.alarm!['enabled'];
    } else {
      _selectedTime = TimeOfDay.now();
      _selectedDays = [1, 2, 3, 4, 5]; // По умолчанию Пн-Пт
      _selectedMedicationId = '';
      _selectedMedicationName = '';
      _isEnabled = true;
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _toggleDay(int dayIndex) {
    setState(() {
      if (_selectedDays.contains(dayIndex + 1)) {
        _selectedDays.remove(dayIndex + 1);
      } else {
        _selectedDays.add(dayIndex + 1);
      }
      _selectedDays.sort();
    });
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      if (_selectedDays.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Выберите хотя бы один день недели'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      final alarm = {
        'id': widget.alarm?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'time': _selectedTime,
        'days': _selectedDays,
        'medicationId': _selectedMedicationId,
        'medicationName': _selectedMedicationName,
        'enabled': _isEnabled,
      };
      
      widget.onSave(alarm);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.alarm == null ? 'Добавить напоминание' : 'Редактировать напоминание'),
        backgroundColor: const Color.fromARGB(255, 117, 255, 170),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Выбор лекарства
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Лекарство',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedMedicationId.isNotEmpty ? _selectedMedicationId : null,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Выберите лекарство',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('-- Выберите лекарство --'),
                        ),
                        ...widget.medications.map((medication) {
                          return DropdownMenuItem(
                            value: medication['id'],
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  medication['name'],
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '${medication['dosage']} • ${medication['form']}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedMedicationId = value ?? '';
                          if (_selectedMedicationId.isNotEmpty) {
                            final selectedMed = widget.medications.firstWhere(
                              (med) => med['id'] == _selectedMedicationId,
                            );
                            _selectedMedicationName = selectedMed['name'];
                          } else {
                            _selectedMedicationName = '';
                          }
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Выберите лекарство';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Выбор времени
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Время приема',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      leading: const Icon(Icons.access_time, size: 40),
                      title: Text(
                        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      onTap: () => _selectTime(context),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Выбор дней
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Дни приема',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: List.generate(7, (index) {
                        final dayNumber = index + 1;
                        final isSelected = _selectedDays.contains(dayNumber);
                        return FilterChip(
                          label: Text(_weekDays[index]),
                          selected: isSelected,
                          onSelected: (_) => _toggleDay(index),
                          backgroundColor: Colors.grey[200],
                          selectedColor: const Color.fromARGB(255, 117, 255, 170),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedDays = [1, 2, 3, 4, 5];
                            });
                          },
                          child: const Text('Пн-Пт'),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedDays = [6, 7];
                            });
                          },
                          child: const Text('Сб-Вс'),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedDays = [1, 2, 3, 4, 5, 6, 7];
                            });
                          },
                          child: const Text('Ежедневно'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Включение/выключение
            Card(
              child: SwitchListTile(
                title: const Text('Активно'),
                subtitle: const Text('Включить или выключить напоминание'),
                value: _isEnabled,
                onChanged: (value) {
                  setState(() {
                    _isEnabled = value;
                  });
                },
                activeColor: const Color.fromARGB(255, 117, 255, 170),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Кнопка сохранения
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 117, 255, 170),
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 50),
              ),
              child: Text(widget.alarm == null ? 'Добавить напоминание' : 'Сохранить изменения'),
            ),
          ],
        ),
      ),
    );
  }
}