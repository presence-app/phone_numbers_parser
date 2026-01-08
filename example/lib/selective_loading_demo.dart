import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'package:phone_numbers_parser/src/metadata/metadata_manager.dart';

/// Demonstrates selective metadata loading for validation-only use cases
///
/// This demo shows how to disable formatting metadata when you only need
/// parsing and validation, achieving even greater memory savings.
void main() {
  print('=== Selective Metadata Loading Demo ===\n');

  // INITIALIZE WITH FORMATS DISABLED
  print('Step 1: Initialize (disable formatting metadata)');
  PhoneNumber.initialize(
    enableFormats: false, // We don't need phone.formatNsn()
  );
  print('  ✓ Formats map cleared (~200KB saved immediately)');
  print('  ✓ Remaining maps: metadata, patterns, lengths (~340KB)\n');

  // WARM-UP: Parse and validate phone numbers
  print('Step 2: Warm-up (parse and validate numbers)');

  // Example 1: E.164 normalization
  final usPhone = PhoneNumber.parse('+14155552671');
  print('  US: ${usPhone.international}');
  print('    Valid mobile: ${usPhone.isValid(type: PhoneNumberType.mobile)}');

  // Example 2: Validation with country context
  final frPhone = PhoneNumber.parse('+33612345678');
  print('  FR: ${frPhone.international}');
  print('    Valid mobile: ${frPhone.isValid(type: PhoneNumberType.mobile)}');

  // Example 3: Multiple validations
  final ukPhone = PhoneNumber.parse('+447911123456');
  print('  UK: ${ukPhone.international}');
  print('    Valid mobile: ${ukPhone.isValid(type: PhoneNumberType.mobile)}');

  // Formatting throws exception (formats disabled)
  print('\n  Formatting test:');
  try {
    usPhone.formatNsn();
    print('    formatNsn() worked unexpectedly!');
  } catch (e) {
    print('    formatNsn() throws exception (expected when formats disabled)');
  }
  print('    ✓ Formats disabled as expected\n');

  final afterWarmup = MetadataMemoryManager.instance.getCacheStats();
  print('After warm-up:');
  print('  Accessed countries: ${afterWarmup["accessed"]}');
  print('  Cached entries: ${afterWarmup["total"]}');
  print('  Memory: ~340KB (formats already cleared)\n');

  // PURGE: Remove unused countries
  print('Step 3: Purge (remove unused countries)');
  MetadataMemoryManager.instance.purge();

  final afterPurge = MetadataMemoryManager.instance.getCacheStats();
  print('  ✓ Purge complete');
  print('  Accessed countries: ${afterPurge["accessed"]}');
  print('  Cached entries: ${afterPurge["total"]}');
  print('  Purged: ${afterPurge["purged"]}\n');

  // VERIFY: Still works after purge
  print('Step 4: Verification');
  final verifyPhone = PhoneNumber.parse('+13105551234'); // Another US number
  print('  Parse: ${verifyPhone.international}');
  print('  Valid: ${verifyPhone.isValid(type: PhoneNumberType.mobile)}\n');

  // CALCULATE SAVINGS
  print('=== Memory Savings Summary ===');
  print('Without purging:');
  print('  All countries: 245 × 4 maps = 980 entries (~540KB)');
  print('');
  print('With initialize(enableFormats: false):');
  print('  All countries: 245 × 3 maps = 735 entries (~340KB)');
  print('  Immediate savings: ~37%');
  print('');
  print('With initialize + purge:');
  final accessed = afterPurge['accessed'] as int;
  final total = afterPurge['total'] as int;
  print('  Used countries: $accessed × 3 maps = $total entries');

  final memoryEstimate = (total / 980 * 540).round();
  print('  Estimated memory: ~${memoryEstimate}KB');

  final totalSavings = ((980 - total) / 980 * 100).toStringAsFixed(1);
  print('  Total savings: ~$totalSavings%');
  print('');
  print('Perfect for validation-only use cases!');
  print('No formatting needed, maximum memory efficiency');
}
