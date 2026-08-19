import 'package:autocarnet/features/sharing/domain/invite_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('invite_code (pure)', () {
    test('generateInviteCode always produces 8 unambiguous uppercase characters', () {
      final code = generateInviteCode();
      expect(code.length, 8);
      expect(RegExp(r'^[A-Z0-9]{8}$').hasMatch(code), isTrue);
      // 0/O/1/I/L are deliberately excluded (easy to confuse on a phone).
      expect(code.contains(RegExp('[O0I1L]')), isFalse);
    });

    test('two consecutive generations are (virtually certainly) different', () {
      final codes = List.generate(50, (_) => generateInviteCode()).toSet();
      expect(codes.length, 50);
    });

    test('formatInviteCodeForDisplay inserts a dash after the 4th character', () {
      expect(formatInviteCodeForDisplay('Q7K9M2P4'), 'Q7K9-M2P4');
    });

    test('normalizeInviteCodeInput strips the dash, spaces and lowercases back to uppercase', () {
      expect(normalizeInviteCodeInput('q7k9-m2p4'), 'Q7K9M2P4');
      expect(normalizeInviteCodeInput('  Q7K9 M2P4  '), 'Q7K9M2P4');
      expect(normalizeInviteCodeInput('Q7K9M2P4'), 'Q7K9M2P4');
    });

    test('display formatting and normalization round-trip', () {
      final code = generateInviteCode();
      final displayed = formatInviteCodeForDisplay(code);
      expect(normalizeInviteCodeInput(displayed), code);
    });
  });
}
