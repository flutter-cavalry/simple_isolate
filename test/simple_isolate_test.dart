import 'package:simple_isolate/simple_isolate.dart';
import 'package:test/test.dart';

Future<void> testFutureAndCompletion(bool sync) async {
  final si = await SimpleIsolate.spawn<String>((SIContext ctx) async {
    final to = ctx.argument as int;
    for (var i = 1; i <= to; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return 'result: $to';
  }, 3, synchronous: sync);
  expect(await si.future, 'result: 3');
}

Future<void> testException(bool sync) async {
  final si = await SimpleIsolate.spawn<String>((SIContext ctx) async {
    final to = ctx.argument as int;
    for (var i = 1; i <= to; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw FormatException('haha');
  }, 3, synchronous: sync);
  expect(() => si.future, throwsA(isA<FormatException>()));
}

Future<void> testStacktrace(bool sync) async {
  final si = await SimpleIsolate.spawn<String>((SIContext ctx) async {
    final to = ctx.argument as int;
    for (var i = 1; i <= to; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw FormatException('haha');
  }, 3, synchronous: sync);
  var stacktrace = '';
  try {
    await si.future;
  } catch (err, st) {
    stacktrace = st.toString();
  }
  expect(stacktrace, contains('simple_isolate_test.dart:32:5'));
}

Future<void> testMessageHandlers(bool sync) async {
  final List<String> msgList = [];
  final si = await SimpleIsolate.spawn<String>(
    (SIContext ctx) async {
      final to = ctx.argument as int;
      ctx.sendMsg('greeting', <String, dynamic>{'msg': 'hello'});
      for (var i = 1; i <= to; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        ctx.sendMsg('i', <String, dynamic>{'value': i});
      }
      ctx.sendMsg('greeting', <String, dynamic>{'msg': 'done'});
      return 'result: $to';
    },
    3,
    synchronous: sync,
    onMsgReceived: (msg) => msgList.add(msg.toString()),
  );
  await si.future;
  expect(msgList, [
    'greeting -> {msg: hello}',
    'i -> {value: 1}',
    'i -> {value: 2}',
    'i -> {value: 3}',
    'greeting -> {msg: done}'
  ]);
}

Future<void> testBidirMessageHandlers(bool sync) async {
  final List<String> msgList = [];
  final si = await SimpleIsolate.spawn<String>(
    (SIContext ctx) async {
      var res = '';
      ctx.onMsgReceivedInIsolate = (msg) {
        res += msg.toString();
      };
      res += '<sending hello>';
      ctx.sendMsg('greeting', <String, dynamic>{'msg': 'hello'});
      await Future<void>.delayed(Duration(seconds: 2));
      res += '<sending done>';
      ctx.sendMsg('greeting', <String, dynamic>{'msg': 'done'});
      return res;
    },
    3,
    synchronous: sync,
    bidirectional: true,
    onMsgReceived: (msg) => msgList.add(msg.toString()),
  );

  await si.sendMsgToIsolate('hi', <String, dynamic>{'from': 'main process'});
  expect(await si.future,
      '<sending hello>hi -> {from: main process}<sending done>');
  expect(msgList, ['greeting -> {msg: hello}', 'greeting -> {msg: done}']);
}

void main() {
  test('Future and completion', () async => testFutureAndCompletion(false));
  test('Future and completion (sync)',
      () async => testFutureAndCompletion(true));

  test('Exception', () async => testException(false));
  test('Exception (sync)', () async => testException(true));

  test('Stacktrace', () async => testStacktrace(false));

  test('Stacktrace (sync)', () async => testStacktrace(true));

  test('Message handlers', () async => testMessageHandlers(false));

  test('Message handlers (sync)', () async => testMessageHandlers(true));

  test('Bidirectional Message handlers',
      () async => testBidirMessageHandlers(false));

  test('Bidirectional Message handlers (sync)',
      () async => testBidirMessageHandlers(true));

  test('Kill', () async {
    final si = await SimpleIsolate.spawn<String>((SIContext ctx) async {
      final to = ctx.argument as int;
      for (var i = 1; i <= to; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      throw FormatException('haha');
    }, 4);
    expect(() async {
      await Future.wait<String>([
        si.future,
        () async {
          await Future<void>.delayed(Duration(seconds: 1));
          si.kill();
          return Future.value('');
        }(),
      ]);
    }, throwsA(isA<SimpleIsolateAbortException>()));
  });
}
