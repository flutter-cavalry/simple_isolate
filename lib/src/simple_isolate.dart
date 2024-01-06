import 'dart:async';
import 'dart:isolate';

/// A wrapper around [SendPort] to send [SIMsg].
class SISendPort {
  /// [SISendPort] usually embeds message boy into another message identified by [headType].
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
    final rawMsg = dynRawMsg as List<dynamic>;
    final msgName = rawMsg[0] as String;
    final params = rawMsg[1] as Map<String, dynamic>?;
    return SIMsg(msgName, params);
  }

  @override
  String toString() {
    final paramStr = params != null ? params.toString() : '<null>';
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
  final Isolate? core;

  /// Gets the `Future<R>` of entrypoint function.
  final Future<R> future;

  final int _sendPortMsgHead;
  final Future<SendPort?> _sendPortFuture;
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
    final sp = await _sendPortFuture;
    if (sp == null) {
      throw Exception('`SendPort` is null. Make sure `bidirectional` is true.');
    }
    _sendPort ??= SISendPort(sp, _sendPortMsgHead);
    _sendPort!.sendMsg(name, params);
  }

  /// Kills the internal [Isolate].
  void kill({bool? immediate}) {
    if (immediate == true) {
      core?.kill(priority: Isolate.immediate);
    } else {
      core?.kill();
    }
  }

  /// Spawns an isolate with the given [entrypoint] function and [argument].
  static Future<SimpleIsolate<T>> spawn<T>(
      Future<T> Function(SIContext ctx) entryPoint, dynamic argument,
      {void Function(SIMsg msg)? onMsgReceived,
      void Function(dynamic argument)? onSpawn,
      bool? debug,
      bool? bidirectional,
      String? debugName,
      bool? synchronous}) async {
    final rp = ReceivePort();
    final completer = Completer<T>();
    SendPort? sp;
    final spCompleter = Completer<SendPort?>();
    var isDone = false;

    void log(String msg) {
      if (debug ?? false) {
        // ignore: avoid_print
        print('[SimpleIsolate-out] $msg');
      }
    }

    rp.listen((dynamic dynRawMsg) {
      log('out-msg: $dynRawMsg');

      // Handle dart `onExit`.
      if (dynRawMsg == null) {
        if (!isDone) {
          log('out-msg: cancelled');
          // Cancelled.
          rp.close();
          completer.completeError(
              SimpleIsolateAbortException('The [Isolate] is cancelled'));
        } else {
          // if `isDone` is true, we have closed `rp` and completed `completer`, do nothing.
          log('out-msg: done (double checked)');
        }
        return;
      }

      if (dynRawMsg is List == false) {
        log('out-msg: msg not a list');
        rp.close();
        completer.completeError(
            Exception('dynRawMsg is not a list. Got $dynRawMsg'));
        return;
      }

      final rawList = dynRawMsg as List<dynamic>;

      // Handle dart `onError` messages.
      if (rawList[0] is String) {
        log('out-msg: onError');
        rp.close();
        completer.completeError(
            rawList[0] as String, StackTrace.fromString(rawList[1] as String));
        return;
      }

      // Handle our messages.
      final type = _MsgHead.values[rawList[0] as int];
      switch (type) {
        case _MsgHead.done:
          {
            log('out-msg: msg.done');
            isDone = true;
            rp.close();
            completer.complete(rawList[1] as T);
            break;
          }

        case _MsgHead.err:
          {
            log('out-msg: msg.err');
            rp.close();
            completer.completeError(rawList[1] as Object,
                StackTrace.fromString(rawList[2] as String));
            break;
          }

        case _MsgHead.load:
          {
            log('out-msg: msg.load');
            sp = rawList[1] as SendPort?;
            spCompleter.complete(sp);
            break;
          }

        case _MsgHead.userMsg:
          {
            log('out-msg: msg.userMsg');
            onMsgReceived?.call(SIMsg.fromRawMsg(rawList[1]));
            break;
          }

        default:
          {
            log('out-msg: msg.unknown');
            throw Exception('Unknown _MsgHead value $type');
          }
      }
    });

    final List<dynamic> entryRawParam = <dynamic>[
      rp.sendPort,
      argument,
    ];

    try {
      Isolate? isolate;
      final entryFn = _makeEntryFunc(
          entryPoint: entryPoint,
          onSpawn: onSpawn,
          debug: debug ?? false,
          bidirectional: bidirectional ?? false,
          synchronous: synchronous ?? false);
      if (synchronous ?? false) {
        entryFn(entryRawParam);
      } else {
        isolate = await Isolate.spawn(entryFn, entryRawParam,
            errorsAreFatal: true,
            onExit: rp.sendPort,
            onError: rp.sendPort,
            debugName: debugName);
      }

      return SimpleIsolate<T>._(isolate, completer.future,
          _MsgHeadInIsolate.userMsg.index, spCompleter.future);
    } catch (err) {
      rp.close();
      rethrow;
    }
  }

  static void Function(List<dynamic> rawMsg) _makeEntryFunc<T>(
      {required Future<T> Function(SIContext ctx) entryPoint,
      required void Function(dynamic argument)? onSpawn,
      required bool debug,
      required bool bidirectional,
      required bool synchronous}) {
    return (List<dynamic> rawMsg) async {
      void log(String msg) {
        if (debug) {
          // ignore: avoid_print
          print('[SimpleIsolate-in] $msg');
        }
      }

      final sp = rawMsg[0] as SendPort;
      // ignore: implicit_dynamic_variable
      final argument = rawMsg[1];
      final ctx = SIContext(argument, SISendPort(sp, _MsgHead.userMsg.index));
      onSpawn?.call(ctx.argument);
      ReceivePort? bidirectionalRP;
      if (bidirectional) {
        bidirectionalRP = ReceivePort();
        bidirectionalRP.listen((dynamic dynRawMsg) {
          log('in-msg: $dynRawMsg');
          final rawMsg = dynRawMsg as List<dynamic>;
          final type = _MsgHeadInIsolate.values[rawMsg[0] as int];
          switch (type) {
            case _MsgHeadInIsolate.userMsg:
              {
                log('in-msg: userMsg');
                ctx.onMsgReceivedInIsolate?.call(SIMsg.fromRawMsg(rawMsg[1]));
                break;
              }

            default:
              {
                log('in-msg: unknown');
                throw Exception('Unknown _MsgHeadInIsolate value $type');
              }
          }
        });
      }

      void finallyBlock() {
        log('body: finally running');
        bidirectionalRP?.close();
      }

      try {
        log('body: sending msgHead.load');
        sp.send([_MsgHead.load.index, bidirectionalRP?.sendPort]);
        log('body: running');
        final result = await entryPoint(ctx);
        log('body: sending msgHead.done');
        log('body: done');
        finallyBlock();
        if (synchronous) {
          sp.send([_MsgHead.done.index, result]);
        } else {
          Isolate.exit(sp, [_MsgHead.done.index, result]);
        }
      } catch (err, stacktrace) {
        log('body: err $err, $stacktrace');
        sp.send([_MsgHead.err.index, err, stacktrace.toString()]);
        finallyBlock();
      }
    };
  }
}
