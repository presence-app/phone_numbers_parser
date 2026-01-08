import 'models/phone_metadata.dart';
import 'models/phone_metadata_formats.dart';
import 'models/phone_metadata_lengths.dart';
import 'models/phone_metadata_patterns.dart';
import '../iso_codes/iso_code.dart';
import 'generated/country_code_to_iso_code.dart';
import 'generated/metadata_by_iso_code.dart';
import 'generated/metadata_formats_by_iso_code.dart';
import 'generated/metadata_lengths_by_iso_code.dart';
import 'generated/metadata_patterns_by_iso_code.dart';

// ============================================================================
// PART 1: Internal Memory Manager (access, tracking, purging, caching)
// ============================================================================

/// Internal manager for metadata access and memory optimization.
///
/// Provides:
/// - Access to metadata maps (by ISO code)
/// - Tracking of accessed countries during warm-up
/// - Purging unused countries to reduce memory
/// - Format filtering when disabled
///
/// **Note:** This is internal. Use `PhoneNumber.initialize()` and
/// `MetadataMemoryManager.instance.purge()` for public API.
class _MetadataManager {
  _MetadataManager._();

  static final _MetadataManager _instance = _MetadataManager._();

  static _MetadataManager get instance => _instance;

  // Track accessed countries during warm-up
  final Set<IsoCode> _accessedCodes = {};

  // Cache maps - populated after purge()
  final Map<IsoCode, PhoneMetadata> _metadataCache = {};
  final Map<IsoCode, PhoneMetadataPatterns> _patternsCache = {};
  final Map<IsoCode, PhoneMetadataLengths> _lengthsCache = {};
  final Map<IsoCode, PhoneMetadataFormats> _formatsCache = {};

  // Configuration flags
  bool _formatsEnabled = true;
  bool _purged = false;

  /// Set whether formats are enabled (called by PhoneNumber.initialize)
  void setFormatsEnabled(bool enabled) {
    _formatsEnabled = enabled;
  }

  /// Get metadata for a specific ISO code (with tracking)
  PhoneMetadata? getMetadata(IsoCode isoCode) {
    _accessedCodes.add(isoCode);

    if (_purged) {
      return _metadataCache[isoCode];
    }
    return metadataByIsoCode[isoCode];
  }

  /// Get pattern metadata for a specific ISO code (with tracking)
  PhoneMetadataPatterns? getPatterns(IsoCode isoCode) {
    _accessedCodes.add(isoCode);

    if (_purged) {
      return _patternsCache[isoCode];
    }
    return metadataPatternsByIsoCode[isoCode];
  }

  /// Get length metadata for a specific ISO code (with tracking)
  PhoneMetadataLengths? getLengths(IsoCode isoCode) {
    _accessedCodes.add(isoCode);

    if (_purged) {
      return _lengthsCache[isoCode];
    }
    return metadataLenghtsByIsoCode[isoCode];
  }

  /// Get format metadata for a specific ISO code (with tracking)
  /// Handles format references by following the reference chain
  PhoneMetadataFormats? getFormats(IsoCode isoCode) {
    // Return null if formats are disabled
    if (!_formatsEnabled) return null;

    _accessedCodes.add(isoCode);

    if (_purged) {
      return _formatsCache[isoCode];
    }

    var metadata = metadataFormatsByIsoCode[isoCode];
    if (metadata is PhoneMetadataFormatReferenceDefinition) {
      metadata = metadataFormatsByIsoCode[metadata.referenceIsoCode];
    }

    if (metadata is PhoneMetadataFormatListDefinition) {
      return metadata.formats;
    }

    return null;
  }

  /// Get ISO codes for a country code (not cached as this is a small lookup)
  List<IsoCode> getIsoCodesFromCountryCode(String countryCode) {
    return countryCodeToIsoCode[countryCode] ?? [];
  }

