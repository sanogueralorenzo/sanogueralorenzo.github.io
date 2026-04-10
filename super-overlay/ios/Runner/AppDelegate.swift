import Flutter
import Foundation
import UIKit

#if canImport(MoonshineVoice)
import MoonshineVoice
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let moonshineManager = MoonshineIOSManager()
  private var moonshineChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MoonshineIOSBridge")
    else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "super_overlay/moonshine",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMoonshineCall(call: call, result: result)
    }
    moonshineChannel = channel
  }

  private func handleMoonshineCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "state":
      result([
        "supported": moonshineManager.isSupported,
        "ready": moonshineManager.isReady,
        "downloading": moonshineManager.isDownloading,
      ])
    case "prepare":
      moonshineManager.prepare { ready, error in
        result([
          "ready": ready,
          "error": error,
        ])
      }
    case "start":
      moonshineManager.start { started, error in
        result([
          "started": started,
          "error": error,
        ])
      }
    case "stop":
      moonshineManager.stop { transcript, error in
        result([
          "transcript": transcript,
          "error": error,
        ])
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private struct MoonshineModelSpec {
  let fileName: String
  let url: String
  let sizeBytes: Int64
}

private final class MoonshineIOSManager {
  private let queue = DispatchQueue(label: "super_overlay.moonshine")

  private let modelSpecs: [MoonshineModelSpec] = [
    MoonshineModelSpec(
      fileName: "adapter.ort",
      url: "https://download.moonshine.ai/model/medium-streaming-en/quantized/adapter.ort",
      sizeBytes: 3_647_712
    ),
    MoonshineModelSpec(
      fileName: "cross_kv.ort",
      url: "https://download.moonshine.ai/model/medium-streaming-en/quantized/cross_kv.ort",
      sizeBytes: 11_544_952
    ),
    MoonshineModelSpec(
      fileName: "decoder_kv.ort",
      url: "https://download.moonshine.ai/model/medium-streaming-en/quantized/decoder_kv.ort",
      sizeBytes: 146_216_448
    ),
    MoonshineModelSpec(
      fileName: "encoder.ort",
      url: "https://download.moonshine.ai/model/medium-streaming-en/quantized/encoder.ort",
      sizeBytes: 94_202_872
    ),
    MoonshineModelSpec(
      fileName: "frontend.ort",
      url: "https://download.moonshine.ai/model/medium-streaming-en/quantized/frontend.ort",
      sizeBytes: 47_467_256
    ),
    MoonshineModelSpec(
      fileName: "streaming_config.json",
      url: "https://download.moonshine.ai/model/medium-streaming-en/quantized/streaming_config.json",
      sizeBytes: 513
    ),
    MoonshineModelSpec(
      fileName: "tokenizer.bin",
      url: "https://download.moonshine.ai/model/medium-streaming-en/quantized/tokenizer.bin",
      sizeBytes: 249_974
    ),
  ]

  private var internalIsDownloading = false
  private var latestTranscript = ""

  #if canImport(MoonshineVoice)
  private var micTranscriber: MicTranscriber?
  #endif

  var isSupported: Bool {
    #if canImport(MoonshineVoice)
    return true
    #else
    return false
    #endif
  }

  var isDownloading: Bool {
    return queue.sync { internalIsDownloading }
  }

  var isReady: Bool {
    guard isSupported else {
      return false
    }
    return queue.sync {
      modelSpecs.allSatisfy { spec in
        let file = modelsDirectory.appendingPathComponent(spec.fileName)
        guard let values = try? file.resourceValues(forKeys: [.fileSizeKey]),
          let size = values.fileSize
        else {
          return false
        }
        return Int64(size) == spec.sizeBytes
      }
    }
  }

  func prepare(completion: @escaping (Bool, String?) -> Void) {
    guard isSupported else {
      completion(false, "MoonshineVoice iOS package is not linked.")
      return
    }

    queue.async {
      if self.modelSpecs.allSatisfy({ self.isSpecPresent($0) }) {
        let loaded = self.ensureTranscriberLoaded()
        DispatchQueue.main.async {
          completion(loaded, loaded ? nil : "Could not load Moonshine transcriber.")
        }
        return
      }

      if self.internalIsDownloading {
        DispatchQueue.main.async {
          completion(false, nil)
        }
        return
      }

      self.internalIsDownloading = true
      let downloadResult = self.downloadMissingModels()
      self.internalIsDownloading = false
      if let error = downloadResult {
        DispatchQueue.main.async {
          completion(false, error)
        }
        return
      }

      let loaded = self.ensureTranscriberLoaded()
      DispatchQueue.main.async {
        completion(loaded, loaded ? nil : "Could not load Moonshine transcriber.")
      }
    }
  }

  func start(completion: @escaping (Bool, String?) -> Void) {
    guard isSupported else {
      completion(false, "MoonshineVoice iOS package is not linked.")
      return
    }

    prepare { [weak self] ready, error in
      guard let self else {
        completion(false, "Moonshine manager unavailable.")
        return
      }
      guard ready else {
        completion(false, error)
        return
      }

      self.queue.async {
        self.latestTranscript = ""
        #if canImport(MoonshineVoice)
        guard let transcriber = self.micTranscriber else {
          DispatchQueue.main.async {
            completion(false, "Moonshine transcriber is not initialized.")
          }
          return
        }
        do {
          try transcriber.start()
          DispatchQueue.main.async {
            completion(true, nil)
          }
        } catch {
          DispatchQueue.main.async {
            completion(false, error.localizedDescription)
          }
        }
        #else
        DispatchQueue.main.async {
          completion(false, "MoonshineVoice iOS package is not linked.")
        }
        #endif
      }
    }
  }

  func stop(completion: @escaping (String, String?) -> Void) {
    guard isSupported else {
      completion("", "MoonshineVoice iOS package is not linked.")
      return
    }

    queue.async {
      #if canImport(MoonshineVoice)
      guard let transcriber = self.micTranscriber else {
        DispatchQueue.main.async {
          completion("", "Moonshine transcriber is not initialized.")
        }
        return
      }
      do {
        try transcriber.stop()
        let transcript = self.latestTranscript
          .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async {
          completion(transcript, nil)
        }
      } catch {
        DispatchQueue.main.async {
          completion("", error.localizedDescription)
        }
      }
      #else
      DispatchQueue.main.async {
        completion("", "MoonshineVoice iOS package is not linked.")
      }
      #endif
    }
  }

  private var modelsDirectory: URL {
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return base
      .appendingPathComponent("models", isDirectory: true)
      .appendingPathComponent("moonshine", isDirectory: true)
      .appendingPathComponent("medium-streaming-en", isDirectory: true)
  }

  private func isSpecPresent(_ spec: MoonshineModelSpec) -> Bool {
    let file = modelsDirectory.appendingPathComponent(spec.fileName)
    guard let values = try? file.resourceValues(forKeys: [.fileSizeKey]),
      let size = values.fileSize
    else {
      return false
    }
    return Int64(size) == spec.sizeBytes
  }

  private func downloadMissingModels() -> String? {
    do {
      try FileManager.default.createDirectory(
        at: modelsDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      return "Could not create model directory: \(error.localizedDescription)"
    }

    for spec in modelSpecs {
      if isSpecPresent(spec) {
        continue
      }

      guard let url = URL(string: spec.url) else {
        return "Invalid Moonshine URL: \(spec.url)"
      }

      let target = modelsDirectory.appendingPathComponent(spec.fileName)
      let temp = target.appendingPathExtension("download_tmp")
      try? FileManager.default.removeItem(at: temp)

      if let downloadError = download(url: url, to: temp) {
        try? FileManager.default.removeItem(at: temp)
        return downloadError
      }

      guard let values = try? temp.resourceValues(forKeys: [.fileSizeKey]),
        let size = values.fileSize,
        Int64(size) == spec.sizeBytes
      else {
        try? FileManager.default.removeItem(at: temp)
        return "Unexpected size for \(spec.fileName)."
      }

      try? FileManager.default.removeItem(at: target)
      do {
        try FileManager.default.moveItem(at: temp, to: target)
      } catch {
        return "Could not move \(spec.fileName): \(error.localizedDescription)"
      }
    }

    return nil
  }

  private func download(url: URL, to target: URL) -> String? {
    let semaphore = DispatchSemaphore(value: 0)
    var downloadError: String?

    let task = URLSession.shared.downloadTask(with: url) { tempUrl, response, error in
      defer { semaphore.signal() }

      if let error {
        downloadError = error.localizedDescription
        return
      }

      guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        downloadError = "Download failed with invalid response."
        return
      }

      guard let tempUrl else {
        downloadError = "Download failed with no file URL."
        return
      }

      do {
        try FileManager.default.copyItem(at: tempUrl, to: target)
      } catch {
        downloadError = error.localizedDescription
      }
    }

    task.resume()
    semaphore.wait()
    return downloadError
  }

  private func ensureTranscriberLoaded() -> Bool {
    #if canImport(MoonshineVoice)
    if micTranscriber != nil {
      return true
    }

    do {
      let modelPath = modelsDirectory.path
      let transcriber = try MicTranscriber(modelPath: modelPath, modelArch: .mediumStreaming)
      transcriber.addListener { [weak self] event in
        self?.queue.async {
          self?.latestTranscript = event.line.text
        }
      }
      micTranscriber = transcriber
      return true
    } catch {
      return false
    }
    #else
    return false
    #endif
  }
}
