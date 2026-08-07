//! Local storage: lookup history and the saved word list.
//!
//! One SQLite file, entirely on the user's machine. There is no server and no
//! account, and there deliberately never will be for v1 — the database path is
//! configurable so anyone who wants sync can point it at iCloud or Dropbox and
//! get it with no infrastructure on our side.

use std::path::Path;

use rusqlite::{Connection, OptionalExtension};
use serde::Serialize;

use crate::model::Lookup;

#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("database error: {0}")]
    Sqlite(#[from] rusqlite::Error),
}

type Result<T> = std::result::Result<T, StoreError>;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct HistoryEntry {
    pub id: i64,
    pub source: String,
    pub translation: Option<String>,
    /// Unix seconds.
    pub looked_up_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct SavedWord {
    pub word: String,
    /// Unix seconds.
    pub saved_at: i64,
}

pub struct Store {
    conn: Connection,
}

impl Store {
    pub fn open(path: &Path) -> Result<Self> {
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let store = Self {
            conn: Connection::open(path)?,
        };
        store.migrate()?;
        Ok(store)
    }

    /// An ephemeral database. The test seam — no temp files to clean up and no
    /// ordering coupling between tests.
    pub fn open_in_memory() -> Result<Self> {
        let store = Self {
            conn: Connection::open_in_memory()?,
        };
        store.migrate()?;
        Ok(store)
    }

    fn migrate(&self) -> Result<()> {
        self.conn.execute_batch(
            "
            CREATE TABLE IF NOT EXISTS history (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                source        TEXT    NOT NULL,
                translation   TEXT,
                looked_up_at  INTEGER NOT NULL
            );

            -- `recent` always orders by this, and history is the table that
            -- grows without bound.
            CREATE INDEX IF NOT EXISTS history_by_time
                ON history (looked_up_at DESC, id DESC);

            CREATE TABLE IF NOT EXISTS saved_words (
                -- UNIQUE is what makes save_word idempotent. Enforcing it in
                -- the schema rather than with a SELECT-then-INSERT avoids the
                -- race between the two statements.
                word     TEXT    NOT NULL UNIQUE,
                saved_at INTEGER NOT NULL
            );
            ",
        )?;
        Ok(())
    }

    pub fn record_lookup(&self, lookup: &Lookup) -> Result<i64> {
        self.conn.execute(
            "INSERT INTO history (source, translation, looked_up_at)
             VALUES (?1, ?2, unixepoch())",
            (&lookup.source, &lookup.translation),
        )?;
        Ok(self.conn.last_insert_rowid())
    }

    /// The most recent `limit` lookups, newest first.
    ///
    /// Ties on `looked_up_at` break by `id` descending: unixepoch() has
    /// one-second resolution, so several lookups in the same second are
    /// common, and ordering by time alone would return them arbitrarily.
    pub fn recent(&self, limit: usize) -> Result<Vec<HistoryEntry>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, source, translation, looked_up_at
             FROM history
             ORDER BY looked_up_at DESC, id DESC
             LIMIT ?1",
        )?;

        let rows = stmt.query_map([limit as i64], |row| {
            Ok(HistoryEntry {
                id: row.get(0)?,
                source: row.get(1)?,
                translation: row.get(2)?,
                looked_up_at: row.get(3)?,
            })
        })?;

        Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
    }

    /// Save a word. Idempotent — saving the same word twice is not an error
    /// and does not duplicate it or move it up the list.
    pub fn save_word(&self, word: &str) -> Result<()> {
        let word = word.trim();
        if word.is_empty() {
            return Ok(());
        }
        self.conn.execute(
            "INSERT OR IGNORE INTO saved_words (word, saved_at) VALUES (?1, unixepoch())",
            [word],
        )?;
        Ok(())
    }

    /// Every saved word, newest first.
    ///
    /// **Deliberately uncapped.** The free tier is unlimited, and a silent
    /// limit here would be a paywall introduced by accident.
    pub fn saved_words(&self) -> Result<Vec<SavedWord>> {
        let mut stmt = self
            .conn
            .prepare("SELECT word, saved_at FROM saved_words ORDER BY saved_at DESC, rowid DESC")?;

        let rows = stmt.query_map([], |row| {
            Ok(SavedWord {
                word: row.get(0)?,
                saved_at: row.get(1)?,
            })
        })?;

        Ok(rows.collect::<std::result::Result<Vec<_>, _>>()?)
    }

    pub fn unsave_word(&self, word: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM saved_words WHERE word = ?1", [word.trim()])?;
        Ok(())
    }

    pub fn is_saved(&self, word: &str) -> Result<bool> {
        Ok(self
            .conn
            .query_row(
                "SELECT 1 FROM saved_words WHERE word = ?1",
                [word.trim()],
                |_| Ok(()),
            )
            .optional()?
            .is_some())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lookup(source: &str, translation: Option<&str>) -> Lookup {
        Lookup {
            source: source.to_owned(),
            source_truncated: false,
            definitions: Vec::new(),
            translation: translation.map(str::to_owned),
        }
    }

    #[test]
    fn saving_the_same_word_twice_does_not_duplicate_it() {
        let s = Store::open_in_memory().unwrap();
        s.save_word("idempotent").unwrap();
        s.save_word("idempotent").unwrap();
        assert_eq!(s.saved_words().unwrap().len(), 1);
    }

    #[test]
    fn saving_a_word_is_reported_by_is_saved() {
        let s = Store::open_in_memory().unwrap();
        assert!(!s.is_saved("throttle").unwrap());
        s.save_word("throttle").unwrap();
        assert!(s.is_saved("throttle").unwrap());
    }

    #[test]
    fn unsave_removes_only_the_named_word() {
        let s = Store::open_in_memory().unwrap();
        s.save_word("idempotent").unwrap();
        s.save_word("throttle").unwrap();
        s.unsave_word("throttle").unwrap();

        let words: Vec<_> = s
            .saved_words()
            .unwrap()
            .into_iter()
            .map(|w| w.word)
            .collect();
        assert_eq!(words, vec!["idempotent"]);
    }

    #[test]
    fn words_are_trimmed_so_the_same_word_does_not_slip_in_twice() {
        // A selection almost always carries surrounding whitespace. Without
        // trimming, "throttle" and " throttle " are two different rows and
        // UNIQUE never fires.
        let s = Store::open_in_memory().unwrap();
        s.save_word("throttle").unwrap();
        s.save_word("  throttle  ").unwrap();
        assert_eq!(s.saved_words().unwrap().len(), 1);
    }

    #[test]
    fn blank_words_are_never_saved() {
        let s = Store::open_in_memory().unwrap();
        s.save_word("   \n\t ").unwrap();
        assert!(s.saved_words().unwrap().is_empty());
    }

    #[test]
    fn the_word_list_is_not_capped() {
        // The free tier is unlimited. A cap here would be a paywall by
        // accident, which is exactly what the tier rule forbids.
        let s = Store::open_in_memory().unwrap();
        for i in 0..500 {
            s.save_word(&format!("w{i}")).unwrap();
        }
        assert_eq!(s.saved_words().unwrap().len(), 500);
    }

    #[test]
    fn recent_returns_newest_first_and_respects_the_limit() {
        let s = Store::open_in_memory().unwrap();
        s.record_lookup(&lookup("first", Some("một"))).unwrap();
        s.record_lookup(&lookup("second", Some("hai"))).unwrap();
        s.record_lookup(&lookup("third", Some("ba"))).unwrap();

        let recent = s.recent(2).unwrap();
        assert_eq!(recent.len(), 2);
        // All three land in the same unixepoch() second, so this only holds
        // because the ordering breaks ties on id. Without that it is flaky.
        assert_eq!(recent[0].source, "third");
        assert_eq!(recent[1].source, "second");
    }

    #[test]
    fn history_keeps_a_missing_translation_as_null() {
        let s = Store::open_in_memory().unwrap();
        s.record_lookup(&lookup("kubectl", None)).unwrap();
        assert_eq!(s.recent(1).unwrap()[0].translation, None);
    }

    #[test]
    fn recent_on_an_empty_database_returns_nothing_rather_than_failing() {
        let s = Store::open_in_memory().unwrap();
        assert!(s.recent(10).unwrap().is_empty());
    }

    #[test]
    fn opening_the_same_file_twice_preserves_the_data() {
        // Guards the migration being re-runnable: CREATE TABLE without
        // IF NOT EXISTS would make the second open fail outright.
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("nested").join("tra.db");

        {
            let s = Store::open(&path).unwrap();
            s.save_word("idempotent").unwrap();
        }

        let reopened = Store::open(&path).unwrap();
        assert_eq!(reopened.saved_words().unwrap().len(), 1);
    }
}
