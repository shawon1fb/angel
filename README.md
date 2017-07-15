# orm
[![Pub](https://img.shields.io/pub/v/angel_orm.svg)](https://pub.dartlang.org/packages/angel_orm)
[![build status](https://travis-ci.org/angel-dart/orm.svg)](https://travis-ci.org/angel-dart/orm)

Source-generated PostgreSQL ORM for use with the
[Angel framework](https://angel-dart.github.io).
Now you can combine the power and flexibility of Angel with a strongly-typed ORM.

* [Usage](#usage)
* [Model Definitions](#models)
* [MVC Example](#example)
* [Relationships](#relations)

# Usage
You'll need these dependencies in your `pubspec.yaml`:
```yaml
dependencies:
  angel_orm: ^1.0.0-alpha
dev_dependencies:
  angel_orm_generator: ^1.0.0-alpha
  build_runner: ^0.3.0
```

`package:angel_orm_generator` exports two classes that you can include
in a `package:build` flow:
* `PostgreORMGenerator` - Fueled by `package:source_gen`; include this within a `GeneratorBuilder`.
* `SQLMigrationGenerator` - This is its own `Builder`; it generates a SQL schema, as well as a SQL script to drop a generated table.

You should pass an `InputSet` containing your project's models.

# Models
Your model, courtesy of `package:angel_serialize`:

```dart
library angel_orm.test.models.car;

import 'package:angel_framework/common.dart';
import 'package:angel_orm/angel_orm.dart';
import 'package:angel_serialize/angel_serialize.dart';
part 'car.g.dart';

@serializable
@orm
class _Car extends Model {
  String make;
  String description;
  bool familyFriendly;
  DateTime recalledAt;
}
```

Models can use the `@Alias()` annotation; `package:angel_orm` obeys it.

After building, you'll have access to a `Query` class with strongly-typed methods that
allow to run asynchronous queries without a headache.

**IMPORTANT:** The ORM *assumes* that you are using `package:angel_serialize`, and will only generate code
designed for such a workflow. Save yourself a headache and build models with `angel_serialize`:

https://github.com/angel-dart/serialize

# Example

MVC just got a whole lot easier:

```dart
import 'package:angel_framework/angel_framework.dart';
import 'package:postgres/postgres.dart';
import 'car.dart';
import 'car.orm.g.dart';

/// Returns an Angel plug-in that connects to a PostgreSQL database, and sets up a controller connected to it...
AngelConfigurer connectToCarsTable(PostgreSQLConnection connection) {
  return (Angel app) async {
    // Register the connection with Angel's dependency injection system.
    // 
    // This means that we can use it as a parameter in routes and controllers.
    app.container.singleton(connection);
    
    // Attach the controller we create below
    await app.configure(new CarController(connection));
  };
}

@Expose('/cars')
class CarController extends Controller {
  // The `connection` will be injected.
  @Expose('/recalled_since_2008')
  carsRecalledSince2008(PostgreSQLConnection connection) {
    // Instantiate a Car query, which is auto-generated. This class helps us build fluent queries easily.
    var cars = new CarQuery();
    cars.where
      ..familyFriendly.equals(false)
      ..recalledAt.year.greaterThanOrEqualTo(2008);
    
    // Shorter syntax we could use instead...
    cars.where.recalledAt.year <= 2008;
    
    // `get()` returns a Stream.
    // `get().toList()` returns a Future.
    return cars.get(connection).toList();
  }
  
  @Expose('/create', method: 'POST')
  createCar(PostgreSQLConnection connection) async {
    // `package:angel_orm` generates a strongly-typed `insert` function on the query class.
    // Say goodbye to typos!!!
    var car = await CarQuery.insert(connection, familyFriendly: true, make: 'Honda');
    
    // Auto-serialized using code generated by `package:angel_serialize`
    return car;
  }
}
```

# Relations
**NOTE**: This is not yet implemented. Expect to see more documentation about this soon.

* `@HasOne()`
* `@HasMany()`
* `@BelongsTo()`

```dart
@serializable
@orm
abstract class _Author extends Model {
  @hasMany // Use the defaults, and auto-compute `foreignKey`
  List<Book> books;
  
  // Also supports parameters...
  @HasMany(localKey: 'id', foreignKey: 'author_id', cascadeOnDelete: true)
  List<Book> books;
  
  @Alias('writing_utensil')
  @hasOne
  Pen pen;
}
```