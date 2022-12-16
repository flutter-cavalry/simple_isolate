[![pub package](https://img.shields.io/pub/v/simple_isolate.svg)](https://pub.dev/packages/simple_isolate)
[![Build Status](https://github.com/flutter-cavalry/simple_isolate/workflows/Build/badge.svg)](https://github.com/flutter-cavalry/simple_isolate/actions)

Simplified Dart isolates.

## Features

- A `Future` based API that support returning data, completion, and handling exceptions
- Opt-in Bi-directional communication support between `Isolate` and the outer world

## Usage

### Basic usage

First, install and import this package:

```dart
import 'package:simple_isolate/simple_isolate.dart';
```

Instead of `Isolate.spawn`, use `SimpleIsolate.spawn<T, R>(entrypoint, argument)` to run a function of type `Future<R> Function(SIContext<T> ctx)` as the entrypoint function for the `Isolate` to be created.

- The context type `SIContext<T>` can be used in many cases, which we will cover in examples below
- `SIContext.argument`: gets the argument passed to the entrypoint function
- Note the entrypoint function returns a `Future`, so you can return data back to the calling function as long as the data is serializable between isolates
- `SimpleIsolate.spawn`: wrapper around `Isolate.spawn`, returns a `Future<SimpleIsolate>`.
- `SimpleIsolate.future`: use this to wait for completion or handle exceptions from entrypoint function
- `SimpleIsolate.core`: returns the internal dart [Isolate]

For example, return some data:

```dart
// Create a [SimpleIsolate] from function of type [Future<String>(int)].
var si = await SimpleIsolate.spawn<int, String>(
  (SIContext<int> ctx) async {
    var result = '';
    // Use `ctx.argument` to get the argument passed to the entrypoint function.
    for (var i = 0; i < ctx.argument; i++) {
      result += '<data chunk $i>';
      await Future<void>.delayed(Duration(milliseconds: 500));
    }
    return result;
  },
  3,
);

// Wait for the Isolate function to complete.
// And print out the result.
print(await si.future);
/**
  * <data chunk 0><data chunk 1><data chunk 2>
  */
```

## Error handling

Since it's a `Future` based API, you can simply wrap the `await` statement in a `try-catch` block to handle exceptions:

```dart
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
```

## Send messages from `Isolate`

Use `Context.sendMsg` to send a message from isolate to the outer world. A message in `simple_isolate` is defined as:

```dart
class SIMsg {
  final String name;
  final Map<String, dynamic>? params;
  SIMsg(this.name, this.params);
}
```

To handle the messages sent from an isolate, use the `onMsgReceived` params in `SimpleIsolate.spawn`:

```dart
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
```

## Send messages into `Isolate`

To send message back into isolate, use `SimpleIsolate.sendMsgToIsolate`. And handle those messages with `SIContext.onMsgReceivedInIsolate`.

**Note that the messages you sent to `Isolate` may not be handled if your entrypoint function exits too early. Message handling in isolate relies on the internal event loop created in the isolate. If it exits too early (or technically speaking, it exits without needing to wait for next event loop), the isolate exits too and never gets to handle the `onMsgReceivedInIsolate`. In the example below, we called `Future<void>.delayed` to make use of the event loop associated with the isolate. **

```dart
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
```
