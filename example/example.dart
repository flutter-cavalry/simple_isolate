// ignore_for_file: avoid_print, use_string_buffers

import 'package:simple_isolate/simple_isolate.dart';

Future<void> futureCompletion() async {
  final si = await SimpleIsolate.spawn<String>(
    (SIContext ctx) async {
      final count = ctx.argument as int;
      var result = '';
      for (var i = 0; i < count; i++) {
        result += '<data chunk $i>';
        await Future<void>.delayed(Duration(milliseconds: 500));
      }
      return result;
    },
    3,
  );
  print(await si.future);
  /**
   * <data chunk 0><data chunk 1><data chunk 2>
   */
}

Future<void> futureException() async {
  final si = await SimpleIsolate.spawn<String>(
    (SIContext ctx) async {
      await Future<void>.delayed(Duration(milliseconds: 500));
      throw Exception('Oops!');
    },
    3,
  );
  try {
    print(await si.future);
  } catch (err) {
    print('ERROR: $err');
  }
  /**
   * ERROR: Exception: Oops!
   */
}

Future<void> sendMessagesFromIsolate() async {
  final si = await SimpleIsolate.spawn<String>(
    (SIContext ctx) async {
      var result = '';
      final to = ctx.argument as int;
      for (var i = 0; i < to; i++) {
        result += '<data chunk $i>';
        ctx.sendMsg(
            'got-data', <String, dynamic>{'index': i, 'currentResult': result});
        await Future<void>.delayed(Duration(milliseconds: 500));
      }
      return result;
    },
    3,
    onMsgReceived: (msg) {
      switch (msg.name) {
        case 'got-data':
          {
            print('MSG> ${msg.params}');
            break;
          }

        default:
          {
            print(
                'Unsupported message ${msg.name}, something went wrong in your code.');
            break;
          }
      }
    },
  );
  print(await si.future);
  /**
   * MSG> {index: 0, currentResult: <data chunk 0>}
   * MSG> {index: 1, currentResult: <data chunk 0><data chunk 1>}
   * MSG> {index: 2, currentResult: <data chunk 0><data chunk 1><data chunk 2>}
   * <data chunk 0><data chunk 1><data chunk 2>
   */
}

Future<void> sendMessagesToIsolate() async {
  final si = await SimpleIsolate.spawn<String>((SIContext ctx) async {
    var result = '';
    ctx.onMsgReceivedInIsolate = (msg) {
      switch (msg.name) {
        case 'inject':
          {
            result += msg.params?['value'] as String;
            break;
          }

        default:
          {
            print(
                'Unsupported message ${msg.name}, something went wrong in your code.');
            break;
          }
      }
    };
    final to = ctx.argument as int;
    for (var i = 0; i < to; i++) {
      result += '<data chunk $i>';
      await Future<void>.delayed(Duration(milliseconds: 500));
    }
    return result;
  }, 3, bidirectional: true);
  await si
      .sendMsgToIsolate('inject', <String, dynamic>{'value': '<injected!!!>'});
  print(await si.future);
  /**
   * <data chunk 0><injected!!!><data chunk 1><data chunk 2>
   */
}

Future<void> kill() async {
  final si = await SimpleIsolate.spawn<String>(
    (SIContext ctx) async {
      final count = ctx.argument as int;
      var result = '';
      for (var i = 0; i < count; i++) {
        final data = '<data chunk $i>';
        print('--> Appending data $data');
        result += data;
        await Future<void>.delayed(Duration(milliseconds: 500));
      }
      return result;
    },
    4,
  );

  try {
    await Future.wait<String>([
      si.future,
      () async {
        await Future<void>.delayed(Duration(seconds: 1));
        si.kill();
        return Future.value('');
      }(),
    ]);
  } on SimpleIsolateAbortException catch (_) {
    print('Isolation killed');
  }
}

Future<void> onSpawn() async {
  final si = await SimpleIsolate.spawn<String>(
    (SIContext ctx) async {
      final count = ctx.argument as int;
      var result = '';
      for (var i = 0; i < count; i++) {
        result += '<data chunk $i>';
        await Future<void>.delayed(Duration(milliseconds: 500));
      }
      return result;
    },
    3,
    onSpawn: (dynamic argument) => print('onSpawn called with $argument'),
  );
  print(await si.future);
  /**
   * <data chunk 0><data chunk 1><data chunk 2>
   */
}

void main(List<String> args) async {
  await futureCompletion();
  try {
    await futureException();
  } catch (err) {
    print('Error: $err');
  }
  await sendMessagesFromIsolate();
  await sendMessagesToIsolate();
  await kill();
  await onSpawn();
}
