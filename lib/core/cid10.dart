/// Códigos CID-10 frequentes na atenção primária, usados como sugestão
/// no cadastro e como legenda no painel epidemiológico. O campo aceita
/// qualquer código; esta lista é só um atalho.
const cid10Common = <String, String>{
  'I10': 'Hipertensão essencial',
  'I11': 'Cardiopatia hipertensiva',
  'I20': 'Angina pectoris',
  'I25': 'Doença isquêmica crônica do coração',
  'I48': 'Fibrilação atrial',
  'I50': 'Insuficiência cardíaca',
  'E10': 'Diabetes mellitus tipo 1',
  'E11': 'Diabetes mellitus tipo 2',
  'E66': 'Obesidade',
  'E78': 'Dislipidemia',
  'E03': 'Hipotireoidismo',
  'E05': 'Hipertireoidismo',
  'F32': 'Episódio depressivo',
  'F33': 'Transtorno depressivo recorrente',
  'F41': 'Transtornos ansiosos',
  'F20': 'Esquizofrenia',
  'F31': 'Transtorno afetivo bipolar',
  'F10': 'Transtornos por uso de álcool',
  'F17': 'Transtornos por uso de tabaco',
  'F90': 'TDAH',
  'F84': 'Transtorno do espectro autista',
  'G40': 'Epilepsia',
  'G43': 'Enxaqueca',
  'G30': 'Doença de Alzheimer',
  'G20': 'Doença de Parkinson',
  'J45': 'Asma',
  'J44': 'DPOC',
  'M54': 'Dorsalgia',
  'M81': 'Osteoporose',
  'M17': 'Artrose do joelho',
  'N18': 'Doença renal crônica',
  'N39': 'Infecção urinária',
  'N95': 'Transtornos da menopausa',
  'Z34': 'Supervisão de gravidez normal (pré-natal)',
  'Z30': 'Anticoncepção',
  'Z00': 'Exame geral (check-up)',
  'Z76': 'Renovação de receita',
  'B20': 'Doença pelo HIV',
  'K21': 'Refluxo gastroesofágico',
  'D50': 'Anemia ferropriva',
};

String cidLabel(String code) {
  final key = code.length > 3 ? code.substring(0, 3) : code;
  final d = cid10Common[code] ?? cid10Common[key];
  return d == null ? code : '$code · $d';
}

List<String> parseCidCodes(String raw) => raw
    .toUpperCase()
    .split(RegExp(r'[\s,;]+'))
    .map((c) => c.replaceAll('.', '').trim())
    .where((c) => c.isNotEmpty)
    .toSet()
    .toList();

/// Exames comuns, como atalhos no formulário.
const commonExams = [
  'Hemograma',
  'Glicemia de jejum',
  'Hemoglobina glicada (HbA1c)',
  'Colesterol total e frações',
  'Triglicerídeos',
  'Creatinina',
  'Ureia',
  'TSH',
  'T4 livre',
  'Urina tipo 1',
  'Potássio',
  'TGO / TGP',
  'Vitamina D',
  'Vitamina B12',
  'Ferritina',
  'PSA',
  'ECG',
  'Mamografia',
  'Papanicolau',
  'Ultrassonografia',
  'Microalbuminúria',
];
