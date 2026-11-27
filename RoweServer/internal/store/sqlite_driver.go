package store

/*
#cgo LDFLAGS: -lsqlite3
#include <sqlite3.h>
#include <stdlib.h>

static int bind_text_transient(sqlite3_stmt *stmt, int idx, const char *val, int len) {
    return sqlite3_bind_text(stmt, idx, val, len, SQLITE_TRANSIENT);
}
*/
import "C"

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"unsafe"
)

// sqliteDB is a minimal, thread-safe, parameterized CGO wrapper over system libsqlite3.
// Keeps RoweServer at zero third-party Go dependencies while supporting WAL & prepared statements.
type sqliteDB struct {
	mu sync.Mutex
	db *C.sqlite3
}

func openSQLite(path string) (*sqliteDB, error) {
	if path != ":memory:" {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return nil, fmt.Errorf("mkdir db dir: %w", err)
		}
	}

	cPath := C.CString(path)
	defer C.free(unsafe.Pointer(cPath))

	var handle *C.sqlite3
	flags := C.SQLITE_OPEN_READWRITE | C.SQLITE_OPEN_CREATE | C.SQLITE_OPEN_FULLMUTEX
	if rc := C.sqlite3_open_v2(cPath, &handle, C.int(flags), nil); rc != C.SQLITE_OK {
		msg := C.GoString(C.sqlite3_errmsg(handle))
		if handle != nil {
			C.sqlite3_close(handle)
		}
		return nil, fmt.Errorf("sqlite open: %s", msg)
	}

	s := &sqliteDB{db: handle}
	pragmas := []string{
		"PRAGMA journal_mode=WAL;",
		"PRAGMA synchronous=NORMAL;",
		"PRAGMA foreign_keys=ON;",
		"PRAGMA busy_timeout=5000;",
	}
	for _, p := range pragmas {
		if err := s.exec(p); err != nil {
			_ = s.close()
			return nil, err
		}
	}
	return s, nil
}

func (s *sqliteDB) close() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.db == nil {
		return nil
	}
	rc := C.sqlite3_close_v2(s.db)
	s.db = nil
	if rc != C.SQLITE_OK {
		return fmt.Errorf("sqlite close failed: code %d", int(rc))
	}
	return nil
}

func (s *sqliteDB) exec(query string, args ...any) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.execLocked(query, args...)
}

func (s *sqliteDB) execLocked(query string, args ...any) error {
	if s.db == nil {
		return errors.New("database closed")
	}

	stmt, err := s.prepareLocked(query, args...)
	if err != nil {
		return err
	}
	defer C.sqlite3_finalize(stmt)

	rc := C.sqlite3_step(stmt)
	if rc != C.SQLITE_DONE && rc != C.SQLITE_ROW {
		return s.lastErrLocked(rc)
	}
	return nil
}

// withTx executes fn inside an atomic SQLite transaction (BEGIN IMMEDIATE / COMMIT / ROLLBACK)
// while holding the database mutex so concurrent callers never interleave statements inside the tx.
func (s *sqliteDB) withTx(fn func() error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.db == nil {
		return errors.New("database closed")
	}
	if err := s.execLocked("BEGIN IMMEDIATE;"); err != nil {
		return err
	}
	if err := fn(); err != nil {
		_ = s.execLocked("ROLLBACK;")
		return err
	}
	if err := s.execLocked("COMMIT;"); err != nil {
		_ = s.execLocked("ROLLBACK;")
		return err
	}
	return nil
}

// queryRows runs a SELECT statement and invokes scan(rowValues) for every returned row.
func (s *sqliteDB) queryRows(query string, args []any, scan func(cols []any) error) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.queryRowsLocked(query, args, scan)
}

func (s *sqliteDB) queryRowsLocked(query string, args []any, scan func(cols []any) error) error {
	if s.db == nil {
		return errors.New("database closed")
	}

	stmt, err := s.prepareLocked(query, args...)
	if err != nil {
		return err
	}
	defer C.sqlite3_finalize(stmt)

	colCount := int(C.sqlite3_column_count(stmt))
	for {
		rc := C.sqlite3_step(stmt)
		if rc == C.SQLITE_DONE {
			break
		}
		if rc != C.SQLITE_ROW {
			return s.lastErrLocked(rc)
		}
		vals := make([]any, colCount)
		for i := 0; i < colCount; i++ {
			switch C.sqlite3_column_type(stmt, C.int(i)) {
			case C.SQLITE_INTEGER:
				vals[i] = int64(C.sqlite3_column_int64(stmt, C.int(i)))
			case C.SQLITE_TEXT:
				ptr := C.sqlite3_column_text(stmt, C.int(i))
				n := C.sqlite3_column_bytes(stmt, C.int(i))
				vals[i] = C.GoStringN((*C.char)(unsafe.Pointer(ptr)), n)
			case C.SQLITE_NULL:
				vals[i] = nil
			default:
				ptr := C.sqlite3_column_text(stmt, C.int(i))
				n := C.sqlite3_column_bytes(stmt, C.int(i))
				vals[i] = C.GoStringN((*C.char)(unsafe.Pointer(ptr)), n)
			}
		}
		if err := scan(vals); err != nil {
			return err
		}
	}
	return nil
}

func (s *sqliteDB) prepareLocked(query string, args ...any) (*C.sqlite3_stmt, error) {
	cQuery := C.CString(query)
	defer C.free(unsafe.Pointer(cQuery))

	var stmt *C.sqlite3_stmt
	if rc := C.sqlite3_prepare_v2(s.db, cQuery, -1, &stmt, nil); rc != C.SQLITE_OK {
		return nil, s.lastErrLocked(rc)
	}

	for idx, arg := range args {
		pos := C.int(idx + 1)
		var rc C.int
		switch v := arg.(type) {
		case nil:
			rc = C.sqlite3_bind_null(stmt, pos)
		case string:
			cStr := C.CString(v)
			rc = C.bind_text_transient(stmt, pos, cStr, C.int(len(v)))
			C.free(unsafe.Pointer(cStr))
		case int:
			rc = C.sqlite3_bind_int64(stmt, pos, C.sqlite3_int64(v))
		case int64:
			rc = C.sqlite3_bind_int64(stmt, pos, C.sqlite3_int64(v))
		case bool:
			if v {
				rc = C.sqlite3_bind_int64(stmt, pos, 1)
			} else {
				rc = C.sqlite3_bind_int64(stmt, pos, 0)
			}
		default:
			C.sqlite3_finalize(stmt)
			return nil, fmt.Errorf("unsupported sqlite arg type %T", arg)
		}
		if rc != C.SQLITE_OK {
			C.sqlite3_finalize(stmt)
			return nil, s.lastErrLocked(rc)
		}
	}
	return stmt, nil
}

func (s *sqliteDB) lastErrLocked(rc C.int) error {
	msg := C.GoString(C.sqlite3_errmsg(s.db))
	if rc == C.SQLITE_CONSTRAINT || rc == C.SQLITE_CONSTRAINT_UNIQUE {
		return fmt.Errorf("%w: %s", ErrAlreadyExists, msg)
	}
	return fmt.Errorf("sqlite error (%d): %s", int(rc), msg)
}

func asString(v any) string {
	if s, ok := v.(string); ok {
		return s
	}
	return ""
}

func asInt64(v any) int64 {
	if n, ok := v.(int64); ok {
		return n
	}
	return 0
}
