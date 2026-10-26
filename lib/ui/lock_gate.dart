import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/lock_service.dart';
import '../services/settings.dart';

/// Cobre o app com a tela de bloqueio ao abrir e ao voltar depois de
/// mais de 1 minuto em segundo plano.
class LockGate extends StatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  static const _graceperiod = Duration(minutes: 1);

  bool _locked = true;
  bool _authenticating = false;
  DateTime? _backgroundAt;

  /// iOS tira a foto do app para o seletor de apps ao sair; a capa evita
  /// que os dados apareçam nela. (No Android isso é feito pelo FLAG_SECURE.)
  bool _covered = false;
  static bool get _coverOnInactive => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _lockIfNeeded());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _lockIfNeeded() async {
    final settings = context.read<AppSettings>();
    final lock = context.read<LockService>();
    if (!settings.lockEnabled || !await lock.available()) {
      if (mounted) setState(() => _locked = false);
      return;
    }
    if (mounted) setState(() => _locked = true);
    await _unlock();
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    _authenticating = true;
    final ok = await context.read<LockService>().authenticate();
    _authenticating = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_authenticating) return; // o diálogo de biometria pausa o app
    if (_coverOnInactive) {
      final cover = state != AppLifecycleState.resumed;
      if (cover != _covered) setState(() => _covered = cover);
    }
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundAt;
      _backgroundAt = null;
      if (!_locked && since != null && DateTime.now().difference(since) > _graceperiod) {
        _lockIfNeeded();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: _LockScreen(onUnlock: _unlock),
          )
        else if (_covered)
          const Positioned.fill(child: ColoredBox(color: AppColors.cream)),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cream,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.yellow,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.ink, width: 1.5),
                ),
                child: const Icon(Icons.lock_outline_rounded, size: 42, color: AppColors.ink),
              ),
              const SizedBox(height: 22),
              const Text('Consultório', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text(
                'Os dados dos pacientes estão protegidos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text('Desbloquear'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
