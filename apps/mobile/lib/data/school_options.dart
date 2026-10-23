// lib/data/school_options.dart
//
// Liceele afișate în dropdown-ul de la înregistrare.
// Pentru a adăuga un liceu, adaugă o linie nouă în lista de mai jos.
// Opțiunea "Altul" afișează un câmp text în care utilizatorul scrie liceul.

const String otherSchoolOption = 'Altul';

const List<String> schoolOptions = [
  'C.N. „Ferdinand I”',
  'C.N. „V. Alecsandri”',
  'C.N. Catolic „Sf. Iosif”',
  'C.N.P. „Ștefan cel Mare”',
  'C.N. „G. Vrănceanu”',
  'C.N. de Artă „G. Apostu”',
  'C. „M. Eminescu”',
  'Liceul Teoretic „Henri Coandă”',
  'C. „N.V. Karpen”',
  otherSchoolOption,
];

/// True when the user picked "Altul" and must type the school name.
bool isOtherSchool(String? value) => value == otherSchoolOption;
