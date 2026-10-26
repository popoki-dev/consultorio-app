import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../data/app_data.dart';
import '../data/local_db.dart';

/// Exporta todos os dados em JSON (portabilidade de dados, LGPD art. 18, V).
/// O arquivo temporário é apagado logo após o compartilhamento. Retorna
/// true se o usuário concluiu o compartilhamento.
Future<bool> exportAllData(LocalDb db) async {
  final map = await db.exportAll();
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, 'consultorio-${dateKey(today())}.json'));
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  try {
    final result = await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'Exportação de dados do consultório',
    );
    return result.status != ShareResultStatus.dismissed;
  } finally {
    if (await file.exists()) await file.delete();
  }
}

/// Escolhe um arquivo exportado e restaura os dados. Retorna quantos
/// registros entraram, ou null se o usuário cancelou a escolha.
Future<int?> importBackupFile(AppData data) async {
  // FileType.any: vários gerenciadores de arquivos não reconhecem .json.
  final picked = await FilePicker.platform.pickFiles(withData: true);
  final file = picked?.files.single;
  if (file == null) return null;
  final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
  if (bytes == null) throw const FormatException('Não foi possível ler o arquivo.');
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const FormatException('O arquivo escolhido não é um backup do Consultório.');
  }
  if (json is! Map<String, Object?>) {
    throw const FormatException('O arquivo escolhido não é um backup do Consultório.');
  }
  return data.importBackup(json);
}
