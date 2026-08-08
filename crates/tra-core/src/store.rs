//! Local storage: lookup history and the saved word list.
//!
//! One SQLite file, entirely on the user's machine. There is no server and no
//! account, and there deliberately never will be for v1 — the database path is
//! configurable so anyone who wants sync can point it at iCloud or Dropbox and
//! get it with no infrastructure on our side.

use std::path::Path;

use rusqlite::{Connection, OptionalExtension};
use serde::Serialize;

use crate::config::LangConfig;
use crate::lang::Lang;
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

            CREATE TABLE IF NOT EXISTS settings (
                key   TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            ",
        )?;

        // Nullable so every row written before this release stays valid.
        self.add_column_if_missing("history", "source_lang", "TEXT")?;
        self.add_column_if_missing("history", "target_lang", "TEXT")?;
        // Not needed until SRS, but the language of a saved word cannot be
        // re-derived from the word later, so it is recorded from the start.
        self.add_column_if_missing("saved_words", "lang", "TEXT")?;

        Ok(())
    }

    /// `ALTER TABLE ADD COLUMN`, but re-runnable.
    ///
    /// SQLite has no `IF NOT EXISTS` for columns, and `migrate` runs on every
    /// open — so without this guard the second launch fails with "duplicate
    /// column name" and the app never starts again.
    fn add_column_if_missing(&self, table: &str, column: &str, decl: &str) -> Result<()> {
        let exists: bool = self.conn.query_row(
            "SELECT COUNT(*) > 0 FROM pragma_table_info(?1) WHERE name = ?2",
            (table, column),
            |row| row.get(0),
        )?;

        if !exists {
            // Interpolated rather than bound because SQLite does not accept
            // parameters for identifiers. Safe here: every argument is a
            // literal from this file, never user input.
            self.conn
                .execute_batch(&format!("ALTER TABLE {table} ADD COLUMN {column} {decl}"))?;
        }

        Ok(())
    }

    // -- settings ------------------------------------------------------------

    pub fn setting(&self, key: &str) -> Result<Option<String>> {
        Ok(self
            .conn
            .query_row("SELECT value FROM settings WHERE key = ?1", [key], |r| {
                r.get(0)
            })
            .optional()?)
    }

    pub fn set_setting(&self, key: &str, value: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO settings (key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            (key, value),
        )?;
        Ok(())
    }

    /// The stored language configuration, or the default.
    ///
    /// Every field degrades independently: an unreadable or unknown code falls
    /// back rather than failing, because a bad row in this table must never be
    /// able to stop the app from starting.
    pub fn lang_config(&self) -> Result<LangConfig> {
        let read = |key: &str| -> Option<Lang> {
            self.setting(key)
                .ok()
                .flatten()
                .and_then(|c| Lang::from_code(&c))
        };

        let default = LangConfig::default();
        // Degrades the same way `read` does: a DB error here must not stop
        // the app from starting any more than one on `lang.target` would.
        //
        // "auto" is written explicitly by `set_lang_config` rather than the
        // key being left absent, so that choosing a concrete source and then
        // switching back to auto actually overwrites it — an absent key would
        // leave the old concrete value in `settings` for this read to find.
        let source = match self.setting("lang.source").ok().flatten().as_deref() {
            Some("auto") | None => None,
            Some(code) => Lang::from_code(code),
        };

        Ok(LangConfig::new(
            source,
            read("lang.target").unwrap_or(default.target()),
            read("lang.other").unwrap_or(default.other()),
        ))
    }

    pub fn set_lang_config(&self, config: &LangConfig) -> Result<()> {
        self.set_setting("lang.source", config.sl())?;
        self.set_setting("lang.target", config.target().code())?;
        self.set_setting("lang.other", config.other().code())?;
        Ok(())
    }

    /// How many languages the picker pins above the full list.
    const RECENT_LANGS: usize = 5;

    /// The most recently chosen languages, newest first.
    ///
    /// Capped here as well as in `push_recent_lang`: `set_setting` is public,
    /// so a longer stored string must not be able to hand back more than the
    /// picker is designed to show.
    pub fn recent_langs(&self) -> Result<Vec<Lang>> {
        Ok(self
            .setting("lang.recents")?
            .unwrap_or_default()
            .split(',')
            .filter_map(Lang::from_code)
            .take(Self::RECENT_LANGS)
            .collect())
    }

    /// Move `lang` to the front of the recents, capped at [`Self::RECENT_LANGS`].
    pub fn push_recent_lang(&self, lang: Lang) -> Result<()> {
        let mut recents = self.recent_langs()?;
        recents.retain(|l| *l != lang);
        recents.insert(0, lang);
        recents.truncate(Self::RECENT_LANGS);

        let joined: Vec<&str> = recents.iter().map(|l| l.code()).collect();
        self.set_setting("lang.recents", &joined.join(","))
    }

    pub fn record_lookup(&self, lookup: &Lookup) -> Result<i64> {
        self.conn.execute(
            "INSERT INTO history (source, translation, source_lang, target_lang, looked_up_at)
             VALUES (?1, ?2, ?3, ?4, unixepoch())",
            (
                &lookup.source,
                &lookup.translation,
                lookup.source_lang.map(|l| l.code()),
                lookup.target_lang.code(),
            ),
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
            source_lang: None,
            target_lang: Lang::VI,
            definition_lang: None,
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

    #[test]
    fn the_language_config_defaults_before_anything_is_saved() {
        let s = Store::open_in_memory().unwrap();
        assert_eq!(s.lang_config().unwrap(), LangConfig::default());
    }

    #[test]
    fn the_language_config_round_trips() {
        let s = Store::open_in_memory().unwrap();
        let c = LangConfig::new(
            Lang::from_code("de"),
            Lang::from_code("ja").unwrap(),
            Lang::EN,
        );
        s.set_lang_config(&c).unwrap();
        assert_eq!(s.lang_config().unwrap(), c);
    }

    #[test]
    fn an_auto_source_round_trips_too() {
        // The concrete-source case above cannot catch a regression in the
        // "auto" sentinel — the one path that maps a stored string back to
        // `None` instead of a `Lang`.
        let s = Store::open_in_memory().unwrap();
        let c = LangConfig::default();
        assert_eq!(c.source(), None, "test assumes the default source is auto");
        s.set_lang_config(&c).unwrap();
        assert_eq!(s.lang_config().unwrap(), c);
    }

    #[test]
    fn an_unreadable_stored_language_falls_back_to_the_default() {
        // A code that was valid in an older build, a hand-edited database, a
        // corrupted row: none of these may stop the app from starting.
        let s = Store::open_in_memory().unwrap();
        s.set_setting("lang.target", "klingon").unwrap();
        assert_eq!(
            s.lang_config().unwrap().target(),
            LangConfig::default().target()
        );
    }

    #[test]
    fn a_stored_config_that_would_break_an_invariant_is_repaired_on_read() {
        let s = Store::open_in_memory().unwrap();
        s.set_setting("lang.target", "en").unwrap();
        s.set_setting("lang.other", "en").unwrap();
        let c = s.lang_config().unwrap();
        assert_ne!(c.other(), c.target());
    }

    #[test]
    fn recent_languages_are_newest_first_and_capped() {
        let s = Store::open_in_memory().unwrap();
        for code in ["de", "ja", "es", "fr", "it", "ru"] {
            s.push_recent_lang(Lang::from_code(code).unwrap()).unwrap();
        }
        let recents = s.recent_langs().unwrap();
        assert_eq!(recents.len(), 5, "the picker shows five");
        assert_eq!(recents[0], Lang::from_code("ru").unwrap());
        assert!(
            !recents.contains(&Lang::from_code("de").unwrap()),
            "the oldest fell off"
        );
    }

    #[test]
    fn recent_langs_caps_even_a_directly_stored_longer_list() {
        // The cap has to hold on read, not just when written through
        // `push_recent_lang` — `set_setting` is public, so nothing stops a
        // longer value ending up in `lang.recents` some other way.
        let s = Store::open_in_memory().unwrap();
        let codes = ["de", "ja", "es", "fr", "it", "ru", "pt"];
        s.set_setting("lang.recents", &codes.join(",")).unwrap();
        assert_eq!(s.recent_langs().unwrap().len(), 5);
    }

    #[test]
    fn pushing_a_language_again_moves_it_to_the_front_without_duplicating() {
        let s = Store::open_in_memory().unwrap();
        for code in ["de", "ja", "de"] {
            s.push_recent_lang(Lang::from_code(code).unwrap()).unwrap();
        }
        let recents = s.recent_langs().unwrap();
        assert_eq!(
            recents,
            vec![
                Lang::from_code("de").unwrap(),
                Lang::from_code("ja").unwrap()
            ]
        );
    }

    #[test]
    fn history_records_the_languages_a_lookup_ran_in() {
        let s = Store::open_in_memory().unwrap();
        let mut l = lookup("Haus", Some("Căn nhà"));
        l.source_lang = Lang::from_code("de");
        l.target_lang = Lang::VI;
        s.record_lookup(&l).unwrap();

        let (source_lang, target_lang): (Option<String>, Option<String>) = s
            .conn
            .query_row("SELECT source_lang, target_lang FROM history", [], |r| {
                Ok((r.get(0)?, r.get(1)?))
            })
            .unwrap();
        assert_eq!(source_lang.as_deref(), Some("de"));
        assert_eq!(target_lang.as_deref(), Some("vi"));
    }

    #[test]
    fn migrating_twice_does_not_fail_on_the_added_columns() {
        // ALTER TABLE ADD COLUMN has no IF NOT EXISTS. Without the pragma guard
        // this throws "duplicate column name" on the second open, which means
        // every launch after the first.
        //
        // `tempfile::tempdir()` rather than a plain `remove_file` at the end:
        // the `TempDir` guard cleans up on `Drop`, including when an assert
        // above panics, so a failing run never leaves `twice.db` behind. Same
        // pattern as `opening_the_same_file_twice_preserves_the_data` above.
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("twice.db");

        let first = Store::open(&path).unwrap();
        first.save_word("idempotent").unwrap();
        drop(first);

        let second = Store::open(&path).expect("second open must not fail");
        assert!(second.is_saved("idempotent").unwrap());
    }
}
