import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  test('a hotline as written becomes a number a phone can dial', () {
    expect(dialable('(02) 8527-0000'), '0285270000');
    expect(dialable('+63 2 8527 0000'), '+63285270000');
    expect(dialable(' 911 '), '911');
    expect(dialable('0917-000-4821'), '09170004821');
    expect(dialable(''), '');
  });
}
