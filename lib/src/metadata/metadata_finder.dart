import '../validation/validator.dart';
import 'models/phone_metadata.dart';
import 'models/phone_metadata_formats.dart';
import 'models/phone_metadata_lengths.dart';
import 'models/phone_metadata_patterns.dart';
import '../iso_codes/iso_code.dart';
import '../parsers/phone_number_exceptions.dart';
import 'metadata_manager.dart';

/// Helper to find metadata for phone number parsing and validation.
abstract class MetadataFinder {
  static final _manager = getMetadataManager();

  /// Find metadata for a specific ISO code
  static PhoneMetadata findMetadataForIsoCode(IsoCode isoCode) {
    final metadata = _manager.getMetadata(isoCode);
    if (metadata == null) {
      throw PhoneNumberException(
        code: Code.invalidIsoCode,
        description: '$isoCode not found',
      );
    }
    return metadata;
  }

  /// Find pattern metadata for a specific ISO code
  static PhoneMetadataPatterns findMetadataPatternsForIsoCode(IsoCode isoCode) {
    final metadata = _manager.getPatterns(isoCode);
    if (metadata == null) {
      throw PhoneNumberException(
        code: Code.invalidIsoCode,
        description: '$isoCode not found',
      );
    }
    return metadata;
  }

  /// Find length metadata for a specific ISO code
  static PhoneMetadataLengths findMetadataLengthForIsoCode(IsoCode isoCode) {
    final metadata = _manager.getLengths(isoCode);
    if (metadata == null) {
      throw PhoneNumberException(
        code: Code.invalidIsoCode,
        description: 'isoCode "$isoCode" not found',
      );
    }
    return metadata;
  }

  /// Find format metadata for a specific ISO code
  static PhoneMetadataFormats findMetadataFormatsForIsoCode(IsoCode isoCode) {
    final metadata = _manager.getFormats(isoCode);
    if (metadata == null) {
      throw PhoneNumberException(
        code: Code.invalidIsoCode,
        description: 'isoCode "$isoCode" not found',
      );
    }
    return metadata;
  }

  /// Find metadata for a country code with pattern matching
  static PhoneMetadata? findMetadataForCountryCode(
    String countryCode,
    String nationalNumber,
  ) {
    final isoList = _manager.getIsoCodesFromCountryCode(countryCode);

    if (isoList.isEmpty) {
      return null;
    }
    // country code can have multiple metadata because multiple iso code
    // share the same country code.
    final allMatchingMetadata =
        isoList.map((iso) => findMetadataForIsoCode(iso)).toList();

    final match = _getMatchUsingPatterns(nationalNumber, allMatchingMetadata);
    return match;
  }

  static PhoneMetadata _getMatchUsingPatterns(
    String nationalNumber,
    List<PhoneMetadata> potentialFits,
  ) {
    if (potentialFits.length == 1) return potentialFits[0];
    // if the phone number is valid for a metadata return that metadata
    for (var fit in potentialFits) {
      final isValidForIso =
          Validator.validateWithPattern(fit.isoCode, nationalNumber);
      if (isValidForIso) {
        return fit;
      }
    }
    // otherwise the phone number starts with leading digits of metadata
    for (var fit in potentialFits) {
      final leadingDigits = fit.leadingDigits;
      if (leadingDigits != null && nationalNumber.startsWith(leadingDigits)) {
        return fit;
      }
    }

    // best guess here
    return potentialFits.firstWhere(
      (fit) => fit.isMainCountryForDialCode,
      orElse: () => potentialFits[0],
    );
  }
}
