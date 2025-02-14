part of angel3_mongo.services;

/// Manipulates data from MongoDB as Maps.
class MongoService extends Service<String, Map<String, dynamic>> {
  DbCollection collection;

  /// If set to `true`, clients can remove all items by passing a `null` `id` to `remove`.
  ///
  /// `false` by default.
  final bool allowRemoveAll;

  /// If set to `true`, parameters in `req.query` are applied to the database query.
  final bool allowQuery;

  MongoService(this.collection,
      {this.allowRemoveAll = false, this.allowQuery = true})
      : super();

  SelectorBuilder? _makeQuery([Map<String, dynamic>? params_]) {
    var params = Map.from(params_ ?? {});
    params = params..remove('provider');
    var result = where.exists('_id');

    // You can pass a SelectorBuilder as 'query';
    if (params['query'] is SelectorBuilder) {
      return params['query'] as SelectorBuilder?;
    }

    for (var key in params.keys) {
      if (key == r'$sort' ||
          key == r'$query' &&
              (allowQuery == true || !params.containsKey('provider'))) {
        if (params[key] is Map) {
          // If they send a map, then we'll sort by every key in the map

          for (var fieldName in params[key].keys.where((x) => x is String)) {
            var sorter = params[key][fieldName];
            if (sorter is num && fieldName is String) {
              result = result.sortBy(fieldName, descending: sorter == -1);
            } else if (sorter is String && fieldName is String) {
              result = result.sortBy(fieldName, descending: sorter == '-1');
            } else if (sorter is SelectorBuilder) {
              result = result.and(sorter);
            }
          }
        } else if (params[key] is String && key == r'$sort') {
          // If they send just a string, then we'll sort
          // by that, ascending
          result = result.sortBy(params[key] as String);
        }
      } else if (key == 'query' &&
          (allowQuery == true || !params.containsKey('provider'))) {
        var query = params[key] as Map?;
        query?.forEach((key, v) {
          var value = v is Map<String, dynamic> ? _filterNoQuery(v) : v;

          if (!_noQuery.contains(key) &&
              value is! RequestContext &&
              value is! ResponseContext) {
            result = result.and(where.eq(key as String, value));
          }
        });
      }
    }

    return result;
  }

  Map<String, dynamic> _jsonify(Map<String, dynamic> doc,
      [Map<String, dynamic>? params]) {
    var result = <String, dynamic>{};

    for (var key in doc.keys) {
      var value = doc[key];
      if (value is ObjectId) {
        result[key] = value.toHexString();
      } else if (value is! RequestContext && value is! ResponseContext) {
        result[key] = value;
      }
    }

    return _transformId(result);
  }

  @override
  Future<List<Map<String, dynamic>>> index(
      [Map<String, dynamic>? params]) async {
    return await (collection.find(_makeQuery(params)))
        .map((x) => _jsonify(x, params))
        .toList();
  }

  static const String _nonceKey = '__angel__mongo__nonce__key__';

  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> data,
      [Map<String, dynamic>? params]) async {
    var item = _removeSensitive(data);

    try {
      var nonce = (await collection.db.getNonce())['nonce'] as String?;
      var result = await (collection.findAndModify(
          query: where.eq(_nonceKey, nonce),
          update: item,
          returnNew: true,
          upsert: true) as FutureOr<Map<String, dynamic>>);
      return _jsonify(result);
    } catch (e, st) {
      throw AngelHttpException(stackTrace: st);
    }
  }

  @override
  Future<Map<String, dynamic>> findOne(
      [Map<String, dynamic>? params,
      String errorMessage =
          'No record was found matching the given query.']) async {
    var found = await collection.findOne(_makeQuery(params));

    if (found == null) {
      throw AngelHttpException.notFound(message: errorMessage);
    }

    return _jsonify(found, params);
  }

  @override
  Future<Map<String, dynamic>> read(String id,
      [Map<String, dynamic>? params]) async {
    var _id = _makeId(id);
    var found =
        await collection.findOne(where.id(_id).and(_makeQuery(params)!));

    if (found == null) {
      throw AngelHttpException.notFound(
          message: 'No record found for ID ${_id.toHexString()}');
    }

    return _jsonify(found, params);
  }

  @override
  Future<List<Map<String, dynamic>>> readMany(List<String> ids,
      [Map<String, dynamic>? params]) async {
    var q = _makeQuery(params);
    q = ids.fold(q, (q, id) => q!.or(where.id(_makeId(id))));
    return await (collection.find(q)).map((x) => _jsonify(x, params)).toList();
  }

  @override
  Future<Map<String, dynamic>> modify(String id, data,
      [Map<String, dynamic>? params]) async {
    Map<String, dynamic> target;

    try {
      target = await read(id, params);
    } on AngelHttpException catch (e) {
      if (e.statusCode == 404) {
        return await create(data, params);
      } else {
        rethrow;
      }
    }

    var result = mergeMap([target, _removeSensitive(data)]);
    //result['updatedAt'] = new DateTime.now().toIso8601String();

    try {
      var modified = await (collection.findAndModify(
          query: where.id(_makeId(id)),
          update: result,
          returnNew: true) as FutureOr<Map<String, dynamic>>);
      result = _jsonify(modified, params);
      result['id'] = _makeId(id).toHexString();
      return result;
    } catch (e, st) {
      //printDebug(e, st, 'MODIFY');
      throw AngelHttpException(stackTrace: st);
    }
  }

  @override
  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> data,
      [Map<String, dynamic>? params]) async {
    var result = _removeSensitive(data);
    result['_id'] = _makeId(id);
    /*result['createdAt'] =
        target is Map ? target['createdAt'] : target.createdAt;

    if (result['createdAt'] is DateTime)
      result['createdAt'] = result['createdAt'].toIso8601String();

    result['updatedAt'] = new DateTime.now().toIso8601String();*/

    try {
      var updated = await (collection.findAndModify(
          query: where.id(_makeId(id)),
          update: result,
          returnNew: true,
          upsert: true) as FutureOr<Map<String, dynamic>>);
      result = _jsonify(updated, params);
      result['id'] = _makeId(id).toHexString();
      return result;
    } catch (e, st) {
      //printDebug(e, st, 'UPDATE');
      throw AngelHttpException(stackTrace: st);
    }
  }

  @override
  Future<Map<String, dynamic>> remove(String id,
      [Map<String, dynamic>? params]) async {
    if (id == 'null') {
      // Remove everything...
      if (!(allowRemoveAll == true ||
          params?.containsKey('provider') != true)) {
        throw AngelHttpException.forbidden(
            message: 'Clients are not allowed to delete all items.');
      } else {
        await collection.remove(null);
        return {};
      }
    }

    // var result = await read(id, params);

    try {
      var result = await (collection.findAndModify(
          query: where.id(_makeId(id)),
          remove: true) as FutureOr<Map<String, dynamic>>);
      return _jsonify(result);
    } catch (e, st) {
      //printDebug(e, st, 'REMOVE');
      throw AngelHttpException(stackTrace: st);
    }
  }
}
