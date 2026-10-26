import 'package:flutter/services.dart';

/// Proteção de tela no Android (FLAG_SECURE): bloqueia capturas e mostra a
/// miniatura em branco na lista de apps recentes. A MainActivity já começa
/// protegida; aqui só se aplica a preferência do usuário. No iOS o
/// equivalente é a capa do LockGate.
class PrivacyService {
  static const _channel = MethodChannel('consultorio/privacy');

  static Future<void> setScreenProtection(bool on) async {
    try {
      await _channel.invokeMethod<void>('setSecure', on);
    } on MissingPluginException {
      // iOS / testes: sem canal nativo.
    } on PlatformException {
      // Sem janela ativa (app em segundo plano): vale na próxima abertura.
    }
  }
}
