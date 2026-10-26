import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/app_data.dart';
import '../../data/models.dart';
import '../../services/demo_seed.dart';
import '../../services/export_service.dart';
import '../../services/lock_service.dart';
import '../../services/notification_service.dart';
import '../../services/settings.dart';
import '../../services/sync_service.dart';
import '../widgets.dart';
import 'care_lines_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final data = context.watch<AppData>();

    return AccentPage(
      accent: Accent.settings,
      title: 'Ajustes',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          const SectionTitle('Sincronização'),
          const _SyncCard(),

          const SectionTitle('Segurança'),
          OutlinedCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.lockEnabled,
                  title: const Text('Bloquear o app', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Pede biometria ou a senha do aparelho ao abrir'),
                  onChanged: (v) async {
                    // Desativar exige autenticar primeiro.
                    final lock = context.read<LockService>();
                    if (!v && await lock.available() && !await lock.authenticate()) return;
                    await settings.setLockEnabled(v);
                  },
                ),
                if (defaultTargetPlatform == TargetPlatform.android)
                  SwitchListTile(
                    value: settings.screenProtection,
                    title: const Text('Proteger a tela', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text(
                      'Bloqueia capturas de tela e esconde o app na lista de apps recentes',
                    ),
                    onChanged: (v) async {
                      final lock = context.read<LockService>();
                      if (!v && await lock.available() && !await lock.authenticate()) return;
                      await settings.setScreenProtection(v);
                    },
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              'Os dados ficam cifrados no aparelho (SQLCipher, chave no cofre do sistema).',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),

          const SectionTitle('Lembretes'),
          OutlinedCard(
            child: Column(
              children: [
                for (final k in ReminderKind.values)
                  _LeadRow(kind: k, days: settings.leadDays(k), onChanged: (d) => settings.setLeadDays(k, d)),
                const Divider(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.notificationNames,
                  title: const Text('Nome do paciente nas notificações',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    settings.notificationNames
                        ? 'Nome, medicamento e exame aparecem também na tela bloqueada'
                        : 'Só as iniciais aparecem (recomendado: a tela bloqueada fica à vista)',
                  ),
                  onChanged: settings.setNotificationNames,
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Permitir notificações'),
                    onPressed: () => context.read<NotificationService>().requestPermission(),
                  ),
                ),
              ],
            ),
          ),

          const SectionTitle('Consultório'),
          OutlinedCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: const Text('Linhas de cuidado', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(data.careLines.map((c) => c.name).join(', ')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CareLinesScreen()),
              ),
            ),
          ),

          const SectionTitle('Dados (LGPD)'),
          OutlinedCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BackupStatus(lastBackup: settings.lastBackup),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Exportar todos os dados (backup)'),
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Exportar dados?',
                      message: 'Será gerado um arquivo JSON com todos os dados dos pacientes. '
                          'Ele serve de backup e pode ser restaurado aqui mesmo. '
                          'Guarde-o em local seguro: o arquivo não é cifrado.',
                      confirm: 'Exportar',
                    );
                    if (!ok || !context.mounted) return;
                    if (await exportAllData(context.read<AppData>().db)) {
                      await settings.setLastBackup(DateTime.now());
                    }
                  },
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.settings_backup_restore_rounded),
                  label: const Text('Restaurar backup'),
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Restaurar backup?',
                      message: 'Os registros do arquivo são juntados aos do aparelho. '
                          'Nada mais recente é sobrescrito e nada é apagado.',
                      confirm: 'Escolher arquivo',
                    );
                    if (!ok || !context.mounted) return;
                    try {
                      final n = await importBackupFile(context.read<AppData>());
                      if (n == null || !context.mounted) return;
                      showSnack(
                        context,
                        n == 0
                            ? 'Nada a restaurar: o aparelho já tem esses dados.'
                            : '${plural(n, 'registro restaurado', 'registros restaurados')}.',
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      showSnack(
                        context,
                        e is FormatException ? e.message : 'Falha ao restaurar: $e',
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                if (data.patients.isEmpty)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Carregar dados de demonstração'),
                    onPressed: () async {
                      await seedDemoData(context.read<AppData>());
                      if (context.mounted) showSnack(context, 'Dados fictícios carregados.');
                    },
                  ),
                if (hasDemoData(data))
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('Remover dados de demonstração'),
                    onPressed: () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'Remover dados fictícios?',
                        message: 'Apenas os pacientes marcados como demonstração serão removidos.',
                        confirm: 'Remover',
                        danger: true,
                      );
                      if (ok && context.mounted) await removeDemoData(context.read<AppData>());
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text('Consultório · versão 1.2.0', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/// Sem sincronização, o backup exportado é a única cópia fora do aparelho.
class _BackupStatus extends StatelessWidget {
  const _BackupStatus({required this.lastBackup});
  final DateTime? lastBackup;

  static const _staleAfterDays = 30;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final last = lastBackup;
    final days = last == null ? null : daysBetween(last, DateTime.now());
    final stale = !sync.signedIn && (days == null || days > _staleAfterDays);
    final text = last == null
        ? 'Nenhum backup exportado ainda.'
        : 'Último backup: ${fmtDate(last)} (${relativeDays(last)}).';
    return Row(
      children: [
        Icon(
          stale ? Icons.warning_amber_rounded : Icons.verified_outlined,
          color: stale ? AppColors.warn : AppColors.ok,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            stale
                ? '$text Sem sincronização, exporte um backup ao menos 1 vez por mês '
                    'e guarde-o fora do aparelho.'
                : text,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _LeadRow extends StatelessWidget {
  const _LeadRow({required this.kind, required this.days, required this.onChanged});
  final ReminderKind kind;
  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final what = switch (kind) {
      ReminderKind.returnVisit => 'Retornos',
      ReminderKind.prescription => 'Receitas',
      ReminderKind.exam => 'Exames',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(kind.icon, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(what, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  days == 0 ? 'Avisar só no dia' : 'Avisar $days dias antes e no dia',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Menos dias',
            onPressed: days > 0 ? () => onChanged(days - 1) : null,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
          SizedBox(
            width: 28,
            child: Text('$days', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          IconButton(
            tooltip: 'Mais dias',
            onPressed: days < 60 ? () => onChanged(days + 1) : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _SyncCard extends StatefulWidget {
  const _SyncCard();

  @override
  State<_SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends State<_SyncCard> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();

    if (!sync.enabled) {
      return const OutlinedCard(
        child: Row(
          children: [
            Icon(Icons.phone_android_rounded),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Modo somente neste aparelho. Os dados ficam salvos localmente e funcionam sem internet.',
              ),
            ),
          ],
        ),
      );
    }

    if (!sync.signedIn) {
      return OutlinedCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Entre para sincronizar os dados entre os seus aparelhos.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'E-mail'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Senha'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() {
                        _busy = true;
                        _error = null;
                      });
                      final err = await sync.signIn(_email.text, _password.text);
                      if (!mounted) return;
                      setState(() {
                        _busy = false;
                        _error = err;
                      });
                      if (err == null) _password.clear();
                    },
              child: Text(_busy ? 'Entrando…' : 'Entrar'),
            ),
          ],
        ),
      );
    }

    final last = sync.lastSync;
    return OutlinedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                sync.lastError != null ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
                color: sync.lastError != null ? AppColors.warn : AppColors.ok,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sync.userEmail ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      sync.syncing
                          ? 'Sincronizando…'
                          : last == null
                              ? 'Ainda não sincronizado'
                              : 'Última sincronização: ${fmtDate(last)} às ${fmtTime(last)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (sync.lastError != null) ...[
            const SizedBox(height: 8),
            Text(sync.lastError!, style: const TextStyle(fontSize: 12, color: AppColors.warn)),
          ],
          if (sync.conflicts > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${sync.conflicts} alteração(ões) simultânea(s) resolvida(s) automaticamente; '
              'as versões anteriores foram guardadas no aparelho.',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: sync.syncing ? null : sync.syncNow,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Sincronizar'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () async {
                  final pending = await sync.pendingChanges();
                  if (!context.mounted) return;
                  final ok = await confirmDialog(
                    context,
                    title: 'Sair da conta?',
                    message: pending == 0
                        ? 'Os dados continuam neste aparelho, mas deixam de sincronizar.'
                        : 'Há ${plural(pending, 'alteração', 'alterações')} ainda não '
                            'enviada(s). Elas continuam neste aparelho, mas o outro '
                            'aparelho não as receberá até você entrar de novo.',
                    confirm: 'Sair',
                    danger: pending > 0,
                  );
                  if (ok) await sync.signOut();
                },
                child: const Text('Sair'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
