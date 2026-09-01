use adw::prelude::*;
use adw::{Application, ApplicationWindow};
use ashpd::desktop::global_shortcuts::{GlobalShortcuts, NewShortcut};
use ashpd::desktop::CreateSessionOptions;
use futures_util::StreamExt;
use gtk4::{gio, glib};
use ksni::blocking::TrayMethods;
use serde_json::{json, Value};
use std::cell::RefCell;
use std::env;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::rc::Rc;
use std::sync::mpsc;
use std::thread;
use webkit6::prelude::*;
use webkit6::WebView;

const APP_ID: &str = "sh.palette.Desktop";

#[derive(Clone, Copy)]
enum TrayAction {
    Open,
    Toggle,
    Clipboard,
    Hide,
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
                label: "Quit".into(),
                activate: Box::new(move |_| {
                    let _ = quit.send(TrayAction::Quit);
                }),
                ..Default::default()
            }
            .into(),
        ]
    }
}

fn installed_resource(relative: &Path) -> Option<PathBuf> {
    let executable = env::current_exe().ok()?;
    let binary_directory = executable.parent()?;
    [
        binary_directory.join("Resources").join(relative),
        binary_directory
            .join("..")
            .join("share")
            .join("palette")
            .join(relative),
    ]
    .into_iter()
    .find(|candidate| candidate.exists())
}

fn ui_path() -> PathBuf {
    if let Some(path) = env::var_os("PALETTE_UI_PATH") {
        return PathBuf::from(path);
    }
    installed_resource(Path::new("ui/index.html"))
        .unwrap_or_else(|| PathBuf::from("dist/ui/index.html"))
}

fn ui_url() -> String {
    gio::File::for_path(ui_path()).uri().to_string()
}

fn daemon_path() -> PathBuf {
    if let Some(path) = env::var_os("PALETTE_NODE_DAEMON") {
        return PathBuf::from(path);
    }
    installed_resource(Path::new("node/node-daemon.mjs"))
        .or_else(|| {
            PathBuf::from("dist/node/node-daemon.mjs")
                .exists()
                .then(|| PathBuf::from("dist/node/node-daemon.mjs"))
        })
        .unwrap_or_else(|| PathBuf::from("src/node-daemon.ts"))
}

fn node_executable() -> Option<PathBuf> {
    if let Some(path) = env::var_os("PALETTE_NODE_EXECUTABLE") {
        let path = PathBuf::from(path);
        if path.exists() {
            return Some(path);
        }
    }
    installed_resource(Path::new("Helpers/node")).or_else(|| {
        ["/usr/bin/node", "/usr/local/bin/node"]
            .into_iter()
            .map(PathBuf::from)
            .find(|path| path.exists())
    })
}

fn indexer_path() -> Option<PathBuf> {
    if let Some(path) = env::var_os("PALETTE_INDEXER") {
        let path = PathBuf::from(path);
        if path.exists() {
            return Some(path);
        }
    }
    installed_resource(Path::new("Helpers/palette-indexer")).or_else(|| {
        let development = PathBuf::from("native/rust-indexer/target/release/palette-indexer");
        development.exists().then_some(development)
    })
}

fn data_directory() -> PathBuf {
    env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/share")))
        .unwrap_or_else(|| PathBuf::from("."))
        .join("palette")
}

fn config_directory() -> PathBuf {
    env::var_os("PALETTE_CONFIG_DIR")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".palette")))
        .unwrap_or_else(|| PathBuf::from(".palette"))
}

