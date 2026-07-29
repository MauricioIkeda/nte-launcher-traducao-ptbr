import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nte_translation_launcher/services/download_service.dart';

void main() {
  test('server ignoring Range restarts instead of appending', () {
    expect(
      validateResumeResponse(
        statusCode: HttpStatus.ok,
        contentRange: null,
        existingBytes: 50,
        expectedSize: 100,
      ),
      isFalse,
    );
  });

  test('valid Content-Range resumes at the exact offset', () {
    expect(
      validateResumeResponse(
        statusCode: HttpStatus.partialContent,
        contentRange: 'bytes 50-99/100',
        existingBytes: 50,
        expectedSize: 100,
      ),
      isTrue,
    );
  });

  for (final range in [
    null,
    'bytes 49-99/100',
    'bytes 50-99/101',
    'bytes 50-100/100',
    'invalid',
  ]) {
    test('rejects invalid partial response $range', () {
      expect(
        () => validateResumeResponse(
          statusCode: HttpStatus.partialContent,
          contentRange: range,
          existingBytes: 50,
          expectedSize: 100,
        ),
        throwsA(isA<DownloadResumeException>()),
      );
    });
  }

  test('rejects an unexpected non-success response', () {
    expect(
      () => validateResumeResponse(
        statusCode: HttpStatus.requestedRangeNotSatisfiable,
        contentRange: null,
        existingBytes: 100,
        expectedSize: 100,
      ),
      throwsA(isA<DownloadResumeException>()),
    );
  });
}
