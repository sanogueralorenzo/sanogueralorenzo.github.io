import 'package:app/src/mavericks/async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('async state flags and error accessors work', () {
    const uninitialized = Uninitialized<int>();
    const loading = Loading<int>(1);
    const success = Success<int>(2);
    final fail = Fail<int>(Exception('boom'), 3);

    expect(uninitialized.isUninitialized, isTrue);
    expect(loading.isLoading, isTrue);
    expect(success.isSuccess, isTrue);
    expect(fail.isFail, isTrue);
    expect(fail.errorOrNull, isA<Exception>());
    expect(fail.errorOrNull.messageOrNull, 'boom');
    expect(uninitialized.valueOrNull, isNull);
    expect(loading.valueOrNull, 1);
    expect(success.valueOrNull, 2);
    expect(fail.valueOrNull, 3);
  });

  test('map covers all async branches', () {
    expect(
      const Uninitialized<int>().map((value) => '$value'),
      isA<Uninitialized<String>>(),
    );
    expect(
      const Loading<int>(1).map((value) => '$value'),
      const Loading<String>(),
    );
    expect(
      const Loading<int>(1).map((value) => '$value', retainValue: true),
      const Loading<String>('1'),
    );
    expect(
      const Success<int>(2).map((value) => '$value'),
      const Success<String>('2'),
    );

    final fail = Fail<int>(
      Exception('boom'),
      3,
    ).map((value) => '$value', retainValue: true);
    expect(fail, isA<Fail<String>>());
    expect(fail.valueOrNull, '3');
  });

  test('messageOrNull uses dynamic message and string fallback', () {
    expect('plain'.messageOrNull, 'plain');
    expect(_MessageError('custom').messageOrNull, 'custom');
    expect(_MessageError('').messageOrNull, contains('_MessageError'));
    expect(Exception('boom').messageOrNull, 'boom');
    expect(null.messageOrNull, isNull);
  });

  test('async equality and hashCode use their payloads', () {
    expect(const Uninitialized<int>(), const Uninitialized<int>());
    expect(const Loading<int>(1), const Loading<int>(1));
    expect(const Success<int>(2), const Success<int>(2));
    expect(Fail<int>('boom', 3), Fail<int>('boom', 3));

    expect(const Uninitialized<int>().hashCode, 0);
    expect(const Loading<int>(1).hashCode, const Loading<int>(1).hashCode);
    expect(const Success<int>(2).hashCode, const Success<int>(2).hashCode);
    expect(Fail<int>('boom', 3).hashCode, Fail<int>('boom', 3).hashCode);
  });
}

class _MessageError {
  _MessageError(this.message);

  final String message;
}
