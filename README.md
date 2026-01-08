# Phone Numbers Parser

Dart library for parsing phone numbers. Inspired by Google's libphonenumber and PhoneNumberKit for ios.

The advantage of this lib instead of libphonenumber is that it instantly supports all platforms (no need for channeling).

## Features

 - Validation: Validate based on type (mobile, fixed line, voip)
 - Formatting: Format phone number for a specific country
 - Phone ranges: find all phone numbers in a range of phone numbers
 - Find phone numbers in a text
 - Supports eastern arabic digits
 - Uses best-in-class metadata from Google's libPhoneNumber project. 

## Demo

[demo](https://cedvdb.github.io/phone_numbers_parser/)

## Contributing

[Please read this to upgrade the metadata](CONTRIBUTING.md)

## Usage

Use the class `PhoneNumber` as a starting point

```dart
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

void main(List<String> arguments) {
  final frPhone0 = PhoneNumber.parse('+33 655 5705 76');
  // raw caller in france calling another person in france
  final frPhone1 =
      PhoneNumber.parse('0 655 5705 76', callerCountry: IsoCode.FR);
  // us calling to france
  final frPhone2 =
      PhoneNumber.parse('011 33 655-5705-76', callerCountry: IsoCode.US);
  final frPhone3 =
      PhoneNumber.parse('011 33 655 5705 76', destinationCountry: IsoCode.FR);
  final isAllEqual =
      frPhone0 == frPhone1 && frPhone0 == frPhone2 && frPhone0 == frPhone3;
  print(frPhone1);
  print('all raw same: $isAllEqual');

  // validation
  final valid = frPhone1.isValid();
  final validMobile = frPhone1.isValid(type: PhoneNumberType.mobile);
  final validFixed = frPhone1.isValid(type: PhoneNumberType.fixedLine);
  print('valid: $valid'); // true
  print('valid mobile: $validMobile'); // true
  print('valid fixed line: $validFixed'); // false

  // utils
  final text =
      'hey my phone number is: +33 939 876 218, but you can call me on +33 939 876 999 too';
  final found = PhoneNumber.findPotentialPhoneNumbers(text);
  print('found: $found');
}
```

# validation

```dart
final valid = frPhone1.validate();
final validMobile = frPhone1.validate(type: PhoneNumberType.mobile);
final validFixed = frPhone1.validate(type: PhoneNumberType.fixedLine);
print('valid: $valid'); // true
print('valid mobile: $validMobile'); // true
print('valid fixed line: $validFixed'); // false
```

### Formatting

Formatting is region specific, so the formats will vary by iso code to accommodate
for local formats.

```dart
final phoneNumber =
    PhoneNumber.parse('2025550119', destinationCountry: IsoCode.US);
final formattedNsn = phoneNumber.formatNsn();
print('formatted: $formattedNsn'); // (202) 555-0119
```

### Range 

```dart
print('Ranges:');
final first = PhoneNumber.parse('+33 655 5705 00');
final last = PhoneNumber.parse('+33 655 5705 03');
final range = PhoneNumber.getRange(first, last);

print('Count: ${range.count}');
print('Expand: ${range.expandRange().join(',')}');

if (first > last) {
  print("this shouldn't be.");
}

final one = PhoneNumber.parse('+33 655 5705 01');
final two = PhoneNumber.parse('+33 655 5705 02');

if (one.isAdjacentTo(two)) {
  print('We are together');
}
if (one.isSequentialTo(two)) {
  print('$two comes after $one');
}

/// treat the phone no. like an int
final three = two + 1;
print('Its still a phone No. $three');
two - 1 == one;
final another = one + 2;
print('$another == $three');
```

## Memory Optimization

By default, the library loads metadata for all 245 countries (~540KB). For apps that only need specific countries, you can reduce memory usage by up to 90%.

### Disable Formatting (37% savings)

If you only need parsing/validation without formatting:

```dart
PhoneNumber.initialize(enableFormats: false);
// Saves ~200KB - formatting will throw an exception
```

### Purge Unused Countries (87% savings)

Parse the countries you need, then purge the rest:

```dart
// Parse numbers from countries you need
PhoneNumber.parse('+14155552671'); // US
PhoneNumber.parse('+33612345678'); // FR

// Remove all other countries
MetadataMemoryManager.instance.purge();
// Keeps only US & FR (~65KB instead of ~540KB)
```

### Combined Optimization (90-93% savings)

```dart
// Disable formats and purge unused countries
PhoneNumber.initialize(enableFormats: false);
// ... parse your countries ...
MetadataMemoryManager.instance.purge();
// Result: ~50KB instead of ~540KB
```

For detailed information, see [MEMORY_OPTIMIZATION.md](MEMORY_OPTIMIZATION.md)

