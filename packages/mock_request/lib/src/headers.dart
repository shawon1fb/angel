import 'dart:io';

class MockHttpHeaders extends HttpHeaders {
  final Map<String, List<String>> _data = {};
  final List<String> _noFolding = [];
  Uri? _host;

  List<String> get doNotFold => List<String>.unmodifiable(_noFolding);

  @override
  ContentType get contentType {
    if (_data.containsKey(HttpHeaders.contentTypeHeader)) {
      return ContentType.parse(_data[HttpHeaders.contentTypeHeader]!.join(','));
    } else {
      return ContentType.html;
    }
  }

  @override
  set contentType(ContentType? value) =>
      set(HttpHeaders.contentTypeHeader, value?.value ?? ContentType.html);

  @override
  DateTime get date => _data.containsKey(HttpHeaders.dateHeader)
      ? HttpDate.parse(_data[HttpHeaders.dateHeader]!.join(','))
      : DateTime.now();

  @override
  set date(DateTime? value) =>
      set(HttpHeaders.dateHeader, HttpDate.format(value ?? DateTime.now()));

  @override
  DateTime get expires => _data.containsKey(HttpHeaders.expiresHeader)
      ? HttpDate.parse(_data[HttpHeaders.expiresHeader]!.join(','))
      : DateTime.now();

  @override
  set expires(DateTime? value) =>
      set(HttpHeaders.expiresHeader, HttpDate.format(value ?? DateTime.now()));

  @override
  DateTime get ifModifiedSince =>
      _data.containsKey(HttpHeaders.ifModifiedSinceHeader)
          ? HttpDate.parse(_data[HttpHeaders.ifModifiedSinceHeader]!.join(','))
          : DateTime.now();

  @override
  set ifModifiedSince(DateTime? value) => set(HttpHeaders.ifModifiedSinceHeader,
      HttpDate.format(value ?? DateTime.now()));

  @override
  String? get host {
    if (_host != null) {
      return _host!.host;
    } else if (_data.containsKey(HttpHeaders.hostHeader)) {
      _host = Uri.parse(_data[HttpHeaders.hostHeader]!.join(','));
      return _host!.host;
    } else {
      return null;
    }
  }

  @override
  int? get port {
    host; // Parse it
    return _host?.port;
  }

  @override
  List<String>? operator [](String name) => _data[name.toLowerCase()];

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    var lower = preserveHeaderCase ? name : name.toLowerCase();

    if (_data.containsKey(lower)) {
      if (value is Iterable) {
        _data[lower]!.addAll(value.map((x) => x.toString()).toList());
      } else {
        _data[lower]!.add(value.toString());
      }
    } else {
      if (value is Iterable) {
        _data[lower] = value.map((x) => x.toString()).toList();
      } else {
        _data[lower] = [value.toString()];
      }
    }
  }

  @override
  void clear() {
    _data.clear();
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _data.forEach(action);
  }

  @override
  void noFolding(String name) {
    _noFolding.add(name.toLowerCase());
  }

  @override
  void remove(String name, Object value) {
    var lower = name.toLowerCase();

    if (_data.containsKey(lower)) {
      if (value is Iterable) {
        for (var x in value) {
          _data[lower]!.remove(x.toString());
        }
      } else {
        _data[lower]!.remove(value.toString());
      }
    }
  }

  @override
  void removeAll(String name) {
    _data.remove(name.toLowerCase());
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    var lower = preserveHeaderCase ? name : name.toLowerCase();
    _data.remove(lower);

    if (value is Iterable) {
      _data[lower] = value.map((x) => x.toString()).toList();
    } else {
      _data[lower] = [value.toString()];
    }
  }

  @override
  String? value(String name) => _data[name.toLowerCase()]?.join(',');

  @override
  String toString() {
    var b = StringBuffer();
    _data.forEach((k, v) {
      b.write('$k: ');
      b.write(v.join(','));
      b.writeln();
    });
    return b.toString();
  }
}
