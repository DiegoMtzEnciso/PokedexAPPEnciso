import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/main.dart';

void main() {
  test('maps Pokémon data, artwork, types, and display units', () {
    final pokemon = Pokemon.fromJson({
      'id': 1,
      'name': 'bulbasaur',
      'height': 7,
      'weight': 69,
      'sprites': {
        'front_default': 'https://example.com/sprite.png',
        'other': {
          'official-artwork': {
            'front_default': 'https://example.com/artwork.png',
          },
        },
      },
      'types': [
        {
          'slot': 1,
          'type': {'name': 'grass', 'url': 'https://example.com/grass'},
        },
        {
          'slot': 2,
          'type': {'name': 'poison', 'url': 'https://example.com/poison'},
        },
      ],
    });

    expect(pokemon.id, 1);
    expect(pokemon.name, 'bulbasaur');
    expect(pokemon.imageUrl, 'https://example.com/artwork.png');
    expect(pokemon.types, ['grass', 'poison']);
    expect(pokemon.heightInMeters, 0.7);
    expect(pokemon.weightInKilograms, 6.9);
  });

  test('falls back to the default sprite when artwork is unavailable', () {
    final pokemon = Pokemon.fromJson({
      'id': 1,
      'name': 'bulbasaur',
      'height': 7,
      'weight': 69,
      'sprites': {'front_default': 'https://example.com/sprite.png'},
      'types': [
        {
          'slot': 1,
          'type': {'name': 'grass', 'url': 'https://example.com/grass'},
        },
      ],
    });

    expect(pokemon.imageUrl, 'https://example.com/sprite.png');
  });
}
