import 'package:simple_isolate/simple_isolate.dart';
import 'package:test/test.dart';

void main() {
  test('Future and completion', () async {
    var si = await SimpleIsolate.spawn<String>((SIContext ctx) async {
      var to = ctx.argument as int;
      for (var i = 1; i <= to; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      return 'result: $to';
    }, 3);
    expect(await si.future, 'result: 3');
  });

  test('Exception', () async {
    var si = await SimpleIsolate.spawn<String>((SIContext ctx) async {
      var to = ctx.argument as int;
      for (var i = 1; i <= to; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      throw FormatException('haha');
    }, 3);
    expect(() => si.future, throwsA(isA<FormatException>()));
  });

  test('Stacktrace', () async {
    var si = await SimpleIsolate.spawn<String>((SIContext ctx) async {
      var to = ctx.argument as int;
      for (var i = 1; i <= to; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      throw FormatException('haha');
    }, 3);
    var stacktrace = '';
    try {
      await si.future;
    } catch (err, st) {
      stacktrace = st.toString();
    }
    expect(stacktrace, contains('simple_isolate_test.dart:33:7'));
  });

  test('Message handler', () async {
    List<String> msgList = [];
    var si = await SimpleIsolate.spawn<String>(
      (SIContext ctx) async {
        var to = ctx.argument as int;
        ctx.sendMsg('greeting', <String, dynamic>{'msg': 'hello'});
        for (var i = 1; i <= to; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          ctx.sendMsg('i', <String, dynamic>{'value': i});
        }
        ctx.sendMsg('greeting', <String, dynamic>{'msg': 'done'});
        return 'result: $to';
      },
      3,
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
  });

  test('Bidirectional Message handlers', () async {
    List<String> msgList = [];
    var si = await SimpleIsolate.spawn<String>(
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
      onMsgReceived: (msg) => msgList.add(msg.toString()),
    );

    await si.sendMsgToIsolate('hi', <String, dynamic>{'from': 'main process'});
    expect(await si.future,
        '<sending hello>hi -> {from: main process}<sending done>');
    expect(msgList, ['greeting -> {msg: hello}', 'greeting -> {msg: done}']);
  });
  test('Cancellation', () async {
    var si = await SimpleIsolate.spawn<String>((SIContext ctx) async {
      var to = ctx.argument as int;
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
          si.core.kill();
          return Future.value('');
        }(),
      ]);
    }, throwsA(isA<SimpleIsolateAbortException>()));
  });
}
