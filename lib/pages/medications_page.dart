import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class Medication {
  final String id;
  final String name;
  final String dosage; 

  Medication({
    required this.id,
    required this.name,
    required this.dosage,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'dosage': dosage,
    };
  }

  factory Medication.fromJson(Map<String, dynamic> json) {
    return Medication(
      id: json['id'],
      name: json['name'],
      dosage: json['dosage'],
    );
  }
}

class MedicationsPage extends StatefulWidget {
  const MedicationsPage({super.key});

  @override
  State<MedicationsPage> createState() => _MedicationsPageState();
}

class _MedicationsPageState extends State<MedicationsPage> {
  List<Medication> _medications = [];

  @override
  void initState() {
    super.initState();
    _loadMedications();
  }

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/medications.json');
  }

  Future<void> _loadMedications() async {
    try {
      final file = await _localFile;

      if (await file.exists()) {
        final contents = await file.readAsString();

        if (contents.isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(contents);
          setState(() {
            _medications = jsonList.map((item) => Medication.fromJson(item)).toList();
          });
        } else {
          _addTestMedications();
        }
      } else {
        _addTestMedications();
      }
    } catch (e) {
      print('Ошибка при загрузке лекарств: $e');
      _addTestMedications();
    }
  }

  void _addTestMedications() {
    setState(() {
      _medications = [
        Medication(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: 'Аспирин',
          dosage: '1 таблетка',
        ),
        Medication(
          id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
          name: 'Парацетамол',
          dosage: '2 таблетки',
        ),
        Medication(
          id: (DateTime.now().millisecondsSinceEpoch + 2).toString(),
          name: 'Витамин D',
          dosage: '1 капсула',
        ),
      ];
    });
    _saveMedicationsToFile();
  }

  Future<void> _saveMedicationsToFile() async {
    try {
      final file = await _localFile;
      final jsonList = _medications.map((med) => med.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('Ошибка при сохранении лекарств: $e');
    }
  }

  void _addMedication(Medication medication) async {
    setState(() {
      _medications.add(medication);
    });
    await _saveMedicationsToFile();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Лекарство добавлено'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _updateMedication(String id, Medication updatedMedication) async {
    setState(() {
      final index = _medications.indexWhere((med) => med.id == id);
      if (index != -1) {
        _medications[index] = updatedMedication;
      }
    });
    await _saveMedicationsToFile();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Лекарство обновлено'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _deleteMedication(String id) async {
    setState(() {
      _medications.removeWhere((med) => med.id == id);
    });
    await _saveMedicationsToFile();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Лекарство удалено'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Text(
                    'Лекарства',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Expanded(
              child: _medications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.medication,
                            size: 100,
                            color: Color.fromARGB(255, 117, 255, 170),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Нет лекарств',
                            style: TextStyle(fontSize: 24),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Нажмите + чтобы добавить лекарство',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _medications.length,
                      itemBuilder: (context, index) {
                        final medication = _medications[index];
                        return Dismissible(
                          key: Key(medication.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.red,
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          onDismissed: (direction) {
                            _deleteMedication(medication.id);
                          },
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(255, 117, 255, 170).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.medication,
                                  size: 30,
                                  color: Color.fromARGB(255, 117, 255, 170),
                                ),
                              ),
                              title: Text(
                                medication.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                medication.dosage,
                                style: const TextStyle(fontSize: 14),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CreateMedicationPage(
                                        medication: medication,
                                        onSave: (updatedMedication) {
                                          _updateMedication(medication.id, updatedMedication);
                                        },
                                      ),
                                    ),
                                  );
                                },
                              ),
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
              builder: (context) => CreateMedicationPage(
                onSave: _addMedication,
              ),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class CreateMedicationPage extends StatefulWidget {
  final Medication? medication;
  final Function(Medication) onSave;

  const CreateMedicationPage({
    super.key,
    this.medication,
    required this.onSave,
  });

  @override
  State<CreateMedicationPage> createState() => _CreateMedicationPageState();
}

class _CreateMedicationPageState extends State<CreateMedicationPage> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameController;
  late TextEditingController _dosageController;

  @override
  void initState() {
    super.initState();
    
    if (widget.medication != null) {
      _nameController = TextEditingController(text: widget.medication!.name);
      _dosageController = TextEditingController(text: widget.medication!.dosage);
    } else {
      _nameController = TextEditingController();
      _dosageController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      final medication = Medication(
        id: widget.medication?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text,
        dosage: _dosageController.text,
      );
      
      widget.onSave(medication);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.medication == null ? 'Добавить лекарство' : 'Редактировать лекарство'),
        backgroundColor: const Color.fromARGB(255, 117, 255, 170),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Название препарата',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.medication),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Введите название препарата';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _dosageController,
              decoration: const InputDecoration(
                labelText: 'Количество (например, 1 таблетка, 2 мл)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.science),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Введите количество';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 117, 255, 170),
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 50),
              ),
              child: Text(widget.medication == null ? 'Добавить' : 'Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}