  /// Purge unused countries from memory to reduce footprint.
  ///
  /// This method:
  /// 1. Copies all countries accessed during warm-up to an internal cache
  /// 2. Clears the original metadata maps to free memory
  /// 3. Keeps only the cached (used) countries in memory
  ///
  /// ## Memory Savings Example
  /// - Before: 245 countries × 4 metadata types = 980 entries (~540KB)
  /// - After warm-up with 30 countries: 30 × 4 = 120 entries (~65KB)
  /// - Memory saved: ~87%
  ///
  /// ## Critical Warning
  /// **After calling purge(), new countries cannot be parsed!**
  ///
  /// Only countries accessed before purge() remain available. Attempting
  /// to parse a new country will fail with "IsoCode not found" error.
  ///
  /// ## When It Resets
  /// The purge persists for the entire app session. It only resets when:
  /// - User force-closes the app
  /// - OS kills the app (common after long background time)
  /// - App is restarted
  ///
  /// ## Best Practice
  /// ```dart
  /// // 1. Parse the countries you need
  /// PhoneNumber.parse('+14155552671'); // US
  /// PhoneNumber.parse('+33612345678'); // FR
  ///
  /// // 2. Purge to keep only those countries
  /// MetadataMemoryManager.instance.purge();
  ///
  /// // 3. Continue using with reduced memory footprint
  /// ```
  ///
  /// ## Idempotent
  /// Calling purge() multiple times is safe - it only runs once.
  void purge() {
    if (_purged) return;

    // Copy accessed countries to cache
    for (var code in _accessedCodes) {
      final metadata = metadataByIsoCode[code];
      if (metadata != null) {
        _metadataCache[code] = metadata;
      }

      final patterns = metadataPatternsByIsoCode[code];
      if (patterns != null) {
        _patternsCache[code] = patterns;
      }

      final lengths = metadataLenghtsByIsoCode[code];
      if (lengths != null) {
        _lengthsCache[code] = lengths;
      }

      // Handle formats with references (only if enabled)
      if (_formatsEnabled) {
        var formatDef = metadataFormatsByIsoCode[code];
        if (formatDef is PhoneMetadataFormatReferenceDefinition) {
          formatDef = metadataFormatsByIsoCode[formatDef.referenceIsoCode];
        }
        if (formatDef is PhoneMetadataFormatListDefinition) {
          _formatsCache[code] = formatDef.formats;
        }
      }
    }

    // Clear original maps - this frees memory!
    metadataByIsoCode.clear();
    metadataPatternsByIsoCode.clear();
    metadataLenghtsByIsoCode.clear();
    metadataFormatsByIsoCode.clear();

    _purged = true;
  }

  /// Clear all cached metadata (useful for testing)
  void clearCache() {
    _metadataCache.clear();
    _patternsCache.clear();
    _lengthsCache.clear();
    _formatsCache.clear();
    _accessedCodes.clear();
    _formatsEnabled = true;
    _purged = false;
  }

  /// Get cache statistics for monitoring
  Map<String, dynamic> getCacheStats() {
    return {
      'metadata': _metadataCache.length,
      'patterns': _patternsCache.length,
      'lengths': _lengthsCache.length,
      'formats': _formatsCache.length,
      'accessed': _accessedCodes.length,
      'purged': _purged,
      'total': _metadataCache.length +
          _patternsCache.length +
          _lengthsCache.length +
          _formatsCache.length,
    };
  }
}

// ============================================================================
// PART 2: Public API - Memory Management
// ============================================================================

/// Public API for metadata memory optimization.
///
/// ## Memory Optimization Strategy
///
/// **1. Disable Formatting (37% savings)**
/// ```dart
/// PhoneNumber.initialize(enableFormats: false);
/// // Saves ~200KB if you only need parsing/validation
/// ```
///
/// **2. Purge Unused Countries (87% savings)**
/// ```dart
/// // Parse the countries you need
/// PhoneNumber.parse('+14155552671'); // US
/// PhoneNumber.parse('+33612345678'); // FR
///
/// // Remove all other countries
/// MetadataMemoryManager.instance.purge();
/// // Keeps only US & FR (~65KB instead of ~540KB)
/// ```
///
/// **3. Combined (90-93% savings)**
/// ```dart
/// PhoneNumber.initialize(enableFormats: false);
/// // ... parse your countries ...
/// MetadataMemoryManager.instance.purge();
/// // Result: ~50KB instead of ~540KB
/// ```
///
/// ## Memory Impact
/// - Default: ~540KB (245 countries × 4 maps)
/// - Without formats: ~340KB (37% savings)
/// - After purge (30 countries): ~65KB (87% savings)
/// - Both: ~50KB (90-93% savings)
abstract class MetadataMemoryManager {
  static final _manager = _MetadataManager.instance;

  /// Get the manager instance for purging operations
  static MetadataMemoryManager get instance => _MetadataMemoryManagerImpl._();

  /// Purge unused countries from memory. See [_MetadataManager.purge] for details.
  void purge();

  /// Get cache statistics for monitoring. See [_MetadataManager.getCacheStats] for details.
  Map<String, dynamic> getCacheStats();
}

class _MetadataMemoryManagerImpl implements MetadataMemoryManager {
  _MetadataMemoryManagerImpl._();

  @override
  void purge() => MetadataMemoryManager._manager.purge();

  @override
  Map<String, dynamic> getCacheStats() =>
      MetadataMemoryManager._manager.getCacheStats();
}

/// Internal API - access to the metadata manager for MetadataFinder
_MetadataManager getMetadataManager() => _MetadataManager.instance;
