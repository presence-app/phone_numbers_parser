import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:phone_numbers_parser/src/metadata/lazy_metadata_loader.dart';
import 'package:test/test.dart';

void main() {
  group('Warm-up and Purge Strategy', () {
    test('full lifecycle: warm-up, optimize, use', () {
      final loader = LazyMetadataLoader.instance;

      // Before warm-up
      final initial = loader.getCacheStats();
      final initialAccessed = initial['accessed'] as int;
      expect(initial['purged'], equals(false));

      // Warm-up: parse some numbers
      PhoneNumber.parse('+14155552671'); // US
      PhoneNumber.parse('+33612345678'); // FR
      PhoneNumber.parse('+441234567890'); // GB

      // After warm-up: tracked but not cached
      final afterWarmup = loader.getCacheStats();
      expect(afterWarmup['accessed'], greaterThan(initialAccessed));
      expect(afterWarmup['purged'], equals(false));

      // Purge: remove unused countries
      loader.purge();

      // After purge: cached and purged
      final afterPurge = loader.getCacheStats();
      expect(afterPurge['purged'], equals(true));
      expect(afterPurge['total'], greaterThan(0));
      expect(afterPurge['total'], lessThan(200)); // Much less than 980

      // Should still work after optimization
      final phone = PhoneNumber.parse('+13105551234'); // US number
      expect(phone.isValid(type: PhoneNumberType.mobile), isTrue);

      // Formatting should work
      final formatted = phone.formatNsn();
      expect(formatted, isNotEmpty);
    });
  });

  group('Backward Compatibility (no purging)', () {
    test('parsing still works without purge', () {
      final numbers = [
        '+14155552671',
        '+33612345678',
        '+441234567890',
      ];

      for (var number in numbers) {
        expect(() => PhoneNumber.parse(number), returnsNormally);
      }
    });

    test('validation still works without purge', () {
      final usPhone = PhoneNumber.parse('+14155552671');
      expect(usPhone.isValid(type: PhoneNumberType.mobile), isTrue);

      final frPhone = PhoneNumber.parse('+33612345678');
      expect(frPhone.isValid(type: PhoneNumberType.mobile), isTrue);
    });
  });

  group('Selective Metadata Loading', () {
    test('initialize(enableFormats: false) disables formats immediately', () {
      // Note: Must be run in isolation as clearCache can't restore original maps
      // This test assumes formats map hasn't been cleared yet
      final loader = LazyMetadataLoader.instance;

      // Initialize with formats disabled
      loader.initialize(enableFormats: false);

      // Parse a number
      final phone = PhoneNumber.parse('+14155552671');

      // Parsing and validation work
      expect(phone.international, isNotEmpty);
      expect(phone.isValid(type: PhoneNumberType.mobile), isTrue);

      // Formatting throws when formats disabled
      expect(
        () => phone.formatNsn(),
        throwsA(isA<PhoneNumberException>()),
      );
    });

    test('selective loading with purge saves more memory', () {
      final loader = LazyMetadataLoader.instance;

      // Warm up with some countries
      PhoneNumber.parse('+14155552671'); // US
      PhoneNumber.parse('+33612345678'); // FR

      // Purge
      loader.purge();

      final stats = loader.getCacheStats();

      // Should have cached data
      expect(stats['total'], greaterThan(0));
      expect(stats['purged'], isTrue);
    });
  });
}
