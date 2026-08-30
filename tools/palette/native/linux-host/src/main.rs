use adw::prelude::*;
use adw::{Application, ApplicationWindow};
use gtk4::gio;
use gtk4::glib;
use ksni::blocking::TrayMethods;
use std::env;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;
use webkit6::prelude::*;
use webkit6::WebView;

const APP_ID: &str = "sh.palette.Desktop";

#[derive(Clone, Copy)]
enum TrayAction {
    Open,
    Clipboard,
    Quit,
}

struct PaletteTray {
    actions: mpsc::Sender<TrayAction>,
}

impl ksni::Tray for PaletteTray {
    fn id(&self) -> String {
        "palette".into()
    }

    fn title(&self) -> String {
        "Palette".into()
    }

    fn icon_name(&self) -> String {
        "system-search".into()
    }

    fn menu(&self) -> Vec<ksni::menu::MenuItem<Self>> {
        use ksni::menu::StandardItem;
        let open = self.actions.clone();
        let clipboard = self.actions.clone();
        let quit = self.actions.clone();
        vec![
            StandardItem {
                label: "Open Palette".into(),
                activate: Box::new(move |_| {
                    let _ = open.send(TrayAction::Open);
                }),
                ..Default::default()
            }
            .into(),
            StandardItem {
                label: "Clipboard History".into(),
                activate: Box::new(move |_| {
                    let _ = clipboard.send(TrayAction::Clipboard);
                }),
                ..Default::default()
            }
            .into(),
            ksni::menu::MenuItem::Separator,
            StandardItem {
                label: "Quit Palette".into(),
                activate: Box::new(move |_| {
                    let _ = quit.send(TrayAction::Quit);
                }),
                ..Default::default()
            }
            .into(),
        ]
    }
}

fn ui_url() -> String {
    let path = env::var_os("PALETTE_UI_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("dist/ui/index.html"));
    gio::File::for_path(path).uri().to_string()
}

fn daemon_path() -> PathBuf {
    if let Some(path) = env::var_os("PALETTE_NODE_DAEMON") {
        return PathBuf::from(path);
    }
    let packaged = PathBuf::from("dist/node/node-daemon.mjs");
    if packaged.exists() {
        packaged
    } else {
        PathBuf::from("src/node-daemon.ts")
    }
}

fn start_sidecar() -> (mpsc::Sender<String>, mpsc::Receiver<String>) {
    let (requests, request_rx) = mpsc::channel::<String>();
    let (response_tx, responses) = mpsc::channel::<String>();
    thread::spawn(move || {
        let script = daemon_path();
        let mut command = Command::new("node");
        if script.extension().and_then(|value| value.to_str()) == Some("ts") {
            command.arg("--experimental-strip-types");
        }
        if let Some(data_home) = env::var_os("XDG_DATA_HOME") {
            command.env("PALETTE_DATA_DIR", PathBuf::from(data_home).join("palette"));
        }
        let child = command
            .arg(script)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn();
        let Ok(mut child) = child else { return };
        let Some(mut input) = child.stdin.take() else {
            return;
        };
        let Some(output) = child.stdout.take() else {
            return;
        };
        let mut output = BufReader::new(output);
        'requests: for request in request_rx {
            let request_id = serde_json::from_str::<serde_json::Value>(&request)
                .ok()
                .and_then(|value| {
                    value
                        .get("id")
                        .and_then(|id| id.as_str())
                        .map(str::to_owned)
                });
            if input.write_all(request.as_bytes()).is_err()
                || input.write_all(b"\n").is_err()
                || input.flush().is_err()
            {
                break;
            }
            loop {
                let mut response = String::new();
                if output.read_line(&mut response).is_err() || response.is_empty() {
                    break 'requests;
                }
                let response_id = serde_json::from_str::<serde_json::Value>(&response)
                    .ok()
                    .and_then(|value| {
                        value
                            .get("id")
                            .and_then(|id| id.as_str())
                            .map(str::to_owned)
                    });
                if response_tx.send(response).is_err() {
                    break 'requests;
                }
                if response_id.is_some() && response_id == request_id {
                    break;
                }
            }
        }
        let _ = child.kill();
    });
    (requests, responses)
}

fn main() {
    let application = Application::builder().application_id(APP_ID).build();
    application.connect_activate(|application| {
        let manager = webkit6::UserContentManager::new();
        manager.register_script_message_handler("palette", None);
        let web_view = WebView::builder().user_content_manager(&manager).build();
        web_view.load_uri(&ui_url());

        let (requests, responses) = start_sidecar();
        let web_view_for_messages = web_view.clone();
        manager.connect_script_message_received(Some("palette"), move |_, value| {
            if let Some(json) = value.to_json(0) {
                let _ = requests.send(json.to_string());
            }
        });
        glib::timeout_add_local(std::time::Duration::from_millis(20), move || {
            while let Ok(response) = responses.try_recv() {
                let trimmed = response.trim();
                if trimmed.starts_with('{') {
                    web_view_for_messages.evaluate_javascript(
                        &format!("window.__paletteResolve({trimmed})"),
                        None,
                        None,
                        None::<&gio::Cancellable>,
                        |_| {},
                    );
                }
            }
            glib::ControlFlow::Continue
        });

        let window = ApplicationWindow::builder()
            .application(application)
            .title("Palette")
            .default_width(680)
            .default_height(420)
            .content(&web_view)
            .build();

        let (tray_actions, tray_events) = mpsc::channel();
        thread::spawn(move || {
            let tray = PaletteTray {
                actions: tray_actions,
            };
            match tray.spawn() {
                Ok(_handle) => loop {
                    thread::park();
                },
                Err(error) => eprintln!("Palette StatusNotifier unavailable: {error}"),
            }
        });
        let window_for_tray = window.clone();
        let web_view_for_tray = web_view.clone();
        glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
            while let Ok(action) = tray_events.try_recv() {
                match action {
                    TrayAction::Open => window_for_tray.set_visible(true),
                    TrayAction::Clipboard => {
                        window_for_tray.set_visible(true);
                        web_view_for_tray.evaluate_javascript(
                            "window.__paletteOpenClipboard?.()",
                            None,
                            None,
                            None::<&gio::Cancellable>,
                            |_| {},
                        );
                    }
                    TrayAction::Quit => application.quit(),
                }
            }
            glib::ControlFlow::Continue
        });
        let hotkey = env::var("PALETTE_HOTKEY").unwrap_or_else(|_| "alt+space".to_string());
        let keys = gtk4::EventControllerKey::new();
        let window_for_keys = window.clone();
        keys.connect_key_pressed(move |_, key, _, state| {
            let normalized = hotkey.replace(' ', "").to_lowercase();
            let modifier = if normalized.starts_with("ctrl+") || normalized.starts_with("control+")
            {
                gtk4::gdk::ModifierType::CONTROL_MASK
            } else {
                gtk4::gdk::ModifierType::ALT_MASK
            };
            if key == gtk4::gdk::Key::space && state.contains(modifier) {
                window_for_keys.set_visible(!window_for_keys.is_visible());
                return glib::Propagation::Stop;
            }
            glib::Propagation::Proceed
        });
        window.add_controller(keys);
        // The process is resident; the native StatusNotifierItem/global-shortcut
        // implementation can present this window without recreating the WebView.
        window.hide();
    });
    application.run();
}
