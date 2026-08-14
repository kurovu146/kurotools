//! The menu-bar / system-tray icon.
//!
//! KTranslate has no Dock presence and no window in the task switcher — it is
//! summoned by a hotkey and dismissed on Esc. The tray is therefore the only
//! persistent, discoverable way to reach it, which makes Quit here the app's
//! only exit. Without it a user who wants KTranslate gone has to reach for Activity
//! Monitor.

use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::App;

use crate::popup;

pub fn init(app: &App) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show", "Show KTranslate", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit KTranslate", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &quit])?;

    TrayIconBuilder::new()
        .icon(app.default_window_icon().unwrap().clone())
        .menu(&menu)
        // The menu must not also open on a left click: that is the button the
        // positioner uses for "show at cursor", and having both fight over one
        // click makes the icon feel broken.
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show" => popup::show(app),
            "quit" => app.exit(0),
            _ => {}
        })
        .build(app)?;

    Ok(())
}
