import 'dart:async';
import 'dart:isolate';

/// A wrapper around [SendPort] to send [SIMsg].
class SISendPort {
  /// [SISendPort] usually embeds message boy into another message identified with [headType].
  /// See [_MsgHead] enum for details.
  final int _headType;
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
class SIContext<T> {
  /// The argument passed in [SimpleIsolate.spawn].
  final T argument;

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

/// Wrapper type around Dart [Isolate].
class SimpleIsolate<R> {
  final Isolate core;
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

  /// Spawns an isolate with the given [entrypoint] function and [argument].
  static Future<SimpleIsolate> spawn<T, R>(
      Future<R> Function(SIContext<T> ctx) entryPoint, T argument,
      {void Function(SIMsg msg)? onMsgReceived}) async {
    var rp = ReceivePort();
    var completer = Completer<R>();
    SendPort? sp;
    var spCompleter = Completer<SendPort>();

    rp.listen((dynamic dynRawMsg) {
      var rawMsg = dynRawMsg as List<dynamic>;
      var type = _MsgHead.values[rawMsg[0] as int];
      switch (type) {
        case _MsgHead.done:
          {
            rp.close();
            completer.complete(rawMsg[1] as R);
            break;
          }

        case _MsgHead.err:
          {
            rp.close();
            completer.completeError(rawMsg[1] as Object);
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
    });

    List<dynamic> entryRawParam = <dynamic>[
      rp.sendPort,
      argument,
    ];

    var iso = await Isolate.spawn(_makeEntryFunc(entryPoint), entryRawParam);
    return SimpleIsolate<R>._(iso, completer.future,
        _MsgHeadInIsolate.userMsg.index, spCompleter.future);
  }

  static void Function(List<dynamic> rawMsg) _makeEntryFunc<T, R>(
      Future<R> Function(SIContext<T> ctx) entryPoint) {
    return (List<dynamic> rawMsg) async {
      var sp = rawMsg[0] as SendPort;
      var argument = rawMsg[1] as T;
      var ctx = SIContext(argument, SISendPort(sp, _MsgHead.userMsg.index));
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
      } catch (err) {
        sp.send([_MsgHead.err.index, err]);
      } finally {
        rp.close();
      }
    };
  }
}