//! Enforces the architectural rule from the design doc: `tra-core` must stay
//! framework-free.
//!
//! Without a test, "don't import tauri" is a comment nobody reads at 2am when
//! something in the core needs an AppHandle and adding one dependency looks
//! harmless. That single dependency is what makes the core untestable without
//! a GUI and welds the app to one framework.
//!
//! This reads the manifest as text rather than shelling out to `cargo
//! metadata` so it stays fast and offline. It checks *direct* dependencies,
//! which is the rule being enforced — a transitive tauri crate arriving under
//! something else is not the mistake this guards against.

const MANIFEST: &str = include_str!("../Cargo.toml");

#[test]
fn tra_core_does_not_depend_on_tauri() {
    let mut offenders = Vec::new();

    for (n, raw) in MANIFEST.lines().enumerate() {
        let line = raw.trim();
        if line.starts_with('#') {
            continue;
        }
        // Dependency entries are `name = ...` or `name.workspace = true`.
        let Some((name, _)) = line.split_once('=') else {
            continue;
        };
        let name = name.trim().trim_matches('"');
        let base = name.split('.').next().unwrap_or(name);

        if base == "tauri" || base.starts_with("tauri-") {
            offenders.push(format!("  line {}: {}", n + 1, line));
        }
    }

    assert!(
        offenders.is_empty(),
        "tra-core must not depend on tauri — that is the whole point of the crate \
         split (see the design doc, Architecture / Structure). Found:\n{}",
        offenders.join("\n")
    );
}

#[test]
fn the_guard_would_actually_catch_a_violation() {
    // A test that can only pass is worse than no test. This runs the same
    // detection over a manifest that IS in violation and asserts it trips, so
    // the check above is known to be load-bearing rather than vacuous.
    let bad = "[dependencies]\nserde = \"1\"\ntauri = { version = \"2\" }\n";

    let found = bad.lines().any(|raw| {
        let line = raw.trim();
        !line.starts_with('#')
            && line
                .split_once('=')
                .map(|(name, _)| {
                    let base = name.trim().trim_matches('"');
                    let base = base.split('.').next().unwrap_or(base);
                    base == "tauri" || base.starts_with("tauri-")
                })
                .unwrap_or(false)
    });

    assert!(found, "the tauri-dependency detection failed to flag an obvious violation");
}
