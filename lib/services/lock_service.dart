import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

/// Desbloqueio por biometria ou pelo PIN/senha do próprio aparelho.
class LockService {
  final _auth = LocalAuthentication();

  /// Textos do diálogo do sistema. Sem eles o plugin mostra o título, a
  /// dica e o botão em inglês ("Authentication required", "Cancel").
  static const _messages = <AuthMessages>[
    AndroidAuthMessages(
      signInTitle: 'Desbloquear o Consultório',
      biometricHint: 'Confirme sua identidade',
      biometricNotRecognized: 'Não reconhecido. Tente de novo.',
      biometricSuccess: 'Pronto',
      cancelButton: 'Cancelar',
      biometricRequiredTitle: 'Biometria necessária',
      deviceCredentialsRequiredTitle: 'Bloqueio de tela necessário',
      deviceCredentialsSetupDescription: 'Configure um PIN, padrão ou senha no aparelho.',
      goToSettingsButton: 'Abrir configurações',
      goToSettingsDescription:
          'A biometria não está configurada neste aparelho. Abra as configurações para cadastrar.',
    ),
    IOSAuthMessages(
      lockOut: 'A biometria foi bloqueada. Bloqueie e desbloqueie o aparelho para reativá-la.',
      goToSettingsButton: 'Abrir ajustes',
      goToSettingsDescription: 'A biometria não está configurada. Abra os Ajustes para cadastrar.',
      cancelButton: 'Cancelar',
      localizedFallbackTitle: 'Usar código',
    ),
  ];

  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Desbloqueie para acessar os dados dos pacientes',
        authMessages: _messages,
        // Sem stickyAuth: no Android 9 e 10 o PIN abre outra tela, o app
        // pausa e, com stickyAuth, o plugin recomeça a autenticação ao
        // voltar e perde o PIN já confirmado. Se o usuário cancelar ou sair,
        // o LockGate continua bloqueado com o botão "Desbloquear".
        options: const AuthenticationOptions(stickyAuth: false, biometricOnly: false),
      );
    } catch (_) {
      return false;
    }
  }
}