fn start_sidecar() -> (mpsc::Sender<String>, mpsc::Receiver<String>) {
    let (requests, request_rx) = mpsc::channel::<String>();
    let (response_tx, responses) = mpsc::channel::<String>();
    thread::spawn(move || {
        let script = daemon_path();
        let Some(node) = node_executable() else {
            eprintln!("Palette: Node.js was not found; set PALETTE_NODE_EXECUTABLE");
            return;
        };
        let mut command = Command::new(node);
        if script.extension().and_then(|value| value.to_str()) == Some("ts") {
            command.arg("--experimental-strip-types");
        }
        if let Some(indexer) = indexer_path() {
            command.env("PALETTE_INDEXER", indexer);
        }
        let child = command
            .arg(script)
            .env("PALETTE_DATA_DIR", data_directory())
            .env("PALETTE_CONFIG_DIR", config_directory())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn();
        let Ok(mut child) = child else {
            eprintln!("Palette: failed to start Node service");
            return;
        };
        let Some(mut input) = child.stdin.take() else {
            return;
        };
        let Some(output) = child.stdout.take() else {
            return;
        };
        let mut output = BufReader::new(output);
        'requests: for request in request_rx {
            let request_id = serde_json::from_str::<Value>(&request)
                .ok()
                .and_then(|value| value.get("id").and_then(Value::as_str).map(str::to_owned));
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
                let response_id = serde_json::from_str::<Value>(&response)
                    .ok()
                    .and_then(|value| value.get("id").and_then(Value::as_str).map(str::to_owned));
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

fn start_global_shortcut(action_tx: mpsc::Sender<TrayAction>) {
    thread::spawn(move || {
        let Ok(runtime) = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
        else {
            return;
        };
        runtime.block_on(async move {
            let Ok(portal) = GlobalShortcuts::new().await else {
                return;
            };
            let Ok(session) = portal.create_session(CreateSessionOptions::default()).await else {
                return;
            };
            let preferred = env::var("PALETTE_HOTKEY")
                .unwrap_or_else(|_| "alt+space".into())
                .to_uppercase();
            let trigger = match preferred.as_str() {
                "CTRL+SPACE" | "CONTROL+SPACE" => "<Control>space",
                "CTRL+SHIFT+SPACE" | "CONTROL+SHIFT+SPACE" => "<Control><Shift>space",
                _ => "<Alt>space",
            };
            let shortcut =
                NewShortcut::new("toggle", "Toggle Palette").preferred_trigger(Some(trigger));
            let Ok(request) = portal
                .bind_shortcuts(&session, &[shortcut], None, Default::default())
                .await
            else {
                return;
            };
            if request.response().is_err() {
                return;
            }
            let Ok(mut activated) = portal.receive_activated().await else {
                return;
            };
            while let Some(event) = activated.next().await {
                if event.shortcut_id() == "toggle" {
                    let _ = action_tx.send(TrayAction::Toggle);
                }
            }
        });
    });
}

fn start_clipboard_monitor(requests: mpsc::Sender<String>) {
    let Some(display) = gtk4::gdk::Display::default() else {
        return;
    };
    let clipboard = display.clipboard();
    let last_text = Rc::new(RefCell::new(String::new()));
    clipboard.connect_changed(move |clipboard| {
        let requests = requests.clone();
        let last_text = last_text.clone();
        clipboard.read_text_async(None::<&gio::Cancellable>, move |result| {
            let Ok(Some(text)) = result else {
                return;
            };
            let text = text.to_string();
            if text.is_empty() || *last_text.borrow() == text {
                return;
            }
            *last_text.borrow_mut() = text.clone();
            let id = glib::uuid_string_random().to_string();
            let request = json!({
                "id": format!("capture-{id}"),
                "type": "captureClipboard",
                "item": {
                    "id": id,
                    "kind": if text.contains("://") { "url" } else { "text" },
                    "content": text,
                    "createdAt": glib::real_time() / 1000,
                    "pinned": false
                }
            });
            let _ = requests.send(request.to_string());
        });
    });
}

fn main() {
    let application = Application::builder().application_id(APP_ID).build();
    application.connect_activate(|application| {
        if let Some(existing) = application.windows().into_iter().next() {
            existing.present();
            return;
        }
        let manager = webkit6::UserContentManager::new();
        manager.register_script_message_handler("palette", None);
        let web_view = WebView::builder().user_content_manager(&manager).build();
        web_view.load_uri(&ui_url());

        let (requests, responses) = start_sidecar();
        let (tray_actions, tray_events) = mpsc::channel();
        let host_actions = tray_actions.clone();
        let requests_for_messages = requests.clone();
        manager.connect_script_message_received(Some("palette"), move |_, value| {
            let Some(json) = value.to_json(0) else {
                return;
            };
            let serialized = json.to_string();
            let kind = serde_json::from_str::<Value>(&serialized)
                .ok()
                .and_then(|value| value.get("type").and_then(Value::as_str).map(str::to_owned));
            match kind.as_deref() {
                Some("dismissLauncher") => {
                    let _ = host_actions.send(TrayAction::Hide);
                }
                Some("hostReady") => {}
                _ => {
                    let _ = requests_for_messages.send(serialized);
                }
            }
        });

        let application_for_responses = application.clone();
        let web_view_for_messages = web_view.clone();
        glib::timeout_add_local(std::time::Duration::from_millis(20), move || {
            while let Ok(response) = responses.try_recv() {
                let trimmed = response.trim();
                let parsed = serde_json::from_str::<Value>(trimmed).ok();
                if parsed
                    .as_ref()
                    .and_then(|value| value.get("type"))
                    .and_then(Value::as_str)
                    == Some("notification")
                {
                    if let Some(notification) =
                        parsed.as_ref().and_then(|value| value.get("notification"))
                    {
                        let title = notification
                            .get("title")
                            .and_then(Value::as_str)
                            .unwrap_or("Palette");
                        let native = gio::Notification::new(title);
                        if let Some(body) = notification.get("body").and_then(Value::as_str) {
                            native.set_body(Some(body));
                        }
                        application_for_responses.send_notification(None, &native);
                    }
                } else if trimmed.starts_with('{') {
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
            .decorated(false)
            .resizable(false)
            .content(&web_view)
            .build();
        window.connect_close_request(|window| {
            window.hide();
            glib::Propagation::Stop
        });
        let window_for_deactivate = window.clone();
        window.connect_is_active_notify(move |current| {
            if !current.is_active() {
                window_for_deactivate.hide();
            }
        });

        let keys = gtk4::EventControllerKey::new();
        let window_for_keys = window.clone();
        keys.connect_key_pressed(move |_, key, _, _| {
            if key == gtk4::gdk::Key::Escape {
                window_for_keys.hide();
                return glib::Propagation::Stop;
            }
            glib::Propagation::Proceed
        });
        window.add_controller(keys);

        let tray_sender = tray_actions.clone();
        thread::spawn(move || {
            let tray = PaletteTray {
                actions: tray_sender,
            };
            match tray.spawn() {
                Ok(_handle) => loop {
                    thread::park();
                },
                Err(error) => eprintln!("Palette StatusNotifier unavailable: {error}"),
            }
        });
        start_global_shortcut(tray_actions);
        start_clipboard_monitor(requests);

        let window_for_tray = window.clone();
        let web_view_for_tray = web_view.clone();
        let application_for_tray = application.clone();
        glib::timeout_add_local(std::time::Duration::from_millis(50), move || {
            while let Ok(action) = tray_events.try_recv() {
                match action {
                    TrayAction::Open => {
                        window_for_tray.present();
                        web_view_for_tray.evaluate_javascript(
                            "window.__paletteOpen?.()",
                            None,
                            None,
                            None::<&gio::Cancellable>,
                            |_| {},
                        );
                    }
                    TrayAction::Toggle => {
                        if window_for_tray.is_visible() {
                            window_for_tray.hide();
                        } else {
                            window_for_tray.present();
                        }
                    }
                    TrayAction::Clipboard => {
                        window_for_tray.present();
                        web_view_for_tray.evaluate_javascript(
                            "window.__paletteOpenClipboard?.()",
                            None,
                            None,
                            None::<&gio::Cancellable>,
                            |_| {},
                        );
                    }
                    TrayAction::Hide => window_for_tray.hide(),
                    TrayAction::Quit => application_for_tray.quit(),
                }
            }
            glib::ControlFlow::Continue
        });

        // A direct/manual launch always gives immediate feedback; subsequent
        // dismissals leave the application, tray, WebView, and sidecar resident.
        window.present();
    });
    application.run();
}
