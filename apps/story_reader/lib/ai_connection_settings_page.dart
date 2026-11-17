import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai_connection.dart';

/// A manual setup screen, never a background connection or a book uploader.
/// No secret is prefilled or displayed after storing it in the device vault.
class AiConnectionSettingsPage extends StatefulWidget {
  const AiConnectionSettingsPage({
    super.key,
    this.preferences,
    this.vault,
    this.connectivity,
  });

  final AiCloudPreferences? preferences;
  final AiApiKeyVault? vault;
  final AiConnectivityCheck? connectivity;

  @override
  State<AiConnectionSettingsPage> createState() =>
      _AiConnectionSettingsPageState();
}

class _AiConnectionSettingsPageState
    extends State<AiConnectionSettingsPage> {
  final _newKey = TextEditingController();
  late final AiCloudPreferences _preferences =
      widget.preferences ?? AiCloudPreferences();
  late final AiApiKeyVault _vault =
      widget.vault ?? DeviceAiApiKeyVault();
  late final AiConnectivityCheck _connectivity =
      widget.connectivity ?? ZaiConnectivityCheck(
        preferences: _preferences, vault: _vault);

  bool _loading = true;
  bool _busy = false;
  bool _hasKey = false;
  bool _allowed = false;
  bool _connected = false;
  String? _message;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _newKey.clear();
    _newKey.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final allowed = await _preferences.isEnabled();
      final hasKey = await _vault.hasKey();
      if (mounted) setState(() {
        _hasKey = hasKey;
        _allowed = allowed && hasKey;
        _loading = false;
      });
      // If the key was removed outside the app, revoke stale consent.
      if (allowed && !hasKey) await _preferences.setEnabled(false);
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _allowed = false;
        _message = 'Защищённое хранилище недоступно. '
            'Проверьте настройки устройства и повторите.';
        _error = true;
      });
    }
  }

  Future<void> _action(Future<void> Function() operation) async {
    if (_busy || _loading) return;
    setState(() {
      _busy = true;
      _error = false;
      _message = null;
    });
    try {
      await operation();
    } on AiSetupException catch (exception) {
      if (mounted) setState(() {
        _error = true;
        _message = exception.message;
      });
    } catch (_) {
      if (mounted) setState(() {
        _error = true;
        _message = 'Операция не завершена. '
            'Проверьте защищённое хранилище или соединение.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveKey() => _action(() async {
    final newValue = _newKey.text.trim();
    if (newValue.isEmpty) {
      throw const AiSetupException('Введите ключ из кабинета Z.ai.');
    }
    // A key change always revokes prior consent before touching the vault.
    await _preferences.setEnabled(false);
    if (mounted) setState(() {
      _allowed = false;
      _connected = false;
    });
    await _vault.write(newValue);
    _newKey.clear();
    if (mounted) setState(() {
      _hasKey = true;
      _message = 'Ключ сохранён в защищённом хранилище устройства. '
          'Разрешение на соединение пока выключено.';
    });
  });

  Future<void> _setAllowed(bool value) async {
    if (_busy || _loading) return;
    if (value && !_hasKey) {
      setState(() {
        _error = true;
        _message = 'Сначала сохраните API-ключ.';
      });
      return;
    }
    if (value) {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Разрешить подключение к Z.ai?'),
          content: const Text(
            'После подтверждения разрешена только ручная проверка '
            'соединения с GLM-4.7-Flash. Она отправит короткую '
            'техническую фразу и ваш API-ключ на Z.ai. '
            'Книги, NPC, история прохождений и сохранения не передаются. '
            'Для будущего анализа книги потребуется отдельное согласие. '
            'Бесплатный тариф и ограничения могут измениться.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Разрешаю проверку'),
            ),
          ],
        ),
      );
      if (agreed != true || !mounted) return;
    }
    await _action(() async {
      await _preferences.setEnabled(value);
      if (mounted) setState(() {
        _allowed = value;
        _connected = false;
        _message = value
            ? 'Разрешение сохранено. Соединение не проверялось.'
            : 'Облачное подключение отключено. Ключ остался на устройстве.';
      });
    });
  }

  Future<void> _testConnection() => _action(() async {
    if (!_allowed || !_hasKey) {
      throw const AiSetupException(
          'Сначала сохраните ключ и разрешите проверку.');
    }
    await _connectivity.check();
    if (mounted) setState(() {
      _connected = true;
      _message = 'GLM-4.7-Flash ответила. Соединение работает. '
          'Текст книги не отправлялся.';
    });
  });

  Future<void> _removeKey() async {
    if (_busy || _loading || !_hasKey) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Удалить API-ключ Z.ai?'),
        content: const Text('Ключ будет удалён только из защищённого '
            'хранилища этого устройства. Разрешение на соединение '
            'будет отключено. Книги и игровые сохранения останутся.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить ключ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _action(() async {
      // Fail closed if native deletion fails.
      await _preferences.setEnabled(false);
      if (mounted) setState(() {
        _allowed = false;
        _connected = false;
      });
      await _vault.delete();
      _newKey.clear();
      if (mounted) setState(() {
        _hasKey = false;
        _message = 'API-ключ удалён. Облачное подключение выключено.';
      });
    });
  }

  Future<void> _copyKeyPage() async {
    await Clipboard.setData(
        const ClipboardData(text: ZaiModel.apiKeysPage));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Адрес страницы API-ключей скопирован')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Подключение ИИ')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text('Провайдер', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.cloud_outlined),
                    title: Text('Z.ai · GLM-4.7-Flash'),
                    subtitle: Text('Основная бесплатная текстовая модель. '
                        'Платные модели не подключаются автоматически. '
                        'Официальный API: api.z.ai'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('GLM-4.7-Flash отмечена бесплатной в тарифах '
                    'провайдера. Лимиты и условия могут измениться. '
                    'В приложении нет фоновых запросов и платного fallback.'),
                const Divider(height: 32),
                Text('Ваш API-ключ',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('Создайте Standard API Key в кабинете Z.ai. '
                    'Ключ не записывается в настройки, книги, сохранения '
                    'и журналы приложения.'),
                TextButton.icon(
                  key: const Key('ai-copy-key-url'),
                  onPressed: _copyKeyPage,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Скопировать адрес получения API-ключа'),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('ai-api-key-input'),
                  controller: _newKey,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Новый API-ключ',
                    helperText: 'После сохранения поле очистится',
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const Key('ai-save-key'),
                  onPressed: _busy || _loading ? null : _saveKey,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Сохранить ключ защищённо'),
                ),
                const SizedBox(height: 8),
                Text(_loading
                    ? 'Читаем защищённые настройки…'
                    : _hasKey
                        ? 'Ключ сохранён на этом устройстве'
                        : 'Ключ пока не сохранён'),
                if (_hasKey)
                  TextButton.icon(
                    key: const Key('ai-delete-key'),
                    onPressed: _busy ? null : _removeKey,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Удалить сохранённый ключ'),
                  ),
                const Divider(height: 32),
                Text('Приватность и соединение',
                    style: Theme.of(context).textTheme.titleMedium),
                SwitchListTile(
                  key: const Key('ai-cloud-consent'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Разрешить проверочное соединение с Z.ai'),
                  subtitle: const Text('Выключено по умолчанию. '
                      'Даже после включения соединение выполняется только '
                      'по нажатию кнопки ниже.'),
                  value: _allowed,
                  onChanged: _busy || _loading ? null : _setAllowed,
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  key: const Key('ai-test-connection'),
                  onPressed: _loading || _busy || !_allowed || !_hasKey
                      ? null : _testConnection,
                  icon: const Icon(Icons.wifi_tethering_outlined),
                  label: const Text('Проверить соединение с GLM-4.7-Flash'),
                ),
                if (_busy) const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
                if (_message != null) Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _message!,
                    key: const Key('ai-status'),
                    style: _error
                        ? TextStyle(color: scheme.error)
                        : null,
                  ),
                ),
                if (_connected)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Проверен только тестовый запрос, '
                        'не анализ книги или игровое общение.'),
                  ),
                const Divider(height: 32),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.smart_toy_outlined),
                  title: Text('Анализ книги и свободная RPG'),
                  subtitle: Text('В подготовке книги доступен ручной '
                      'предпросмотр предложений по одному фрагменту: '
                      'каждая отправка требует нового согласия. '
                      'В проверенных BookWorld v5 доступны свободные ' +
                      'действия ИИ с отдельным согласием и проверкой ' +
                      'последствий движком. Создание литературной RPG ' +
                      'по всей книге требует подтверждённого разбора ' +
                      'источника; внешний ChatGPT Skill E6q.1 ' +
                      'устанавливается через личный .bworld.'),
                ),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.computer_outlined),
                  title: Text('Локальная модель'),
                  subtitle: Text('Запланирована. Текущая игра и чтение '
                      'продолжают работать без интернета.'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
