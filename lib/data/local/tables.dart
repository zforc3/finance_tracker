import 'package:drift/drift.dart';

@DataClassName('TransactionEntry')
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  IntColumn get amount => integer()();
  TextColumn get type => text()(); // 'income' | 'expense'
  TextColumn get category => text()();
  TextColumn get note => text().nullable()();
  TextColumn get date => text()(); // 'YYYY-MM-DD'
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))(); // 'pending' | 'synced' | 'conflict'
  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncOutboxEntry')
class SyncOutbox extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text()();
  TextColumn get action => text()(); // 'create' | 'update' | 'delete'
  IntColumn get baseVersion => integer().withDefault(const Constant(0))();
  TextColumn get payload => text()(); // JSON string
  TextColumn get status => text().withDefault(const Constant('pending'))(); // 'pending' | 'in_flight' | 'failed' | 'conflict'
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncStateEntry')
class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
