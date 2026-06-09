/* Minimal EVA entry point: exercises sqlite open/exec/close on an
   in-memory DB so EVA has a `main` to analyze against sqlite3.c. */
#include "sqlite3.h"
int main(void) {
  sqlite3 *db;
  if (sqlite3_open(":memory:", &db) != 0) return 1;
  sqlite3_exec(db, "CREATE TABLE t(x INTEGER);", 0, 0, 0);
  sqlite3_exec(db, "INSERT INTO t VALUES(42);", 0, 0, 0);
  sqlite3_close(db);
  return 0;
}
