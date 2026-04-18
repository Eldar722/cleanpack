// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:js' as js;

Future<void> webLoadModel(String url) async {
  if (!js.context.hasProperty('loadYoloModel')) return;
  final promise = js.context.callMethod('loadYoloModel', [url]);
  await _promiseToFuture(promise);
}

Future<String> webDetect(dynamic frame) async {
  if (!js.context.hasProperty('detectOnVideo')) return '[]';
  final promise = js.context.callMethod('detectOnVideo');
  final result = await _promiseToFuture(promise);
  return (result as String?) ?? '[]';
}

Future<dynamic> _promiseToFuture(dynamic promise) {
  final c = Completer<dynamic>();
  final then = js.JsFunction.withThis((self, result) => c.complete(result));
  final catch_ = js.JsFunction.withThis((self, error) => c.completeError(Object()));
  (promise as js.JsObject).callMethod('then', [then]);
  (promise).callMethod('catch', [catch_]);
  return c.future;
}
