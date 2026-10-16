import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const PokedexApp());
}

class Pokemon {
  const Pokemon({
    required this.id,
    required this.name,
    required this.height,
    required this.weight,
    required this.imageUrl,
    required this.types,
    required this.baseStats,
  });

  final int id;
  final String name;
  final int height;
  final int weight;
  final String imageUrl;
  final List<String> types;
  final Map<String, int> baseStats;

  factory Pokemon.fromJson(Map<String, dynamic> json) {
    final sprites = json['sprites'] as Map<String, dynamic>;
    final other = sprites['other'] as Map<String, dynamic>?;
    final artwork = other?['official-artwork'] as Map<String, dynamic>?;
    final imageUrl =
        artwork?['front_default'] as String? ??
        sprites['front_default'] as String? ??
        '';

    return Pokemon(
      id: json['id'] as int,
      name: json['name'] as String,
      height: json['height'] as int,
      weight: json['weight'] as int,
      imageUrl: imageUrl,
      types: (json['types'] as List<dynamic>)
          .map(
            (entry) =>
                (entry as Map<String, dynamic>)['type']['name'] as String,
          )
          .toList(),
      baseStats: {
        for (final entry in json['stats'] as List<dynamic>? ?? const [])
          (entry as Map<String, dynamic>)['stat']['name'] as String:
              entry['base_stat'] as int,
      },
    );
  }

  double get heightInMeters => height / 10;
  double get weightInKilograms => weight / 10;
}

class PokemonService {
  PokemonService()
    : _dio = Dio(
        BaseOptions(
          baseUrl: 'https://pokeapi.co/api/v2',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

  final Dio _dio;

  Future<Pokemon> fetchPokemon(String identifier) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/pokemon/$identifier/',
    );
    final data = response.data;
    if (data == null) {
      throw const FormatException('La respuesta de PokeAPI está vacía.');
    }
    return Pokemon.fromJson(data);
  }

  Future<String?> fetchSpanishFlavorText(String identifier) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/pokemon-species/$identifier/',
    );
    final entries = response.data?['flavor_text_entries'] as List<dynamic>?;
    if (entries == null) return null;
    for (final entry in entries) {
      final item = entry as Map<String, dynamic>;
      final language = item['language'] as Map<String, dynamic>;
      if (language['name'] == 'es') {
        return (item['flavor_text'] as String)
            .replaceAll(RegExp(r'[\n\f\r]+'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }
    }
    return null;
  }
}

class RotomDexService {
  // 1. Pega tu API Key completa aquí (la que empieza con AQ.)
  static const String _geminiApiKey =
      'AQ.Ab8RN6LI2lqGe3feQ7_YMbqGtVs51b9bTimQdWqsfCeK4Et1fQ';

  // 2. Lista de modelos recomendados por tu amigo (Cascada de Fallback)
  static const List<String> _modelos = [
    'gemini-3.8-flash',
    'gemini-3.6-flash',
    'gemini-3.5-flash-lite',
  ];

  Future<String> ask({
    required Pokemon pokemon,
    required String flavorText,
    required String question,
    required List<Map<String, String>> history,
  }) async {
    if (_geminiApiKey.isEmpty || _geminiApiKey.contains('TU_API_KEY')) {
      throw StateError(
        'Falta configurar tu API Key. Reemplaza "AQ.TU_API_KEY_AQUI" con tu clave real.',
      );
    }

    final stats = pokemon.baseStats.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(', ');

    final systemPrompt =
        '''
    Eres Rotom-Dex, el asistente inteligente y experto definitivo en el mundo Pokémon. Tu objetivo es proporcionar información clara, precisa, detallada y muy llamativa en español.

    REGLAS DE FORMATO ESTRICTAS:
    1. ESTÁ PROHIBIDO USAR MARKDOWN. NUNCA uses asteriscos (*) ni almohadillas (#) en tus respuestas.
    2. Para resaltar información importante, usa MAYÚSCULAS.
    3. Usa emojis frecuentemente (como ⚡, 🛡️, ⚔️, 🧬, 🔍, 🌟) para hacer la lectura visualmente atractiva, moderna y fácil de escanear.
    4. Usa saltos de línea y guiones (-) para crear listas limpias y ordenadas.

    Dirígete siempre a mí como "Entrenador PKM" y mantén un tono enérgico y entusiasta. Ve directo al grano con datos precisos y estructurados, analizando a fondo al Pokémon.

    Instrucciones de contexto:
    - Si te preguntan sobre el Pokémon de la ficha actual, utiliza exhaustivamente los datos proporcionados a continuación para elaborar tu análisis.
    - Si te hacen una pregunta general sobre el mundo Pokémon, responde con precisión utilizando tu conocimiento de la base de datos nacional.

    DATOS DEL POKÉMON ACTUAL: 
    - Especie: ${pokemon.name}
    - Número de Pokédex: N.º ${pokemon.id}
    - Tipos: ${pokemon.types.join(', ')}
    - Altura: ${pokemon.heightInMeters} m
    - Peso: ${pokemon.weightInKilograms} kg
    - Estadísticas base: $stats
    - Entrada de la Pokédex: $flavorText
    ''';
    final contents = <Map<String, Object>>[
      {
        'role': 'user',
        'parts': [
          {'text': 'Instrucciones del sistema:\n$systemPrompt'},
        ],
      },
      {
        'role': 'model',
        // Aquí también cambiamos el saludo inicial para eliminar el "zzt"
        'parts': [
          {
            'text':
                '¡Entendido, Entrenador PKM! Soy Rotom-Dex y estoy listo para ayudarte con la información de ${pokemon.name}.',
          },
        ],
      },
      for (final message in history)
        {
          'role': message['role'] == 'assistant' ? 'model' : 'user',
          'parts': [
            {'text': message['content'] ?? ''},
          ],
        },
      {
        'role': 'user',
        'parts': [
          {'text': question},
        ],
      },
    ];

    int retryDelayMs = 1500; // Inicia esperando 1.5 segundos si hay error

    // 3. Iteramos sobre los modelos de tu amigo
    for (int i = 0; i < _modelos.length; i++) {
      final currentModel = _modelos[i];
      final url = Uri.https(
        'generativelanguage.googleapis.com',
        '/v1beta/models/$currentModel:generateContent',
        {'key': _geminiApiKey},
      );

      try {
        final response = await http
            .post(
              url,
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'contents': contents,
                'generationConfig': {
                  'temperature': 0.5,
                  'maxOutputTokens':
                      2500, // Aumentado para permitir respuestas largas
                },
              }),
            )
            .timeout(const Duration(seconds: 30));

        // Si hay alta demanda (503) o el modelo no existe (404), intentamos con el siguiente de la lista
        if (response.statusCode == 503 || response.statusCode == 404) {
          if (i < _modelos.length - 1) {
            await Future.delayed(Duration(milliseconds: retryDelayMs));
            retryDelayMs *= 2;
            continue;
          }
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          final errorData = jsonDecode(utf8.decode(response.bodyBytes));
          final error = errorData is Map<String, dynamic>
              ? errorData['error'] as Map<String, dynamic>?
              : null;
          throw GeminiApiException(
            response.statusCode,
            error?['message'] as String?,
          );
        }

        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is! Map<String, dynamic>) {
          throw const FormatException(
            'Gemini devolvió una respuesta no válida.',
          );
        }
        final candidates = data['candidates'] as List<dynamic>?;
        if (candidates == null || candidates.isEmpty) {
          throw const FormatException('Gemini no generó una respuesta.');
        }

