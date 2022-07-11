import 'dart:async';
import 'dart:convert';
import 'package:angel3_orm/angel3_orm.dart';
import 'package:logging/logging.dart';
import 'package:pool/pool.dart';
import 'package:postgres/postgres.dart';

/// A [QueryExecutor] that queries a PostgreSQL database.
class PostgreSqlExecutor extends QueryExecutor {
  PostgreSQLExecutionContext _connection;

  /// An optional [Logger] to print information to. A default logger will be used
  /// if not set
  late Logger logger;

  PostgreSqlExecutor(this._connection, {Logger? logger}) {
    this.logger = logger ?? Logger('PostgreSqlExecutor');
  }

  final Dialect _dialect = const PostgreSQLDialect();

  @override
  Dialect get dialect => _dialect;

  /// The underlying connection.
  PostgreSQLExecutionContext get connection => _connection;

  /// Closes the connection.
  Future close() {
    if (_connection is PostgreSQLConnection) {
      return (_connection as PostgreSQLConnection).close();
    } else {
      return Future.value();
    }
  }

  @override
  Future<PostgreSQLResult> query(
      String tableName, String query, Map<String, dynamic> substitutionValues,
      {String returningQuery = '', List<String> returningFields = const []}) {
    if (returningFields.isNotEmpty) {
      var fields = returningFields.join(', ');
      var returning = 'RETURNING $fields';
      query = '$query $returning';
    }

    //logger.fine('Query: $query');
    //logger.fine('Values: $substitutionValues');

    // Convert List into String
    var param = <String, dynamic>{};
    substitutionValues.forEach((key, value) {
      if (value is List) {
        param[key] = jsonEncode(value);
      } else {
        param[key] = value;
      }
    });

    return _connection
        .query(query, substitutionValues: param)
        .catchError((err) async {
      logger.warning(err);
      if (err is PostgreSQLException) {
        // This is a hack to detect broken db connection
        bool brokenConnection =
            err.message?.contains("connection is not open") ?? false;
        if (brokenConnection) {
          if (_connection is PostgreSQLConnection) {
            // Open a new db connection
            var currentConnection = _connection as PostgreSQLConnection;
            currentConnection.close();

            logger.warning(
                "A broken database connection is detected. Creating a new database connection.");
            var conn = _createNewConnection(currentConnection);
            await conn.open();
            _connection = conn;

            // Retry the query with the new db connection
            return _connection.query(query, substitutionValues: param);
          }
        }
      }
      throw err;
    });
  }

  // Create a new database connection from an existing connection
  PostgreSQLConnection _createNewConnection(PostgreSQLConnection conn) {
    return PostgreSQLConnection(conn.host, conn.port, conn.databaseName,
        username: conn.username,
        password: conn.password,
        useSSL: conn.useSSL,
        timeZone: conn.timeZone,
        timeoutInSeconds: conn.timeoutInSeconds);
  }

  @override
  Future<T> transaction<T>(FutureOr<T> Function(QueryExecutor) f) async {
    if (_connection is! PostgreSQLConnection) {
      return await f(this);
    }

    var conn = _connection as PostgreSQLConnection;
    T? returnValue;

    var txResult = await conn.transaction((ctx) async {
      try {
        logger.fine('Entering transaction');
        var tx = PostgreSqlExecutor(ctx, logger: logger);
        returnValue = await f(tx);

        return returnValue;
      } catch (e) {
        ctx.cancelTransaction(reason: e.toString());
        rethrow;
      } finally {
        logger.fine('Exiting transaction');
      }
    });

    if (txResult is PostgreSQLRollback) {
      //if (txResult.reason == null) {
      //  throw StateError('The transaction was cancelled.');
      //} else {
      throw StateError(
          'The transaction was cancelled with reason "${txResult.reason}".');
      //}
    } else {
      return returnValue!;
    }
  }
}

/// A [QueryExecutor] that manages a pool of PostgreSQL connections.
class PostgreSqlExecutorPool extends QueryExecutor {
  /// The maximum amount of concurrent connections.
  final int size;

  /// Creates a new [PostgreSQLConnection], on demand.
  ///
  /// The created connection should **not** be open.
  final PostgreSQLConnection Function() connectionFactory;

  /// An optional [Logger] to print information to.
  late Logger logger;

  final List<PostgreSqlExecutor> _connections = [];
  int _index = 0;
  final Pool _pool, _connMutex = Pool(1);

  PostgreSqlExecutorPool(this.size, this.connectionFactory, {Logger? logger})
      : _pool = Pool(size) {
    if (logger != null) {
      this.logger = logger;
    } else {
      this.logger = Logger('PostgreSqlExecutorPool');
    }

    assert(size > 0, 'Connection pool cannot be empty.');
  }

  final Dialect _dialect = const PostgreSQLDialect();

  @override
  Dialect get dialect => _dialect;

  /// Closes all connections.
  Future close() async {
    await _pool.close();
    await _connMutex.close();
    return Future.wait(_connections.map((c) => c.close()));
  }

  Future _open() async {
    if (_connections.isEmpty) {
      _connections.addAll(await Future.wait(List.generate(size, (_) async {
        logger.fine('Spawning connections...');
        var conn = connectionFactory();
        await conn.open();
        //return conn
        //    .open()
        //    .then((_) => PostgreSqlExecutor(conn, logger: logger));
        return PostgreSqlExecutor(conn, logger: logger);
      })));
    }
  }

  Future<PostgreSqlExecutor> _next() {
    return _connMutex.withResource(() async {
      await _open();
      if (_index >= size) _index = 0;
      return _connections[_index++];
    });
  }

  @override
  Future<PostgreSQLResult> query(
      String tableName, String query, Map<String, dynamic> substitutionValues,
      {String returningQuery = '', List<String> returningFields = const []}) {
    return _pool.withResource(() async {
      var executor = await _next();
      return executor.query(tableName, query, substitutionValues,
          returningFields: returningFields);
    });
  }

  @override
  Future<T> transaction<T>(FutureOr<T> Function(QueryExecutor) f) {
    return _pool.withResource(() async {
      var executor = await _next();
      return executor.transaction(f);
    });
  }
}
