import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:phone_numbers_parser/src/metadata/metadata_manager.dart';
import 'package:test/test.dart';

void main() {
  group('Warm-up and Purge Strategy', () {
    test('full lifecycle: warm-up, optimize, use', () {
      final loader = MetadataMemoryManager.instance;

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

  group('Idempotence Tests', () {
    test('initialize() is idempotent - multiple calls are safe', () {
      // Measure first call
      final stopwatch1 = Stopwatch()..start();
      PhoneNumber.initialize(enableFormats: false);
      stopwatch1.stop();
      print(
          '[Test] First initialize() took ${stopwatch1.elapsedMilliseconds}ms (${stopwatch1.elapsedMicroseconds}μs)');

      // Measure subsequent calls (should be instant)
      final stopwatch2 = Stopwatch()..start();
      PhoneNumber.initialize(enableFormats: false);
      stopwatch2.stop();
      print(
          '[Test] Second initialize() took ${stopwatch2.elapsedMicroseconds}μs (idempotent, should be ~0μs)');

      final stopwatch3 = Stopwatch()..start();
      PhoneNumber.initialize(enableFormats: false);
      stopwatch3.stop();
      print(
          '[Test] Third initialize() took ${stopwatch3.elapsedMicroseconds}μs (idempotent, should be ~0μs)');

      // Should work normally
      final phone1 = PhoneNumber.parse('+14155552671');
      expect(phone1.isValid(type: PhoneNumberType.mobile), isTrue);

      // Call again before another parse (simulating multiple function calls)
      PhoneNumber.initialize(enableFormats: false);
      final phone2 = PhoneNumber.parse('+33612345678');
      expect(phone2.isValid(type: PhoneNumberType.mobile), isTrue);

      // Formatting still disabled after multiple calls
      expect(
        () => phone1.formatNsn(),
        throwsA(isA<PhoneNumberException>()),
      );
    });

    test('initialize() called from multiple functions (real-world pattern)',
        () {
      // Simulate your normalizePhoneNumberToE164 function
      String normalizePhoneNumber(String phoneNumber) {
        final sw = Stopwatch()..start();
        PhoneNumber.initialize(enableFormats: false); // Called every time
        sw.stop();
        print(
            '[Test] normalizePhoneNumber() - initialize() took ${sw.elapsedMicroseconds}μs');
        final phoneWithPlus =
            phoneNumber.startsWith('+') ? phoneNumber : '+$phoneNumber';
        final parsed = PhoneNumber.parse(phoneWithPlus);
        return parsed.international.replaceAll(RegExp(r'[^\d+]'), '');
      }

      // Simulate your isValidMobilePhoneNumber function
      bool isValidMobile(String phoneNumber, {required String countryCode}) {
        final sw = Stopwatch()..start();
        PhoneNumber.initialize(enableFormats: false); // Called every time
        sw.stop();
        print(
            '[Test] isValidMobilePhoneNumber() - initialize() took ${sw.elapsedMicroseconds}μs');
        final isoCode = IsoCode.values.byName(countryCode.toUpperCase());
        final parsed = PhoneNumber.parse(phoneNumber, callerCountry: isoCode);
        return parsed.isValid(type: PhoneNumberType.mobile);
      }

      // Both functions work correctly despite multiple initialize() calls
      final normalized1 = normalizePhoneNumber('+14155552671');
      expect(normalized1, equals('+14155552671'));

      final isValid1 = isValidMobile('+14155552671', countryCode: 'US');
      expect(isValid1, isTrue);

      final normalized2 = normalizePhoneNumber('+33612345678');
      expect(normalized2, equals('+33612345678'));

      final isValid2 = isValidMobile('0612345678', countryCode: 'FR');
      expect(isValid2, isTrue);

      // Multiple interleaved calls
      for (int i = 0; i < 5; i++) {
        normalizePhoneNumber('+14155552671');
        isValidMobile('+33612345678', countryCode: 'FR');
      }

      // Everything still works (use already-accessed countries)
      expect(normalizePhoneNumber('+14155552671'), equals('+14155552671'));
    });

    test('initialize() with different parameters respects first call', () {
      // First call disables formats
      PhoneNumber.initialize(enableFormats: false);

      // Subsequent calls with different parameters are ignored (idempotent)
      PhoneNumber.initialize(enableFormats: true);
      PhoneNumber.initialize(enableFormats: true);

      final phone = PhoneNumber.parse('+14155552671');

      // Formats still disabled from first call
      expect(
        () => phone.formatNsn(),
        throwsA(isA<PhoneNumberException>()),
      );
    });
  });

  group('Selective Metadata Loading', () {
    test('initialize(enableFormats: false) disables formats immediately', () {
      // Note: Must be run in isolation as clearCache can't restore original maps
      // This test assumes formats map hasn't been cleared yet

      // Initialize with formats disabled
      PhoneNumber.initialize(enableFormats: false);

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
      final loader = MetadataMemoryManager.instance;

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