        final first = candidates.first as Map<String, dynamic>;
        final content = first['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List<dynamic>?;
        final text = parts
            ?.whereType<Map<String, dynamic>>()
            .map((part) => part['text'])
            .whereType<String>()
            .join('\n');

        if (text == null || text.trim().isEmpty) {
          throw const FormatException('Gemini devolvió una respuesta vacía.');
        }

        return text.trim(); // Retorna el éxito y rompe el ciclo
      } catch (e) {
        // Si hay error de red o timeout, pasamos al siguiente modelo
        if ((e is http.ClientException || e is TimeoutException) &&
            i < _modelos.length - 1) {
          await Future.delayed(Duration(milliseconds: retryDelayMs));
          retryDelayMs *= 2;
          continue;
        }
        // Si ya probamos el último modelo (3.5-flash-lite) y también falló, lanzamos el error
        if (i == _modelos.length - 1) {
          rethrow;
        }
      }
    }
    throw const FormatException(
      'No se pudo conectar tras intentar con todos los modelos.',
    );
  }
}

class GeminiApiException implements Exception {
  const GeminiApiException(this.statusCode, [this.message]);

  final int statusCode;
  final String? message;
}

class PokedexApp extends StatelessWidget {
  const PokedexApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF090D16);
    return MaterialApp(
      title: 'Pokédex // NEXUS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: const Color(0xFF00F5D4),
          surface: background,
        ),
        fontFamily: 'monospace',
        inputDecorationTheme: InputDecorationTheme(
          hintStyle: const TextStyle(color: Color(0xFF64748B)),
          labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
          prefixIconColor: const Color(0xFF00F5D4),
          filled: true,
          fillColor: const Color(0xFF0B1220),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF263449)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF263449)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF00F5D4)),
          ),
        ),
      ),
      home: const _PokedexShell(),
    );
  }
}

class _PokedexShell extends StatefulWidget {
  const _PokedexShell();

  @override
  State<_PokedexShell> createState() => _PokedexShellState();
}

class _PokedexShellState extends State<_PokedexShell> {
  int _selectedTab = 0;
  bool _gameVisited = false;
  bool _rankingsVisited = false;
  bool _musicEnabled = false;
  bool _audioUnavailable = false;
  int _musicRequestSequence = 0;
  final AudioPlayer _musicPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    unawaited(_startMusic());
  }

  @override
  void dispose() {
    unawaited(_musicPlayer.dispose());
    super.dispose();
  }

  Future<void> _startMusic({bool fromUserGesture = false}) async {
    final requestSequence = ++_musicRequestSequence;
    try {
      await _musicPlayer.setReleaseMode(ReleaseMode.loop);
      if (!mounted || requestSequence != _musicRequestSequence) return;
      await _musicPlayer.setVolume(1.0);
      if (!mounted || requestSequence != _musicRequestSequence) return;
      await _musicPlayer.play(
        BytesSource(
          _createToneWav(
            const [110, 164.81, 220, 164.81, 130.81, 196, 261.63, 196],
            samplesPerNote: 11025,
            amplitude: 0.12,
          ),
          mimeType: 'audio/wav',
        ),
      );
      if (mounted && requestSequence == _musicRequestSequence) {
        setState(() => _musicEnabled = true);
      }
    } on AudioPlayerException {
      _handleMusicStartFailure(fromUserGesture);
    } on PlatformException {
      _handleMusicStartFailure(fromUserGesture);
    }
  }

  void _handleMusicStartFailure(bool fromUserGesture) {
    if (!mounted) return;
    if (fromUserGesture) {
      _markAudioUnavailable();
    } else {
      setState(() => _musicEnabled = false);
    }
  }

  void _markAudioUnavailable() {
    if (!mounted) return;
    setState(() {
      _audioUnavailable = true;
      _musicEnabled = false;
    });
  }

  Future<void> _toggleMusic() async {
    if (_audioUnavailable) return;
    if (_musicEnabled) {
      _musicRequestSequence++;
      try {
        await _musicPlayer.stop();
        if (mounted) setState(() => _musicEnabled = false);
      } on AudioPlayerException {
        _markAudioUnavailable();
      } on PlatformException {
        _markAudioUnavailable();
      }
    } else {
      await _startMusic(fromUserGesture: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _AppTopBar(
              musicEnabled: _musicEnabled,
              audioUnavailable: _audioUnavailable,
              onToggleMusic: _toggleMusic,
            ),
            Expanded(
              child: IndexedStack(
                index: _selectedTab,
                children: [
                  const PokemonPage(),
                  _gameVisited
                      ? const _PokemonQuizPage()
                      : const SizedBox.shrink(),
                  _rankingsVisited
                      ? const _PokemonRankingsPage()
                      : const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          setState(() {
            _selectedTab = index;
            if (index == 1) _gameVisited = true;
            if (index == 2) _rankingsVisited = true;
          });
        },
        backgroundColor: const Color(0xFF090D16),
        indicatorColor: _neonCyan.withValues(alpha: 0.12),
        height: 72,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            selectedIcon: Icon(Icons.grid_view_rounded, color: _neonCyan),
            label: 'Pokédex',
          ),
          NavigationDestination(
            icon: Icon(Icons.quiz_outlined),
            selectedIcon: Icon(Icons.quiz_rounded, color: _neonPurple),
            label: 'Minijuego',
          ),
          NavigationDestination(
            icon: Icon(Icons.leaderboard_outlined),
            selectedIcon: Icon(Icons.leaderboard_rounded, color: _neonGreen),
            label: 'Rankings',
          ),
        ],
      ),
    );
  }
}

class _PokemonRankingsPage extends StatefulWidget {
  const _PokemonRankingsPage();

  @override
  State<_PokemonRankingsPage> createState() => _PokemonRankingsPageState();
}

class _PokemonRankingsPageState extends State<_PokemonRankingsPage> {
  static const int _pokemonCount = 1025;
  static const int _topCount = 20;
  static const int _requestConcurrency = 8;
  static const List<_RankingCategory> _categories = [
    _RankingCategory(
      label: 'Lo Mejor de lo Mejor',
      statKey: null,
      color: _neonPurple,
    ),
    _RankingCategory(label: 'Ataque', statKey: 'attack', color: _neonRed),
    _RankingCategory(label: 'HP', statKey: 'hp', color: _neonGreen),
    _RankingCategory(label: 'Defensa', statKey: 'defense', color: _neonCyan),
    _RankingCategory(label: 'Velocidad', statKey: 'speed', color: _neonPurple),
  ];

