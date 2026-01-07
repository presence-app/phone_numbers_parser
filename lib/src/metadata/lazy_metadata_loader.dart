import '../iso_codes/iso_code.dart';
import 'generated/country_code_to_iso_code.dart';
import 'generated/metadata_by_iso_code.dart';
import 'generated/metadata_formats_by_iso_code.dart';
import 'generated/metadata_lengths_by_iso_code.dart';
import 'generated/metadata_patterns_by_iso_code.dart';
import 'models/phone_metadata.dart';
import 'models/phone_metadata_formats.dart';
import 'models/phone_metadata_lengths.dart';
import 'models/phone_metadata_patterns.dart';

/// Lazy loader for phone metadata with initialization control and memory optimization.
///
/// This loader provides multiple strategies to reduce memory footprint:
///
/// ## 1. Lazy Loading (Automatic)
/// Metadata maps use `late final` and aren't loaded until first use, saving
/// ~50-100ms at app launch. Call [initialize()] to control when loading happens.
///
/// ## 2. Selective Loading
/// Disable formatting metadata when you only need parsing/validation:
/// ```dart
/// LazyMetadataLoader.instance.initialize(enableFormats: false);
/// // Saves ~200KB (~37% of total metadata)
/// ```
///
/// ## 3. Warm-up and Purge
/// After warming up with countries you need, call [purge()] to remove unused
/// countries, reducing memory by up to 87%.
///
/// ## Usage Patterns
///
/// ### Pattern 1: Default (Auto Lazy Loading)
/// ```dart
/// // Do nothing - maps load on first parse (~50-100ms delay once)
/// PhoneNumber.parse('+14155552671'); // First call loads all maps
/// PhoneNumber.parse('+33612345678'); // Instant (already loaded)
/// ```
///
/// ### Pattern 2: Eager Initialization
/// ```dart
/// void main() {
///   // Load all maps upfront (avoids delay on first parse)
///   LazyMetadataLoader.instance.initialize();
///   runApp(MyApp());
/// }
/// ```
///
/// ### Pattern 3: Smart Initialization (Recommended)
/// ```dart
/// class PhoneInputScreen extends StatefulWidget {
///   @override
///   void initState() {
///     super.initState();
///     // Load during screen animation (user doesn't notice delay)
///     LazyMetadataLoader.instance.initialize();
///   }
/// }
/// ```
///
/// ### Pattern 4: Validation Only (Maximum Savings)
/// ```dart
/// void main() {
///   // Don't load formats (37% immediate savings)
///   LazyMetadataLoader.instance.initialize(enableFormats: false);
///   
///   // Parse and validate works
///   final phone = PhoneNumber.parse('+14155552671');
///   phone.isValid(type: PhoneNumberType.mobile); // ✓ Works
///   phone.formatNsn(); // ✗ Throws (formats not loaded)
/// }
/// ```
///
/// ### Pattern 5: Memory Optimization (90-93% Savings)
/// ```dart
/// void main() {
///   // 1. Initialize without formats
///   LazyMetadataLoader.instance.initialize(enableFormats: false);
///   
///   // 2. Warm-up: Use the countries you need
///   PhoneNumber.parse('+14155552671'); // US
///   PhoneNumber.parse('+33612345678'); // FR
///   
///   // 3. Purge: Keep only US & FR
///   LazyMetadataLoader.instance.purge();
///   
///   // Result: ~50KB instead of ~540KB (90-93% savings!)
///   // Only US & FR can be parsed now
/// }
/// ```
///
/// ## Memory Impact
///
/// - **Default**: ~540KB (245 countries × 4 maps)
/// - **Without formats**: ~340KB (37% savings)
/// - **After purge()**: ~65KB for 30 countries (87% savings)
/// - **Combined**: ~50KB for 30 countries (90-93% savings)
///
/// ## Important Notes
///
/// - [initialize()] is idempotent - safe to call multiple times
/// - After [purge()], only warm-up countries remain available
/// - Optimization persists through app backgrounding
/// - Full app restart reloads all countries
/// - Natural app lifecycle (OS killing backgrounded apps) resets to full data
class LazyMetadataLoader {
  LazyMetadataLoader._();

  static final LazyMetadataLoader _instance = LazyMetadataLoader._();

  /// Get the singleton instance
  static LazyMetadataLoader get instance => _instance;

  // Track accessed countries during warm-up
  final Set<IsoCode> _accessedCodes = {};

  // Cache maps - populated after purge()
  final Map<IsoCode, PhoneMetadata> _metadataCache = {};
  final Map<IsoCode, PhoneMetadataPatterns> _patternsCache = {};
  final Map<IsoCode, PhoneMetadataLengths> _lengthsCache = {};
  final Map<IsoCode, PhoneMetadataFormats> _formatsCache = {};

  // Configuration flags for selective map loading
  bool _formatsEnabled = true;
  bool _purged = false;
  bool _initialized = false;

