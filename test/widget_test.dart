import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

void main() async {
  var handler = Pipeline().addMiddleware(logRequests()).addHandler((Request request) {
    if (request.url.path == 'getData') {
      return Response.ok('Hello from host!');
    }
    return Response.notFound('Not found');
  });

  var server = await io.serve(handler, InternetAddress.anyIPv4, 8080);
  print('Server running at http://${server.address.address}:8080');
}