  final PokemonService _service = PokemonService();
  List<Pokemon> _pokemon = const [];
  int _selectedCategory = 0;
  int _loadedCount = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPokemon());
  }

  Future<void> _loadPokemon() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _loadedCount = 0;
    });

    final results = <Pokemon>[];
    var nextId = 1;

    Future<void> worker() async {
      while (mounted && _isLoading) {
        final id = nextId++;
        if (id > _pokemonCount) return;
        final pokemon = await _service.fetchPokemon('$id');
        if (!mounted || !_isLoading) return;
        results.add(pokemon);
        final completed = results.length;
        if (completed % 20 == 0 || completed == _pokemonCount) {
          setState(() => _loadedCount = completed);
        }
      }
    }

    try {
      await Future.wait(List.generate(_requestConcurrency, (_) => worker()));
      if (!mounted) return;
      setState(() {
        _pokemon = results;
        _loadedCount = results.length;
        _isLoading = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.response?.statusCode == 429
            ? 'PokeAPI limitó temporalmente las consultas. Espera un momento y vuelve a intentarlo.'
            : 'No se pudieron cargar los datos del ranking. Comprueba tu conexión e inténtalo de nuevo.';
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'PokeAPI devolvió datos con un formato inesperado.';
      });
    }
  }

  List<Pokemon> get _rankedPokemon {
    final category = _categories[_selectedCategory];
    final ranked = List<Pokemon>.of(_pokemon);
    ranked.sort((first, second) {
      final comparison = _statValue(
        second,
        category,
      ).compareTo(_statValue(first, category));
      return comparison != 0 ? comparison : first.id.compareTo(second.id);
    });
    return ranked.take(_topCount).toList();
  }

  int _statValue(Pokemon pokemon, _RankingCategory category) {
    final statKey = category.statKey;
    if (statKey != null) return pokemon.baseStats[statKey] ?? 0;
    return pokemon.baseStats.values.fold<int>(0, (sum, value) => sum + value);
  }

  int _maximumValue(_RankingCategory category) {
    var maximum = 1;
    for (final pokemon in _pokemon) {
      maximum = max(maximum, _statValue(pokemon, category));
    }
    return maximum;
  }

  void _showPokemonDetails(Pokemon pokemon, int position) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF0E1623),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _neonCyan.withValues(alpha: 0.55)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 650),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'RANK #$position  //  ID #${pokemon.id.toString().padLeft(3, '0')}',
                  style: const TextStyle(
                    color: _neonCyan,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 8),
                _Artwork(imageUrl: pokemon.imageUrl, size: 170),
                Text(
                  _capitalize(pokemon.name),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 25,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in pokemon.types) _TypeBadge(type: type),
                  ],
                ),
                const SizedBox(height: 18),
                for (final entry in pokemon.baseStats.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _statLabel(entry.key),
                            style: const TextStyle(color: Color(0xFF94A3B8)),
                          ),
                        ),
                        Text(
                          '${entry.value}',
                          style: const TextStyle(
                            color: _neonGreen,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('CERRAR'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statLabel(String key) => switch (key) {
    'hp' => 'HP',
    'attack' => 'Ataque',
    'defense' => 'Defensa',
    'special-attack' => 'Ataque especial',
    'special-defense' => 'Defensa especial',
    'speed' => 'Velocidad',
    _ => key,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned(
              top: -180,
              right: -130,
              child: _GlowOrb(color: _neonPurple, size: 380),
            ),
            const Positioned(
              bottom: -190,
              left: -140,
              child: _GlowOrb(color: _neonCyan, size: 390),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _PanelHeading(
                        eyebrow: 'GLOBAL POWER INDEX',
                        title: 'Rankings Pokémon',
                        icon: Icons.leaderboard_rounded,
                        accent: _neonGreen,
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 48,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _categories.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final category = _categories[index];
                            final selected = index == _selectedCategory;
                            return ChoiceChip(
                              label: Text(category.label),
                              selected: selected,
                              onSelected: _isLoading
                                  ? null
                                  : (_) => setState(
                                      () => _selectedCategory = index,
                                    ),
                              labelStyle: TextStyle(
                                color: selected
                                    ? category.color
                                    : const Color(0xFFCBD5E1),
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                              selectedColor: category.color.withValues(
                                alpha: 0.14,
                              ),
                              backgroundColor: const Color(0xFF0E1623),
                              side: BorderSide(
                                color: category.color.withValues(
                                  alpha: selected ? 0.75 : 0.3,
                                ),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(child: _buildRankingList()),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankingList() {
    if (_isLoading) {
      return Center(
        child: _HudPanel(
          accent: _neonCyan,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: _neonCyan),
              const SizedBox(height: 18),
              Text(
                'ANALIZANDO POKÉDEX  $_loadedCount / $_pokemonCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _neonCyan,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'La primera consulta descarga estadísticas para generar rankings precisos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: _HudPanel(
          accent: _neonRed,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_tethering_error_rounded,
                color: _neonRed,
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFCBD5E1)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadPokemon,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('REINTENTAR'),
              ),
            ],
          ),
        ),
      );
    }

    final category = _categories[_selectedCategory];
    final ranked = _rankedPokemon;
    final maxValue = _maximumValue(category);
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: ranked.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final pokemon = ranked[index];
        final position = index + 1;
        final value = _statValue(pokemon, category);
        final medalColor = switch (position) {
          1 => const Color(0xFFFFD54F),
          2 => const Color(0xFFCFD8DC),
          3 => const Color(0xFFCD7F32),
          _ => category.color,
        };
        return _RankingPokemonCard(
          pokemon: pokemon,
          position: position,
          value: value,
          maxValue: maxValue,
          category: category,
          medalColor: medalColor,
          statLabel: category.statKey == null
              ? 'TOTAL'
              : category.label.toUpperCase(),
          onTap: () => _showPokemonDetails(pokemon, position),
        );
      },
    );
  }
}

class _RankingCategory {
  const _RankingCategory({
    required this.label,
    required this.statKey,
    required this.color,
  });

  final String label;
  final String? statKey;
  final Color color;
}

class _RankingPokemonCard extends StatelessWidget {
  const _RankingPokemonCard({
    required this.pokemon,
    required this.position,
    required this.value,
    required this.maxValue,
    required this.category,
    required this.medalColor,
    required this.statLabel,
    required this.onTap,
  });

  final Pokemon pokemon;
  final int position;
  final int value;
  final int maxValue;
  final _RankingCategory category;
  final Color medalColor;
  final String statLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: _HudPanel(
        accent: position <= 3 ? medalColor : category.color,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              child: Column(
                children: [
                  Icon(
                    position <= 3
                        ? Icons.emoji_events_rounded
                        : Icons.military_tech_rounded,
                    color: medalColor,
                    size: 22,
                  ),
                  Text(
                    '#$position',
                    style: TextStyle(
                      color: medalColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Artwork(imageUrl: pokemon.imageUrl, size: 66),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_capitalize(pokemon.name)}  #${pokemon.id.toString().padLeft(3, '0')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      for (final type in pokemon.types) _TypeBadge(type: type),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (value / maxValue).clamp(0.0, 1.0),
                      minHeight: 5,
                      color: category.color,
                      backgroundColor: const Color(0xFF263244),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    color: category.color,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  statLabel,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _AppTopBar extends StatelessWidget {
  const _AppTopBar({
    required this.musicEnabled,
    required this.audioUnavailable,
    required this.onToggleMusic,
  });

  final bool musicEnabled;
  final bool audioUnavailable;
  final VoidCallback onToggleMusic;

  @override
  Widget build(BuildContext context) => Container(
    height: 66,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: const BoxDecoration(
      color: Color(0xE6090D16),
      border: Border(bottom: BorderSide(color: Color(0x3328E9F3))),
    ),
    child: Row(
      children: [
        const Icon(Icons.hexagon_rounded, color: _neonCyan, size: 28),
        const SizedBox(width: 10),
        const Text(
          'NEXUS',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            fontSize: 17,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          '// ROTOM-DEX',
          style: TextStyle(
            color: _neonCyan,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            fontSize: 10,
          ),
        ),
        const Spacer(),
        IconButton(
          onPressed: audioUnavailable ? null : onToggleMusic,
          tooltip: audioUnavailable
              ? 'Audio no disponible'
              : musicEnabled
              ? 'Silenciar música'
              : 'Activar música',
          icon: Icon(
            musicEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            color: audioUnavailable
                ? const Color(0xFF475569)
                : musicEnabled
                ? _neonGreen
                : _neonCyan,
          ),
        ),
      ],
    ),
  );
}

class PokemonPage extends StatefulWidget {
  const PokemonPage({super.key});

  @override
  State<PokemonPage> createState() => _PokemonPageState();
}

class _PokemonPageState extends State<PokemonPage> {
  static const _maxPokemonId = 1025;

  final PokemonService _service = PokemonService();
  final TextEditingController _searchController = TextEditingController();
  final Random _random = Random();

  int _currentPokemonId = 1;
  Pokemon? _pokemon;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isNotFound = false;
  int _requestSequence = 0;
  String _flavorText = 'Consultando archivo de especie...';
  bool _isFlavorLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPokemon('1');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPokemon(String identifier) async {
    final requestSequence = ++_requestSequence;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isNotFound = false;
      _isFlavorLoading = true;
      _flavorText = 'Consultando archivo de especie...';
    });

    try {
      final pokemon = await _service.fetchPokemon(identifier);
      if (!mounted || requestSequence != _requestSequence) return;
      setState(() {
        _pokemon = pokemon;
        _currentPokemonId = pokemon.id;
        _isLoading = false;
        _errorMessage = null;
      });
      try {
        final flavor = await _service.fetchSpanishFlavorText(
          pokemon.id.toString(),
        );
        if (!mounted || requestSequence != _requestSequence) return;
        setState(() {
          _flavorText =
              flavor ?? 'No hay un dato curioso disponible en español.';
          _isFlavorLoading = false;
        });
      } on DioException {
        if (!mounted || requestSequence != _requestSequence) return;
        setState(() {
          _flavorText = 'No se pudo cargar el dato curioso.';
          _isFlavorLoading = false;
        });
      } on FormatException {
        if (!mounted || requestSequence != _requestSequence) return;
        setState(() {
          _flavorText = 'No se pudo interpretar el dato curioso.';
          _isFlavorLoading = false;
        });
      }
    } on DioException catch (error) {
      if (!mounted || requestSequence != _requestSequence) return;
      setState(() {
        _isLoading = false;
        _isNotFound = error.response?.statusCode == 404;
        _errorMessage = _isNotFound
            ? 'El nombre o ID ingresado no existe en la base de datos nacional.'
            : 'No pudimos conectar con la Pokédex. Comprueba tu conexión e inténtalo de nuevo.';
      });
    } on FormatException {
      if (!mounted || requestSequence != _requestSequence) return;
      setState(() {
        _isLoading = false;
        _isNotFound = false;
        _errorMessage =
            'La respuesta recibida no es válida. Inténtalo de nuevo.';
      });
    }
  }

  void _showValidationError(String message) {
    _requestSequence++;
    setState(() {
      _isLoading = false;
      _isNotFound = false;
      _errorMessage = message;
    });
  }

  void _searchPokemon() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty || !RegExp(r'^[a-z0-9-]+$').hasMatch(query)) {
      _showValidationError('Escribe un nombre o un ID válido.');
      return;
    }

    final id = int.tryParse(query);
    if (id != null && (id < 1 || id > _maxPokemonId)) {
      _showValidationError('El ID debe estar entre 1 y $_maxPokemonId.');
      return;
    }

    _loadPokemon(id?.toString() ?? query);
    FocusScope.of(context).unfocus();
  }

  void _goToPokemon(int id) {
    if (id < 1 || id > _maxPokemonId) return;
    _loadPokemon('$id');
  }

  void _loadRandomPokemon() {
    final id = _random.nextInt(_maxPokemonId) + 1;
    _goToPokemon(id);
  }

  void _returnToFirstPokemon() {
    _searchController.clear();
    _loadPokemon('1');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const _LoadingView()
            : _errorMessage != null || _pokemon == null
            ? _ErrorView(
                message: _errorMessage ?? 'No se pudo cargar el Pokémon.',
                isNotFound: _isNotFound,
                onRetry: _returnToFirstPokemon,
                searchController: _searchController,
                onSearch: _searchPokemon,
              )
            : _PokemonDetails(
                pokemon: _pokemon!,
                currentPokemonId: _currentPokemonId,
                onPrevious: () => _goToPokemon(_currentPokemonId - 1),
                onNext: () => _goToPokemon(_currentPokemonId + 1),
                onRandom: _loadRandomPokemon,
                searchController: _searchController,
                onSearch: _searchPokemon,
                flavorText: _flavorText,
                isFlavorLoading: _isFlavorLoading,
              ),
      ),
    );
  }
}

class _PokemonDetails extends StatelessWidget {
  const _PokemonDetails({
    required this.pokemon,
    required this.currentPokemonId,
    required this.onPrevious,
    required this.onNext,
    required this.onRandom,
    required this.searchController,
    required this.onSearch,
    required this.flavorText,
    required this.isFlavorLoading,
  });

  final Pokemon pokemon;
  final int currentPokemonId;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onRandom;
  final TextEditingController searchController;
  final VoidCallback onSearch;
  final String flavorText;
  final bool isFlavorLoading;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        final content = isDesktop
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 11, child: _buildMainPanel(isDesktop: true)),
                  const SizedBox(width: 20),
                  Expanded(flex: 9, child: _buildStatsPanel()),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMainPanel(isDesktop: false),
                  const SizedBox(height: 18),
                  _buildStatsPanel(),
                ],
              );

        return Stack(
          children: [
            Positioned(
              top: -170,
              right: -130,
              child: _GlowOrb(color: _neonPurple, size: 380),
            ),
            Positioned(
              bottom: -220,
              left: -140,
              child: _GlowOrb(color: _neonCyan, size: 420),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          isDesktop ? 28 : 16,
                          16,
                          isDesktop ? 28 : 16,
                          28,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isDesktop)
                              SizedBox(
                                height: (constraints.maxHeight - 100)
                                    .clamp(620.0, 900.0)
                                    .toDouble(),
                                child: content,
                              )
                            else
                              content,
                            const SizedBox(height: 18),
                            _buildRotomChat(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMainPanel({required bool isDesktop}) {
    final artworkSize = isDesktop ? 220.0 : 240.0;
    final artworkPreview = Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: artworkSize + 24,
          height: artworkSize + 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF111827),
            border: Border.all(
              color: _neonCyan.withValues(alpha: 0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _neonCyan.withValues(alpha: 0.12),
                blurRadius: 65,
                spreadRadius: 8,
              ),
            ],
          ),
        ),
        Container(
          width: artworkSize,
          height: artworkSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFF1B2A3A), Color(0xFF0D1420)],
            ),
            border: Border.all(color: _neonCyan.withValues(alpha: 0.5)),
          ),
        ),
        Positioned(
          top: 12,
          child: Text(
            'NO. ${pokemon.id.toString().padLeft(3, '0')}',
            style: const TextStyle(
              color: _neonCyan,
              fontSize: 10,
              letterSpacing: 2.4,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _Artwork(imageUrl: pokemon.imageUrl, size: artworkSize),
        Positioned(
          bottom: 10,
          child: Container(
            width: 54,
            height: 4,
            decoration: BoxDecoration(
              color: _neonCyan,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: _neonCyan.withValues(alpha: 0.8),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
        ),
      ],
    );
    return _HudPanel(
      accent: _neonCyan,
      padding: EdgeInsets.all(isDesktop ? 28 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelHeading(
            eyebrow: 'DATABASE ACCESS',
            title: 'Pokémon Explorer',
            icon: Icons.radar_rounded,
            accent: _neonCyan,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => onSearch(),
                  decoration: const InputDecoration(
                    hintText: 'Ingresa nombre o ID...',
                    prefixIcon: Icon(Icons.terminal_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: onSearch,
                style: FilledButton.styleFrom(
                  backgroundColor: _neonCyan,
                  foregroundColor: const Color(0xFF061217),
                  minimumSize: const Size(52, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Icon(Icons.search_rounded),
              ),
            ],
          ),
          SizedBox(height: isDesktop ? 22 : 20),
          if (isDesktop)
            Expanded(child: artworkPreview)
          else
            SizedBox(height: artworkSize + 42, child: artworkPreview),
          const SizedBox(height: 14),
          Text(
            '#${pokemon.id.toString().padLeft(3, '0')}  /  CLASSIFIED SPECIMEN',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _neonCyan,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _capitalize(pokemon.name),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: isDesktop ? 38 : 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              shadows: [
                Shadow(
                  color: _neonPurple.withValues(alpha: 0.55),
                  blurRadius: 24,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 9,
            runSpacing: 9,
            children: pokemon.types
                .map((type) => _TypeBadge(type: type))
                .toList(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _NavigationButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Pokémon anterior',
                onPressed: currentPokemonId > 1 ? onPrevious : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onRandom,
                  icon: const Icon(Icons.casino_outlined, size: 18),
                  label: const Text('ALEATORIO'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2B1452),
                    foregroundColor: _neonPurple,
                    side: const BorderSide(color: _neonPurple, width: 1),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _NavigationButton(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Siguiente Pokémon',
                onPressed: currentPokemonId < 1025 ? onNext : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRotomChat() =>
      _RotomChat(pokemon: pokemon, flavorText: flavorText);

  Widget _buildStatsPanel() {
    final statRows = <(String, String, Color)>[
      ('hp', 'HP', _neonGreen),
      ('attack', 'ATAQUE', _neonRed),
      ('defense', 'DEFENSA', _neonCyan),
      ('speed', 'VELOCIDAD', _neonPurple),
    ];
    return _HudPanel(
      accent: _neonPurple,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelHeading(
            eyebrow: 'LIVE ANALYTICS',
            title: 'Datos de combate',
            icon: Icons.query_stats_rounded,
            accent: _neonPurple,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  icon: Icons.height_rounded,
                  label: 'ALTURA',
                  value: '${pokemon.heightInMeters.toStringAsFixed(1)} m',
                  accent: _neonCyan,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _MetricTile(
                  icon: Icons.fitness_center_rounded,
                  label: 'PESO',
                  value: '${pokemon.weightInKilograms.toStringAsFixed(1)} kg',
                  accent: _neonPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: _neonGreen, size: 18),
              const SizedBox(width: 8),
              const Text(
                'BASE STATS',
                style: TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Text(
                'TOTAL ${pokemon.baseStats.values.fold<int>(0, (a, b) => a + b)}',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          for (final stat in statRows) ...[
            _BaseStatBar(
              label: stat.$2,
              value: pokemon.baseStats[stat.$1] ?? 0,
              color: stat.$3,
            ),
            const SizedBox(height: 19),
          ],
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFF0A131E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _neonCyan.withValues(alpha: 0.28)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome_rounded, color: _neonCyan),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DATO DE LA POKÉDEX',
                        style: TextStyle(
                          color: _neonCyan,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 7),
                      if (isFlavorLoading)
                        const LinearProgressIndicator(
                          minHeight: 3,
                          color: _neonCyan,
                          backgroundColor: Color(0xFF1B293A),
                        )
                      else
                        Text(
                          flavorText,
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 11,
                            height: 1.45,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0A131E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1D2B3E)),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_moon_outlined, color: _neonGreen, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Lectura de datos en tiempo real desde PokeAPI.',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RotomChat extends StatefulWidget {
  const _RotomChat({required this.pokemon, required this.flavorText});

  final Pokemon pokemon;
  final String flavorText;

  @override
  State<_RotomChat> createState() => _RotomChatState();
}

class _RotomChatState extends State<_RotomChat> {
  final RotomDexService _service = RotomDexService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isSending = false;
  int _requestSequence = 0;

  @override
  void didUpdateWidget(covariant _RotomChat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pokemon.id != widget.pokemon.id) {
      _requestSequence++;
      _messages.clear();
      _controller.clear();
      _isSending = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _isSending) return;
    final requestSequence = ++_requestSequence;
    final history = _messages
        .where((message) => !message.isError)
        .toList()
        .reversed
        .take(8)
        .toList()
        .reversed
        .map((message) => {'role': message.role, 'content': message.text})
        .toList();

    setState(() {
      _messages.add(_ChatMessage(role: 'user', text: question));
      _controller.clear();
      _isSending = true;
    });
    _scrollToLatest();

    try {
      final answer = await _service.ask(
        pokemon: widget.pokemon,
        flavorText: widget.flavorText,
        question: question,
        history: history,
      );
      if (!mounted || requestSequence != _requestSequence) return;
      setState(() {
        _messages.add(_ChatMessage(role: 'assistant', text: answer));
        _isSending = false;
      });
    } on GeminiApiException catch (error) {
      if (!mounted || requestSequence != _requestSequence) return;
      final message = switch (error.statusCode) {
        400 =>
          'Gemini rechazó la solicitud (400). ${error.message ?? 'Revisa el formato de la petición.'}',
        401 =>
          'Gemini rechazó la API key (401). Verifica que la clave en el código sea válida. ${error.message ?? ''}',
        403 =>
          'La clave no tiene permiso para usar Gemini (403). Revisa las restricciones de la clave. ${error.message ?? ''}',
        404 =>
          'El modelo o endpoint no está disponible (404). ${error.message ?? ''}',
        429 =>
          'Se alcanzó el límite de uso de Gemini (429). Inténtalo más tarde. ${error.message ?? ''}',
        _ =>
          'Gemini respondió con el código ${error.statusCode}. ${error.message ?? ''}',
      };
      _showRequestError(message);
    } on http.ClientException {
      if (!mounted || requestSequence != _requestSequence) return;
      _showRequestError('No se pudo conectar con Gemini. Revisa tu conexión.');
    } on TimeoutException {
      if (!mounted || requestSequence != _requestSequence) return;
      _showRequestError(
        'Gemini tardó demasiado en responder. Inténtalo otra vez.',
      );
    } on FormatException catch (error) {
      if (!mounted || requestSequence != _requestSequence) return;
      _showRequestError(error.message);
    } on StateError catch (error) {
      if (!mounted || requestSequence != _requestSequence) return;
      _showRequestError(error.message.toString());
    }
    _scrollToLatest();
  }

  void _showRequestError(String message) {
    setState(() {
      if (_messages.isNotEmpty && _messages.last.role == 'user') {
        _messages.removeLast();
      }
      _messages.add(
        _ChatMessage(role: 'assistant', text: message, isError: true),
      );
      _isSending = false;
    });
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 360,
      child: _HudPanel(
        accent: _neonPurple,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PanelHeading(
              eyebrow: 'AI ASSISTANT // GEMINI',
              title: 'Rotom-Dex',
              icon: Icons.smart_toy_rounded,
              accent: _neonPurple,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _messages.isEmpty
                  ? const Center(
                      child: Text(
                        'Pregunta sobre tipos, evoluciones, estadísticas o curiosidades.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _messages.length + (_isSending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return const Padding(
                            padding: EdgeInsets.all(10),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _neonPurple,
                                ),
                              ),
                            ),
                          );
                        }
                        final message = _messages[index];
                        final isUser = message.role == 'user';
                        final color = message.isError
                            ? _neonRed
                            : isUser
                            ? _neonCyan
                            : _neonPurple;
                        return Align(
                          alignment: isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 680),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: color.withValues(alpha: 0.32),
                              ),
                            ),
                            child: Text(
                              message.text,
                              style: TextStyle(
                                color: message.isError
                                    ? _neonRed
                                    : const Color(0xFFE2E8F0),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_isSending,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: const InputDecoration(
                      hintText: 'Pregunta a Rotom-Dex...',
                      prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: _isSending ? null : _sendMessage,
                  tooltip: 'Enviar pregunta',
                  style: IconButton.styleFrom(
                    backgroundColor: _neonPurple,
                    foregroundColor: const Color(0xFF160A22),
                  ),
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.text,
    this.isError = false,
  });

  final String role;
  final String text;
  final bool isError;
}

class _PokemonQuizPage extends StatefulWidget {
  const _PokemonQuizPage();

  @override
  State<_PokemonQuizPage> createState() => _PokemonQuizPageState();
}

class _PokemonQuizPageState extends State<_PokemonQuizPage> {
  final PokemonService _service = PokemonService();
  final Random _random = Random();
  final AudioPlayer _audioPlayer = AudioPlayer();

  static const int _initialSeconds = 60;

  Pokemon? _answerPokemon;
  List<Pokemon> _options = const [];
  Timer? _timer;
  bool _isLoading = false;
  bool _hasStarted = false;
  bool _isGameOver = false;
  bool _answered = false;
  bool _isCorrect = false;
  int? _selectedPokemonId;
  int _streak = 0;
  int _bestStreak = 0;
  int _gameBestStreak = 0;
  int _totalCorrect = 0;
  int _remainingSeconds = _initialSeconds;
  int _roundSequence = 0;
  String? _error;
  bool _audioErrorShown = false;

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }

  Future<void> _playEffect(List<double> notes) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(
        BytesSource(_createToneWav(notes), mimeType: 'audio/wav'),
      );
    } on AudioPlayerException {
      _showAudioUnavailable();
    } on PlatformException {
      _showAudioUnavailable();
    }
  }

  void _showAudioUnavailable() {
    if (!mounted || _audioErrorShown) return;
    _audioErrorShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('El audio no está disponible en este dispositivo.'),
      ),
    );
  }

  void _startGame() {
    _timer?.cancel();
    setState(() {
      _hasStarted = true;
      _isGameOver = false;
      _remainingSeconds = _initialSeconds;
      _streak = 0;
      _gameBestStreak = 0;
      _totalCorrect = 0;
      _answerPokemon = null;
      _options = const [];
      _error = null;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _isGameOver) return;
      if (_remainingSeconds <= 1) {
        _finishGame();
      } else {
        setState(() => _remainingSeconds--);
      }
    });
    unawaited(_loadRound());
  }

  void _finishGame() {
    _timer?.cancel();
    _timer = null;
    _roundSequence++;
    if (!mounted) return;
    setState(() {
      _remainingSeconds = 0;
      _isGameOver = true;
      _isLoading = false;
    });
  }

  Future<void> _loadRound() async {
    if (!_hasStarted || _isGameOver) return;
    final sequence = ++_roundSequence;
    setState(() {
      _isLoading = true;
      _error = null;
      _answered = false;
      _selectedPokemonId = null;
    });

    try {
      final correctId = _random.nextInt(151) + 1;
      final ids = <int>{correctId};
      while (ids.length < 4) {
        ids.add(_random.nextInt(151) + 1);
      }

      final pokemon = await Future.wait(
        ids.map((id) => _service.fetchPokemon('$id')),
      );
      if (!mounted || sequence != _roundSequence) return;
      final options = List<Pokemon>.of(pokemon)..shuffle(_random);
      setState(() {
        _answerPokemon = pokemon.firstWhere((item) => item.id == correctId);
        _options = options;
        _isLoading = false;
      });
    } on DioException {
      if (!mounted || sequence != _roundSequence) return;
      setState(() {
        _isLoading = false;
        _error = 'No pudimos cargar la ronda. Comprueba tu conexión.';
      });
    } on FormatException {
      if (!mounted || sequence != _roundSequence) return;
      setState(() {
        _isLoading = false;
        _error = 'La respuesta de la Pokédex no tiene un formato válido.';
      });
    }
  }

  Future<void> _selectAnswer(Pokemon selected) async {
    if (!_hasStarted ||
        _isGameOver ||
        _isLoading ||
        _answered ||
        _answerPokemon == null) {
      return;
    }
    final answer = _answerPokemon!;
    final correct = selected.id == answer.id;
    final sequence = _roundSequence;
    setState(() {
      _answered = true;
      _isCorrect = correct;
      _selectedPokemonId = selected.id;
      if (correct) {
        _streak++;
        _totalCorrect++;
        _remainingSeconds += 2;
        if (_streak > _gameBestStreak) _gameBestStreak = _streak;
        if (_streak > _bestStreak) _bestStreak = _streak;
      } else {
        _streak = 0;
        _remainingSeconds -= 3;
      }
    });
    unawaited(
      _playEffect(correct ? const [660, 880, 1320] : const [440, 330, 220]),
    );
    if (_remainingSeconds <= 0) {
      _finishGame();
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted || _isGameOver || sequence != _roundSequence) return;
    unawaited(_loadRound());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned(
              top: -180,
              right: -120,
              child: _GlowOrb(color: _neonPurple, size: 380),
            ),
            const Positioned(
              bottom: -190,
              left: -120,
              child: _GlowOrb(color: _neonCyan, size: 380),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _buildGameContent(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameContent() {
    if (_isGameOver) return _buildGameOver();
    if (!_hasStarted) return _buildLobby();
    if (_error != null) {
      return _HudPanel(
        accent: _neonRed,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_tethering_error_rounded,
              color: _neonRed,
              size: 46,
            ),
            const SizedBox(height: 14),
            Text(
              _error ?? 'No se pudo iniciar la ronda.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFCBD5E1)),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loadRound,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('REINTENTAR'),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop =
            constraints.maxWidth >= 760 && constraints.maxHeight >= 640;
        return SingleChildScrollView(
          child: _HudPanel(
            accent: _neonPurple,
            padding: EdgeInsets.all(desktop ? 28 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _PanelHeading(
                  eyebrow: 'TIME ATTACK // 60 SECONDS',
                  title: 'Siluetas Contra Reloj',
                  icon: Icons.bolt_rounded,
                  accent: _neonPurple,
                ),
                const SizedBox(height: 20),
                _buildTimerAndScore(desktop),
                const SizedBox(height: 20),
                if (desktop)
                  SizedBox(
                    height: 390,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: _isLoading || _answerPokemon == null
                              ? const _LoadingView()
                              : _buildQuizArtwork(300),
                        ),
                        const SizedBox(width: 28),
                        Expanded(flex: 4, child: _buildAnswerPanel()),
                      ],
                    ),
                  )
                else ...[
                  SizedBox(
                    height: 270,
                    child: _isLoading || _answerPokemon == null
                        ? const _LoadingView()
                        : _buildQuizArtwork(205),
                  ),
                  const SizedBox(height: 16),
                  _buildAnswerPanel(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLobby() => Center(
    child: _HudPanel(
      accent: _neonPurple,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _PanelHeading(
            eyebrow: 'MINIJUEGO // MODO RUSH',
            title: 'Siluetas Contra Reloj',
            icon: Icons.bolt_rounded,
            accent: _neonPurple,
          ),
          const SizedBox(height: 22),
          const Icon(
            Icons.hourglass_bottom_rounded,
            color: _neonCyan,
            size: 62,
          ),
          const SizedBox(height: 12),
          const Text(
            'Adivina tantos Pokémon como puedas antes de que se acabe el tiempo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFCBD5E1), height: 1.5),
          ),
          const SizedBox(height: 22),
          _ScoreBadge(
            label: 'RÉCORD DE RACHA',
            score: _bestStreak,
            color: _neonPurple,
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: _startGame,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('INICIAR RETO 60s'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF17352E),
                foregroundColor: _neonGreen,
                side: const BorderSide(color: _neonGreen),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildGameOver() => Center(
    child: _HudPanel(
      accent: _neonRed,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_off_rounded, color: _neonRed, size: 58),
          const SizedBox(height: 12),
          const Text(
            'TIEMPO AGOTADO',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _neonRed,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              _ScoreBadge(
                label: 'ACIERTOS',
                score: _totalCorrect,
                color: _neonCyan,
              ),
              _ScoreBadge(
                label: 'RACHA MÁXIMA',
                score: _gameBestStreak,
                color: _neonPurple,
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _startGame,
            icon: const Icon(Icons.replay_rounded),
            label: const Text('JUGAR DE NUEVO'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF17352E),
              foregroundColor: _neonGreen,
              side: const BorderSide(color: _neonGreen),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildTimerAndScore(bool desktop) {
    final timerColor = _remainingSeconds <= 15 ? _neonRed : _neonGreen;
    final badges = Wrap(
      alignment: desktop ? WrapAlignment.end : WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        _ScoreBadge(label: 'RACHA', score: _streak, color: _neonCyan),
        _ScoreBadge(
          label: 'ACIERTOS',
          score: _totalCorrect,
          color: _neonPurple,
        ),
      ],
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.timer_rounded, color: timerColor, size: 28),
            const SizedBox(width: 8),
            Text(
              '$_remainingSeconds',
              style: TextStyle(
                color: timerColor,
                fontSize: 36,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
              ),
            ),
            const Text(
              ' s',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(width: 10),
        Flexible(child: badges),
      ],
    );
  }

  Widget _buildQuizArtwork(double imageSize) {
    final answer = _answerPokemon!;
    final image = Image.network(
      answer.imageUrl,
      width: imageSize,
      height: imageSize,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const Icon(
        Icons.catching_pokemon_rounded,
        size: 100,
        color: _neonCyan,
      ),
    );
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Center(
            child: Container(
              width: imageSize + 42,
              height: imageSize + 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFF69788D), Color(0xFF34445A)],
                ),
                border: Border.all(color: _neonCyan, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: _neonCyan.withValues(alpha: 0.26),
                    blurRadius: 36,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOut,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
                child: _answered
                    ? Image.network(
                        answer.imageUrl,
                        key: const ValueKey('revealed-pokemon'),
                        width: imageSize,
                        height: imageSize,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.catching_pokemon_rounded,
                              size: 100,
                              color: _neonGreen,
                            ),
                      )
                    : ColorFiltered(
                        key: const ValueKey('pokemon-silhouette'),
                        colorFilter: const ColorFilter.mode(
                          Colors.black,
                          BlendMode.srcIn,
                        ),
                        child: image,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _answered
              ? _isCorrect
                    ? '¡CORRECTO! ES ${answer.name.toUpperCase()}'
                    : '¡INCORRECTO! ERA ${answer.name.toUpperCase()}'
              : '¿QUIÉN SE ESCONDE EN LA SILUETA?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _answered
                ? _isCorrect
                      ? _neonGreen
                      : _neonRed
                : _neonCyan,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildAnswerPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_isLoading || _answerPokemon == null)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'CARGANDO SIGUIENTE SILUETA…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _neonCyan,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          )
        else ...[
          const Text(
            'SELECCIONA UNA RESPUESTA',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          for (final pokemon in _options) ...[
            _QuizOptionButton(
              name: _capitalize(pokemon.name),
              isSelected: pokemon.id == _selectedPokemonId,
              isCorrectAnswer: pokemon.id == _answerPokemon?.id,
              answered: _answered,
              onPressed: () => _selectAnswer(pokemon),
            ),
            const SizedBox(height: 10),
          ],
          if (_answered) ...[
            const SizedBox(height: 4),
            Text(
              _isCorrect ? '+2 SEGUNDOS' : '−3 SEGUNDOS',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _isCorrect ? _neonGreen : _neonRed,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ],
        if (_isLoading) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(
            color: _neonCyan,
            backgroundColor: Color(0xFF1E293B),
          ),
        ],
      ],
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({
    required this.label,
    required this.score,
    required this.color,
  });

  final String label;
  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.48)),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '$score',
          style: const TextStyle(
            color: Color(0xFFF1F5F9),
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ],
    ),
  );
}

class _QuizOptionButton extends StatelessWidget {
  const _QuizOptionButton({
    required this.name,
    required this.isSelected,
    required this.isCorrectAnswer,
    required this.answered,
    required this.onPressed,
  });

  final String name;
  final bool isSelected;
  final bool isCorrectAnswer;
  final bool answered;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = answered
        ? isCorrectAnswer
              ? _neonGreen
              : isSelected
              ? _neonRed
              : const Color(0xFF344256)
        : _neonCyan;

    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: answered ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          disabledForegroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.8)),
          backgroundColor: color.withValues(alpha: answered ? 0.1 : 0.045),
          alignment: Alignment.centerLeft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          children: [
            Icon(
              answered && isCorrectAnswer
                  ? Icons.check_circle_outline_rounded
                  : answered && isSelected
                  ? Icons.cancel_outlined
                  : Icons.radio_button_unchecked_rounded,
              size: 17,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _neonCyan = Color(0xFF00F5D4);
const _neonPurple = Color(0xFFB967FF);
const _neonGreen = Color(0xFF7CFF6B);
const _neonRed = Color(0xFFFF4D6D);

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: size / 2,
            spreadRadius: size / 5,
          ),
        ],
      ),
    ),
  );
}

class _HudPanel extends StatelessWidget {
  const _HudPanel({
    required this.accent,
    required this.padding,
    required this.child,
  });

  final Color accent;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: const Color(0xED0E1623),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: accent.withValues(alpha: 0.38)),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.09),
          blurRadius: 30,
          spreadRadius: 1,
        ),
        const BoxShadow(
          color: Color(0x80000000),
          blurRadius: 28,
          offset: Offset(0, 18),
        ),
      ],
    ),
    child: child,
  );
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.accent,
  });

  final String eyebrow;
  final String title;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.42)),
        ),
        child: Icon(icon, color: accent, size: 22),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: TextStyle(
                color: accent,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFFF1F5F9),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.imageUrl, required this.size});

  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: imageUrl.isEmpty
        ? const Icon(
            Icons.catching_pokemon_rounded,
            size: 100,
            color: _neonCyan,
          )
        : Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.image_not_supported_outlined,
              size: 72,
              color: Color(0xFF64748B),
            ),
          ),
  );
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final String type;

  static const _styles = <String, (String, Color)>{
    'grass': ('PLANTA', Color(0xFF7CFF6B)),
    'poison': ('VENENO', Color(0xFFCF75FF)),
    'fire': ('FUEGO', Color(0xFFFF654F)),
    'water': ('AGUA', Color(0xFF45B7FF)),
    'bug': ('BICHO', Color(0xFFC4E83A)),
    'normal': ('NORMAL', Color(0xFFCBD5E1)),
    'electric': ('ELÉCTRICO', Color(0xFFFFDE59)),
    'ground': ('TIERRA', Color(0xFFFFB65C)),
    'fairy': ('HADA', Color(0xFFFF7EB6)),
    'fighting': ('LUCHA', Color(0xFFFF6666)),
    'psychic': ('PSÍQUICO', Color(0xFFFF72B6)),
    'rock': ('ROCA', Color(0xFFD5B98A)),
    'ghost': ('FANTASMA', Color(0xFFAE9AFF)),
    'ice': ('HIELO', Color(0xFF69F0FF)),
    'dragon': ('DRAGÓN', Color(0xFF8C9EFF)),
    'dark': ('SINIESTRO', Color(0xFFA9A0A0)),
    'steel': ('ACERO', Color(0xFFB6C4D2)),
    'flying': ('VOLADOR', Color(0xFF91A9FF)),
  };

  @override
  Widget build(BuildContext context) {
    final style = _styles[type] ?? (type.toUpperCase(), _neonCyan);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: style.$2.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: style.$2.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(color: style.$2.withValues(alpha: 0.12), blurRadius: 12),
        ],
      ),
      child: Text(
        style.$1,
        style: TextStyle(
          color: style.$2,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF0A131E),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: accent.withValues(alpha: 0.35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accent, size: 21),
        const SizedBox(height: 13),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );
}