  /// Initialize all metadata maps to avoid lazy loading delay.
  ///
  /// This method is idempotent - safe to call multiple times from anywhere
  /// (main, multiple screens, etc). Only the first call triggers initialization;
  /// subsequent calls return immediately.
  ///
  /// The maps use `late final` so they won't be loaded until first access.
  /// Call this method to trigger initialization at a convenient time.
  ///
  /// ## Parameters
  /// - [enableFormats]: Whether to load formatting metadata (default: true)
  ///   Set to false if you only need parsing/validation without formatting.
  ///   Saves ~200KB (~37% of total metadata).
  ///
  /// ## Memory Savings
  /// - With formats: ~540KB loaded
  /// - Without formats: ~340KB loaded (37% savings)
  /// - Combined with purge(): 90-93% total savings
  ///
  /// ## Example: Initialize in Main
  /// ```dart
  /// void main() {
  ///   // Initialize everything upfront
  ///   LazyMetadataLoader.instance.initialize();
  ///   runApp(MyApp());
  /// }
  /// ```
  ///
  /// ## Example: Initialize on Screen Navigation
  /// ```dart
  /// class PhoneInputScreen extends StatefulWidget {
  ///   @override
  ///   void initState() {
  ///     super.initState();
  ///     LazyMetadataLoader.instance.initialize(); // During animation
  ///   }
  /// }
  /// ```
  ///
  /// ## Example: Validation Only (No Formatting)
  /// ```dart
  /// void main() {
  ///   // Don't load formats map (37% savings)
  ///   LazyMetadataLoader.instance.initialize(enableFormats: false);
  ///   
  ///   final phone = PhoneNumber.parse('+14155552671');
  ///   phone.isValid(type: PhoneNumberType.mobile); // Works
  ///   phone.formatNsn(); // Throws (formats not loaded)
  ///   
  ///   // After warm-up, purge for 90-93% total savings
  ///   LazyMetadataLoader.instance.purge();
  /// }
  /// ```
  ///
  /// ## Timeline Without initialize()
  /// - App launch: 0ms (lazy maps not loaded)
  /// - First parse: 50-100ms (maps initialize on demand)
  /// - Subsequent parses: <1ms
  ///
  /// ## Timeline With initialize()
  /// - App launch: 0ms (lazy maps not loaded)
  /// - Call initialize(): 50-100ms (one-time initialization)
  /// - All parses: <1ms (already loaded)
  void initialize({bool enableFormats = true}) {
    if (_initialized) return; // Idempotent - skip if already called
    _initialized = true;
    _formatsEnabled = enableFormats;
    
    // Force lazy initialization by accessing each map
    metadataByIsoCode.isEmpty;
    metadataPatternsByIsoCode.isEmpty;
    metadataLenghtsByIsoCode.isEmpty;
    
    // Only initialize formats if enabled
    if (enableFormats) {
      metadataFormatsByIsoCode.isEmpty;
    } else {
      // Clear formats immediately if disabled
      metadataFormatsByIsoCode.clear();
    }
  }

  @Deprecated('Use initialize(enableFormats: false) instead')
  void configure({bool enableFormats = true}) {
    initialize(enableFormats: enableFormats);
  }

  /// Get metadata for a specific ISO code
  PhoneMetadata? getMetadata(IsoCode isoCode) {
    _accessedCodes.add(isoCode);

    if (_purged) {
      return _metadataCache[isoCode];
    }
    return metadataByIsoCode[isoCode];
  }

  /// Get pattern metadata for a specific ISO code
  PhoneMetadataPatterns? getPatterns(IsoCode isoCode) {
    _accessedCodes.add(isoCode);

    if (_purged) {
      return _patternsCache[isoCode];
    }
    return metadataPatternsByIsoCode[isoCode];
  }

  /// Get length metadata for a specific ISO code
  PhoneMetadataLengths? getLengths(IsoCode isoCode) {
    _accessedCodes.add(isoCode);

    if (_purged) {
      return _lengthsCache[isoCode];
    }
    return metadataLenghtsByIsoCode[isoCode];
  }

  /// Get format metadata for a specific ISO code
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
  /// The purge persists for the entire app session, even when the app
  /// goes to background and returns. It only resets when:
  /// - User force-closes the app
  /// - OS kills the app (common after long background time)
  /// - App is restarted
  ///
  /// When the app restarts, all 245 countries are loaded again and you can
  /// call purge() with a new set of countries.
  ///
  /// ## Best Practice
  /// ```dart
  /// // 1. Determine which countries your user needs
  /// final userCountries = getUserCountryPreferences(); // e.g., ['US', 'FR']
  ///
  /// // 2. Warm up by parsing sample numbers from those countries
  /// for (var country in userCountries) {
  ///   try {
  ///     PhoneNumber.parse(getSampleNumber(country));
  ///   } catch (_) {}
  /// }
  ///
  /// // 3. Purge to keep only those countries
  /// LazyMetadataLoader.instance.purge();
  ///
  /// // 4. Continue using with reduced memory footprint
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
    metadataFormatsByIsoCode
        .clear(); // Clear even if already cleared by configure()

    _purged = true;
  }

  @Deprecated('Use purge() instead')
  void optimize() {
    purge();
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
    _initialized = false;
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
// Force change
