// lib/db/database_connection.dart
import 'package:flutter/foundation.dart';
import 'package:mysql1/mysql1.dart';
import 'package:inboundgenie/db_config.dart'; // adjust package path if needed

class DatabaseConnection {
  /// Connects to MySQL and ensures the session uses the configured DB.
  static Future<MySqlConnection?> connect() async {
    try {
      final settings = ConnectionSettings(
        host: DBConfig.host,
        port: DBConfig.port,
        user: DBConfig.user,
        password: DBConfig.password,
        db: DBConfig.db,
        // initial DB setting (may be null on some servers)
      );

      final conn = await MySqlConnection.connect(settings);
      debugPrint('✅ Connected to MySQL');

      // Try to explicitly set the session default DB (some setups need explicit USE).
      try {
        await conn.query('USE `${DBConfig.db}`');

        var result = await conn.query('SELECT DATABASE()');
        print('Current DB: ${result.first[0]}');

        final curDbRes = await conn.query('SELECT DATABASE()');
        final curDb = curDbRes.isNotEmpty ? curDbRes.first[0] : null;
        debugPrint('After USE, current DB: $curDb');
      } catch (e) {
        debugPrint('Warning: unable to set default DB for session: $e');
      }

      return conn;
    } catch (e) {
      debugPrint('❌ Database connection error: $e');
      return null;
    }
  }

  /// Close connection safely.
  static Future<void> close(MySqlConnection? conn) async {
    if (conn != null) {
      try {
        await conn.close();
      } catch (e) {
        debugPrint('Error closing DB connection: $e');
      }
    }
  }

  /// Verbose diagnostic to inspect server / database / table state.
  /// Call this in debug mode (or behind a debug button) to avoid production noise.
  static Future<void> printTables() async {
    MySqlConnection? conn;
    try {
      conn = await connect();
      if (conn == null) {
        debugPrint('Could not connect to DB.');
        return;
      }

      // 1) Current database
      try {
        final curDbRes = await conn.query('SELECT DATABASE()');
        final curDb = curDbRes.isNotEmpty ? curDbRes.first[0] : null;
        debugPrint('Current database (SELECT DATABASE()): $curDb');
      } catch (e) {
        debugPrint('Error getting current database: $e');
      }

      // 2) List databases on server
      try {
        final dbs = await conn.query('SHOW DATABASES');
        debugPrint('--- Databases on server ---');
        for (var r in dbs) {
          if (r.isNotEmpty) debugPrint(r[0].toString());
        }
      } catch (e) {
        debugPrint('Error running SHOW DATABASES: $e');
      }

      // 3) SHOW TABLES for the session default DB
      try {
        final results = await conn.query('SHOW TABLES');
        debugPrint('--- SHOW TABLES (default DB) ---');
        var count = 0;
        for (var row in results) {
          if (row.isNotEmpty) debugPrint(row[0].toString());
          count++;
        }
        debugPrint('Total tables (SHOW TABLES): $count');
      } catch (e) {
        debugPrint('Error running SHOW TABLES: $e');
      }

      // 4) SHOW TABLES FROM the configured DB (explicit)
      try {
        final results2 = await conn.query('SHOW TABLES FROM `${DBConfig.db}`');
        debugPrint('--- SHOW TABLES FROM ${DBConfig.db} ---');
        var count2 = 0;
        for (var row in results2) {
          if (row.isNotEmpty) debugPrint(row[0].toString());
          count2++;
        }
        debugPrint('Total tables (FROM ${DBConfig.db}): $count2');
      } catch (e) {
        debugPrint('Error running SHOW TABLES FROM ${DBConfig.db}: $e');
      }

      // 5) Count tables in information_schema for the configured schema
      try {
        final infoRes = await conn.query(
          "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = ?",
          [DBConfig.db],
        );
        final cnt = infoRes.isNotEmpty ? infoRes.first[0] : 0;
        debugPrint('information_schema count for ${DBConfig.db}: $cnt');
      } catch (e) {
        debugPrint('Error querying information_schema: $e');
      }

      // 6) Describe user_master (fully-qualified) safely
      try {
        final desc = await conn.query('DESCRIBE `${DBConfig.db}`.`user_master`');
        debugPrint('--- DESCRIBE ${DBConfig.db}.user_master ---');
        if (desc.isEmpty) {
          debugPrint('DESCRIBE returned no rows (table may not exist or insufficient privileges).');
        } else {
          for (var r in desc) {
            final field = r.length > 0 ? r[0] : null;
            final type = r.length > 1 ? r[1] : null;
            final nullable = r.length > 2 ? r[2] : null;
            debugPrint('$field\t$type\t$nullable');
          }
        }
      } catch (e) {
        debugPrint('DESCRIBE user_master error (table may not exist or insufficient privileges): $e');
      }
    } catch (e) {
      debugPrint('enhancedPrintTables unexpected error: $e');
    } finally {
      if (conn != null) {
        await close(conn);
      }
    }
  }

  /// Test helper: selects up to 5 rows from inspectGenieDB.user_master using a fully-qualified query.
  /// Prints rows (id, name, email) if accessible.
  static Future<void> testUserMaster({int limit = 5}) async {
    MySqlConnection? conn;
    try {
      conn = await connect();
      if (conn == null) {
        debugPrint('Could not connect to DB for testUserMaster.');
        return;
      }

      // confirm current DB
      try {
        final cur = await conn.query('SELECT DATABASE()');
        debugPrint('Cur DB: ${cur.isNotEmpty ? cur.first[0] : null}');
      } catch (_) {}

      // list tables explicitly from configured DB
      try {
        final tables = await conn.query('SHOW TABLES FROM `${DBConfig.db}`');
        debugPrint('Tables in ${DBConfig.db}:');
        for (var r in tables) {
          if (r.isNotEmpty) debugPrint(' - ${r[0]}');
        }
      } catch (e) {
        debugPrint('Error listing tables from ${DBConfig.db}: $e');
      }

      // sample select (fully-qualified)
      try {
        final sample = await conn.query(
          'SELECT id, name, email FROM `${DBConfig.db}`.`user_master` LIMIT ?',
          [limit],
        );

        if (sample.isEmpty) {
          debugPrint('No rows returned from ${DBConfig.db}.user_master (or table missing / no SELECT priv).');
        } else {
          for (var row in sample) {
            final id = row.length > 0 ? row[0] : null;
            final name = row.length > 1 ? row[1] : null;
            final email = row.length > 2 ? row[2] : null;
            debugPrint('row: id=$id, name=$name, email=$email');
          }
        }
      } catch (e) {
        debugPrint('Sample select error from user_master: $e');
      }
    } catch (e) {
      debugPrint('testUserMaster unexpected error: $e');
    } finally {
      if (conn != null) {
        await close(conn);
      }
    }
  }
}
