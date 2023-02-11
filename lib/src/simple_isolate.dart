import 'dart:async';
import 'dart:isolate';

/// A wrapper around [SendPort] to send [SIMsg].
class SISendPort {
  /// [SISendPort] usually embeds message boy into another message identified with [headType].
  /// See [_MsgHead] enum for details.
  final int _headType;

  /// Gets the internal [SendPort].
  final SendPort core;

  /// Sends a message with the given [name] and [params].
  void sendMsg(String name, Map<String, dynamic>? params) {
    core.send([
      _headType,
      [name, params]
    ]);
  }

  SISendPort(this.core, this._headType);
}

/// Message type used in [simple_isolate].
class SIMsg {
  final String name;
  final Map<String, dynamic>? params;
  SIMsg(this.name, this.params);

  static SIMsg fromRawMsg(dynamic dynRawMsg) {
    var rawMsg = dynRawMsg as List<dynamic>;
    var msgName = rawMsg[0] as String;
    var params = rawMsg[1] as Map<String, dynamic>?;
    return SIMsg(msgName, params);
  }

  @override
  String toString() {
    var paramStr = params != null ? params.toString() : '<null>';
    return '$name -> $paramStr';
  }
}

/// Context type used as the only parameter type of entrypoint function.
class SIContext {
  /// The argument passed in [SimpleIsolate.spawn].
  final dynamic argument;

  /// Gets the [SISendPoint] used to send messages from the isolate.
  final SISendPort sendPort;

  /// Fires when messages are received.
  void Function(SIMsg msg)? onMsgReceivedInIsolate;

  SIContext(
    this.argument,
    this.sendPort,
  );

  /// Wrapper around [sendPort.sendMsg].
  void sendMsg(String name, Map<String, dynamic>? params) {
    sendPort.sendMsg(name, params);
  }
}

/// Internal message head type for messages sent into isolate.
enum _MsgHead {
  load,
  userMsg,
  err,
  done,
}

/// Internal message head type for messages sent from isolate.
enum _MsgHeadInIsolate {
  userMsg,
}

/// The exception type indicating an [Isolate] is killed.
class SimpleIsolateAbortException implements Exception {
  String cause;
  SimpleIsolateAbortException(this.cause);
}

/// Wrapper type around Dart [Isolate].
class SimpleIsolate<R> {
  /// Gets the internal [Isolate].
  final Isolate core;

  /// Gets the `Future<R>` of entrypoint function.
  final Future<R> future;

  final int _sendPortMsgHead;
  final Future<SendPort> _sendPortFuture;
  SISendPort? _sendPort;

  SimpleIsolate._(
    this.core,
    this.future,
    this._sendPortMsgHead,
    this._sendPortFuture,
  );

  /// Sends a message to the internal isolate with the given [name] and [params].
  Future<void> sendMsgToIsolate(
      String name, Map<String, dynamic>? params) async {
    _sendPort ??= SISendPort(await _sendPortFuture, _sendPortMsgHead);
    _sendPort!.sendMsg(name, params);
  }

  /// Kills the internal [Isolate].
  void kill({bool? immediate}) {
    if (immediate == true) {
      core.kill(priority: Isolate.immediate);
    } else {
      core.kill();
    }
  }

  /// Spawns an isolate with the given [entrypoint] function and [argument].
  static Future<SimpleIsolate<T>> spawn<T>(
      Future<T> Function(SIContext ctx) entryPoint, dynamic argument,
      {void Function(SIMsg msg)? onMsgReceived,
      void Function(dynamic argument)? onSpawn}) async {
    var rp = ReceivePort();
    var completer = Completer<T>();
    SendPort? sp;
    var spCompleter = Completer<SendPort>();
    var isDone = false;

    rp.listen((dynamic dynRawMsg) {
      if (dynRawMsg == null && !isDone) {
        // Cancelled.
        rp.close();
        completer.completeError(
            SimpleIsolateAbortException('The [Isolate] is cancelled'));
      } else {
        var rawMsg = dynRawMsg as List<dynamic>;
        var type = _MsgHead.values[rawMsg[0] as int];
        switch (type) {
          case _MsgHead.done:
            {
              isDone = true;
              rp.close();
              completer.complete(rawMsg[1] as T);
              break;
            }

          case _MsgHead.err:
            {
              rp.close();
              completer.completeError(rawMsg[1] as Object,
                  StackTrace.fromString(rawMsg[2] as String));
              break;
            }

          case _MsgHead.load:
            {
              sp = rawMsg[1] as SendPort;
              spCompleter.complete(sp);
              break;
            }

          case _MsgHead.userMsg:
            {
              onMsgReceived?.call(SIMsg.fromRawMsg(rawMsg[1]));
              break;
            }

          default:
            {
              throw Exception('Unknown _MsgHead value $type');
            }
        }
      }
    });

    List<dynamic> entryRawParam = <dynamic>[
      rp.sendPort,
      argument,
    ];

    var iso = await Isolate.spawn(
        _makeEntryFunc(entryPoint, onSpawn), entryRawParam,
        onExit: rp.sendPort);
    return SimpleIsolate<T>._(iso, completer.future,
        _MsgHeadInIsolate.userMsg.index, spCompleter.future);
  }

  static void Function(List<dynamic> rawMsg) _makeEntryFunc<T>(
      Future<T> Function(SIContext ctx) entryPoint,
      void Function(dynamic argument)? onSpawn) {
    return (List<dynamic> rawMsg) async {
      var sp = rawMsg[0] as SendPort;
      // ignore: implicit_dynamic_variable
      var argument = rawMsg[1];
      var ctx = SIContext(argument, SISendPort(sp, _MsgHead.userMsg.index));
      onSpawn?.call(ctx.argument);
      var rp = ReceivePort();
      rp.listen((dynamic dynRawMsg) {
        var rawMsg = dynRawMsg as List<dynamic>;
        var type = _MsgHeadInIsolate.values[rawMsg[0] as int];
        switch (type) {
          case _MsgHeadInIsolate.userMsg:
            {
              ctx.onMsgReceivedInIsolate?.call(SIMsg.fromRawMsg(rawMsg[1]));
              break;
            }

          default:
            {
              throw Exception('Unknown _MsgHeadInIsolate value $type');
            }
        }
      });

      try {
        sp.send([_MsgHead.load.index, rp.sendPort]);
        var result = await entryPoint(ctx);
        sp.send([_MsgHead.done.index, result]);
      } catch (err, stacktrace) {
        sp.send([_MsgHead.err.index, err, stacktrace.toString()]);
      } finally {
        rp.close();
      }
    };
  }
}