class _BaseStatBar extends StatelessWidget {
  const _BaseStatBar({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: (value / 255).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: const Color(0xFF1B293A),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 34,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    width: 48,
    child: IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        foregroundColor: _neonCyan,
        disabledForegroundColor: const Color(0xFF3A4758),
        backgroundColor: const Color(0xFF0A131E),
        side: const BorderSide(color: Color(0xFF24505A)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: _HudPanel(
        accent: _neonCyan,
        padding: EdgeInsets.symmetric(horizontal: 48, vertical: 38),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 54,
              height: 54,
              child: CircularProgressIndicator(
                color: _neonCyan,
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 22),
            Text(
              'ESTABLECIENDO CONEXIÓN...',
              style: TextStyle(
                color: _neonCyan,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.isNotFound,
    required this.onRetry,
    required this.searchController,
    required this.onSearch,
  });

  final String message;
  final bool isNotFound;
  final VoidCallback onRetry;
  final TextEditingController searchController;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _HudPanel(
            accent: _neonRed,
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 94,
                  height: 94,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _neonRed.withValues(alpha: 0.08),
                    border: Border.all(
                      color: _neonRed.withValues(alpha: 0.75),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _neonRed.withValues(alpha: 0.32),
                        blurRadius: 32,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.radar_rounded,
                    size: 48,
                    color: _neonRed,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  isNotFound
                      ? '¡POKÉMON SALVAJE\nNO ENCONTRADO!'
                      : 'SIN SEÑAL EN LA\nPOKÉDEX',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _neonRed,
                    fontSize: 18,
                    height: 1.4,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFCBD5E1),
                    height: 1.5,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => onSearch(),
                  decoration: const InputDecoration(
                    hintText: 'Intenta con otro nombre o ID...',
                    prefixIcon: Icon(Icons.terminal_rounded),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('VOLVER AL #001'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3A101F),
                      foregroundColor: _neonRed,
                      side: const BorderSide(color: _neonRed),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _capitalize(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

Uint8List _createToneWav(
  List<double> notes, {
  int samplesPerNote = 3308,
  double amplitude = 0.24,
}) {
  const sampleRate = 22050;
  const bytesPerSample = 2;
  final sampleCount = samplesPerNote * notes.length;
  final wav = Uint8List(44 + sampleCount * bytesPerSample);
  final header = ByteData.sublistView(wav);
  final dataLength = sampleCount * bytesPerSample;

  wav.setRange(0, 4, 'RIFF'.codeUnits);
  header.setUint32(4, 36 + dataLength, Endian.little);
  wav.setRange(8, 12, 'WAVE'.codeUnits);
  wav.setRange(12, 16, 'fmt '.codeUnits);
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * bytesPerSample, Endian.little);
  header.setUint16(32, bytesPerSample, Endian.little);
  header.setUint16(34, 16, Endian.little);
  wav.setRange(36, 40, 'data'.codeUnits);
  header.setUint32(40, dataLength, Endian.little);

  for (var index = 0; index < sampleCount; index++) {
    final noteIndex = index ~/ samplesPerNote;
    final noteSample = index % samplesPerNote;
    final envelope = min(
      1.0,
      min(noteSample / 220, (samplesPerNote - noteSample) / 330),
    );
    final phase = 2 * pi * notes[noteIndex] * noteSample / sampleRate;
    final sample = (sin(phase) * envelope * amplitude * 32767).round();
    header.setInt16(44 + index * bytesPerSample, sample, Endian.little);
  }
  return wav;
}
