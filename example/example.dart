// ignore_for_file: avoid_print

import 'package:simple_isolate/simple_isolate.dart';

Future<void> futureCompletion() async {
  // Create a [SimpleIsolate] from function of type [Future<String>(int)].
  var si = await SimpleIsolate.spawn<int, String>(
    (SIContext<int> ctx) async {
      var result = '';
      for (var i = 0; i < ctx.argument; i++) {
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
  // Create a [SimpleIsolate] from function of type [Future<String>(int)].
  var si = await SimpleIsolate.spawn<int, String>(
    (SIContext<int> ctx) async {
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
  // Create a [SimpleIsolate] from function of type [Future<String>(int)].
  var si = await SimpleIsolate.spawn<int, String>(
    (SIContext<int> ctx) async {
      var result = '';
      for (var i = 0; i < ctx.argument; i++) {
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
  // Create a [SimpleIsolate] from function of type [Future<String>(int)].
  var si = await SimpleIsolate.spawn<int, String>(
    (SIContext<int> ctx) async {
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
      for (var i = 0; i < ctx.argument; i++) {
        result += '<data chunk $i>';
        await Future<void>.delayed(Duration(milliseconds: 500));
      }
      return result;
    },
    3,
  );
  await si
      .sendMsgToIsolate('inject', <String, dynamic>{'value': '<injected!!!>'});
  print(await si.future);
  /**
   * <data chunk 0><injected!!!><data chunk 1><data chunk 2>
   */
}