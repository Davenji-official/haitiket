import 'package:flutter_test/flutter_test.dart';
import 'package:haitiket/i18n.dart';

void main() {
  setUp(() {
    appLang.value = 'fr';
  });

  test('French is the default translation language', () {
    expect(tr('Accueil'), 'Accueil');
  });

  test('known strings are translated into Haitian Creole', () {
    appLang.value = 'ht';
    expect(tr('Accueil'), 'Akèy');
    expect(tr('Mes commandes'), 'Kòmand mwen yo');
  });

  test('unknown strings fall back to the French source string', () {
    appLang.value = 'ht';
    expect(tr('Texte absent du dictionnaire'), 'Texte absent du dictionnaire');
  });
}
