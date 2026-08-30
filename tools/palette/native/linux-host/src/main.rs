use adw::prelude::*;
use adw::{Application, ApplicationWindow};
use gtk4::gio;
use std::env;
use std::path::PathBuf;
use webkit6::WebView;

const APP_ID: &str = "sh.palette.Desktop";

fn ui_url() -> String {
    let path = env::var_os("PALETTE_UI_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("dist/ui/index.html"));
    gio::File::for_path(path).uri().to_string()
}

fn main() {
    let application = Application::builder().application_id(APP_ID).build();
    application.connect_activate(|application| {
        let web_view = WebView::new();
        web_view.load_uri(&ui_url());

        let window = ApplicationWindow::builder()
            .application(application)
            .title("Palette")
            .default_width(680)
            .default_height(420)
            .content(&web_view)
            .build();
        // The process is resident; the native StatusNotifierItem/global-shortcut
        // implementation can present this window without recreating the WebView.
        window.hide();
    });
    application.run();
}
