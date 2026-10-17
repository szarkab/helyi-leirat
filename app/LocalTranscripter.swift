import AppKit
import UniformTypeIdentifiers

struct Configuration: Decodable {
    let worker: String
    let tools: String
}

struct ModelSetupOutput: Decodable {
    let ready: Bool
    let note: String?
}

struct ProcessingStatus: Decodable {
    let message: String
}

struct RecognitionOutput: Decodable {
    let transcript: String
    let markdown: String
    let repetition_warnings: Int
    let quality_note: String?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private enum Work { case checking, preparing, transcribing(URL) }
    private var work = Work.checking
    private var modelReady = false
    private let setup = NSButton(title: "Modell letöltése (3,2 GB)…", target: nil, action: nil)
    private var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Helyi leirat", isDirectory: true)
    }
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString: "Válassz egy M4A-, MP3- vagy WAV-hangfelvételt az átíráshoz.")
    private let filename = NSTextField(labelWithString: "Nincs kiválasztott hangfelvétel")
    private let choose = NSButton(title: "Hangfelvétel kiválasztása…", target: nil, action: nil)
    private let save = NSButton(title: "Leirat mentése…", target: nil, action: nil)
    private let cancel = NSButton(title: "Megszakítás", target: nil, action: nil)
    private var statusTimer: Timer?
    private var cancelling = false
    private let speakers = NSButton(checkboxWithTitle: "Beszélők elkülönítése", target: nil, action: nil)
    private let format = NSPopUpButton(frame: .zero, pullsDown: false)
    private let progress = NSProgressIndicator()
    private var transcript: URL?
    private var markdown: URL?
    private var source: URL?
    private var process: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        menu.addItem(applicationItem)
        let applicationMenu = NSMenu()
        let about = applicationMenu.addItem(withTitle: "A Helyi leirat névjegye", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        let licenses = applicationMenu.addItem(withTitle: "Licencek és források…", action: #selector(showLicenses), keyEquivalent: "")
        licenses.target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Kilépés", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Helyi leirat"
        window.delegate = self
        window.isReleasedWhenClosed = false
        let title = NSTextField(labelWithString: "Magyar hangból helyi leirat")
        title.font = .systemFont(ofSize: 25, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: "Whisper large-v3 · Apple Silicon\nA hang feldolgozása ezen a Macen történik.")
        detail.textColor = .secondaryLabelColor
        filename.lineBreakMode = .byTruncatingMiddle
        choose.target = self
        choose.action = #selector(selectAudio)
        save.target = self
        save.action = #selector(saveTranscript)
        save.isEnabled = false
        cancel.target = self
        cancel.action = #selector(cancelRun)
        cancel.isEnabled = false
        choose.isEnabled = false
        setup.target = self
        setup.action = #selector(prepareModel)
        setup.isHidden = true
        speakers.toolTip = "A beszélőszám automatikus becslés. Első használatkor kb. 108 MB modell töltődik le; a hang a gépen marad."
        format.addItems(withTitles: ["TXT (.txt)", "Markdown (.md)"])
        format.setAccessibilityLabel("Export formátuma")
        progress.style = .spinning
        progress.isDisplayedWhenStopped = false
        status.setAccessibilityIdentifier("transcriptionStatus")
        let buttons = NSStackView(views: [choose, format, save])
        let processing = NSStackView(views: [cancel, progress])
        processing.spacing = 12
        buttons.spacing = 12
        let options = NSStackView(views: [speakers])
        options.spacing = 12
        let stack = NSStackView(views: [title, detail, setup, options, filename, buttons, processing, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 30),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -24)
        ])
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        start(.checking)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Helyi leirat",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            .credits: NSAttributedString(string: "Ingyenes, helyi magyar átírás Apple Siliconra.\nMIT licenc.\nWhisper large-v3 · MLX\nFFmpeg: LGPL-2.1-or-later.\nLicencek és FFmpeg-forrás: a Licencek és források menüben.")
        ])
    }

    @objc private func showLicenses() {
        guard let resources = Bundle.main.resourceURL else { return }
        NSWorkspace.shared.open(resources.appendingPathComponent("ThirdParty", isDirectory: true))
    }

    @objc private func selectAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "m4a")!, .mp3, .wav]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.start(.transcribing(url))
        }
    }

    @objc private func prepareModel() { start(.preparing) }

    private func start(_ nextWork: Work) {
        work = nextWork
        cancelling = false
        if case let .transcribing(audio) = work {
            transcript = nil
            markdown = nil
            source = audio
            filename.stringValue = audio.lastPathComponent
        }
        save.isEnabled = false
        choose.isEnabled = false
        cancel.isEnabled = true
        speakers.isEnabled = false
        setup.isEnabled = false
        switch work {
        case .checking: status.stringValue = "Helyi modell ellenőrzése…"; cancel.isEnabled = false
        case .preparing: status.stringValue = "A Whisper modell előkészítése…"
        case .transcribing: status.stringValue = "Helyi átírás folyamatban…"
        }
        progress.startAnimation(nil)
        do {
            guard let configURL = Bundle.main.url(forResource: "configuration", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: configURL))
            guard let resources = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
            let root = dataDirectory
            try FileManager.default.createDirectory(at: root.appendingPathComponent("runs"),
                                                     withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            let run = root.appendingPathComponent("runs").appendingPathComponent(UUID().uuidString)
            let model = root.appendingPathComponent("models/large-v3")
            let speakerModels = root.appendingPathComponent("models/speakers")
            let task = Process()
            let outputURL = run.appendingPathExtension("stdout.json")
            let errorsURL = run.appendingPathExtension("stderr.log")
            FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            FileManager.default.createFile(atPath: errorsURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let output = try FileHandle(forWritingTo: outputURL)
            let errors = try FileHandle(forWritingTo: errorsURL)
            defer { try? output.close(); try? errors.close() }
            task.executableURL = resources.appendingPathComponent(config.worker)
            var arguments = ["--output", run.path, "--model", model.path, "--speaker-models", speakerModels.path]
            switch work {
            case .checking: arguments.append("--check-model")
            case .preparing: arguments.append("--prepare-model")
            case let .transcribing(audio):
                arguments += ["--audio", audio.path]
                if speakers.state == .on { arguments.append("--speakers") }
            }
            task.arguments = arguments
            task.currentDirectoryURL = root
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = resources.appendingPathComponent(config.tools).path + ":/usr/bin:/bin:/usr/sbin:/sbin"
            for key in ["PYTHONHOME", "PYTHONPATH", "__PYVENV_LAUNCHER__", "PYTHONUSERBASE"] {
                environment.removeValue(forKey: key)
            }
            environment["HF_HUB_OFFLINE"] = "1"
            environment["HF_HUB_DISABLE_TELEMETRY"] = "1"
            task.environment = environment
            task.standardOutput = output
            task.standardError = errors
            // Files avoid pipe-buffer deadlocks while the worker is running.
            task.terminationHandler = { [weak self] completed in
                let data = (try? Data(contentsOf: outputURL)) ?? Data()
                let errorData = (try? Data(contentsOf: errorsURL)) ?? Data()
                let succeeded = completed.terminationStatus == 0
                DispatchQueue.main.async {
                    self?.finish(data: data, errors: errorData, succeeded: succeeded)
                }
            }
            try task.run()
            process = task
            let statusURL = run.appendingPathExtension("status.json")
            statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.cancelling,
                          let data = try? Data(contentsOf: statusURL),
                          let state = try? JSONDecoder().decode(ProcessingStatus.self, from: data) else { return }
                    self.status.stringValue = state.message
                }
            }
        } catch {
            finish(data: Data(), errors: Data("Az alkalmazás helyi futtatókörnyezete nem indítható. Ellenőrizd, hogy az alkalmazás teljes egészében át lett másolva.".utf8), succeeded: false)
        }
    }

    @objc private func cancelRun() {
        guard let process, !cancelling else { return }
        cancelling = true
        cancel.isEnabled = false
        status.stringValue = "Megszakítás folyamatban…"
        process.terminate()
    }

    private func finish(data: Data, errors: Data, succeeded: Bool) {
        statusTimer?.invalidate()
        statusTimer = nil
        process = nil
        cancel.isEnabled = false
        progress.stopAnimation(nil)
        setup.isEnabled = true
        switch work {
        case .checking, .preparing:
            let result = try? JSONDecoder().decode(ModelSetupOutput.self, from: data)
            let ready = succeeded && result?.ready == true
            modelReady = ready
            setup.isHidden = ready
            choose.isEnabled = ready
            speakers.isEnabled = ready
            if cancelling {
                status.stringValue = "A modell letöltése megszakítva. Az előkészítést újraindíthatod."
            } else if ready {
                status.stringValue = "A helyi modell készen áll. Válassz egy hangfelvételt."
                if let note = result?.note { status.stringValue += " " + note }
            } else if succeeded {
                status.stringValue = "Első használathoz töltsd le a Whisper modellt (kb. 3,2 GB). Utána internet nélkül is átírhatsz."
            } else {
                status.stringValue = "A modell ellenőrzése vagy letöltése nem sikerült. Ellenőrizd az internetkapcsolatot és a szabad tárhelyet, majd próbáld újra."
            }
            return
        case .transcribing: break
        }
        choose.isEnabled = modelReady
        speakers.isEnabled = true
        if cancelling {
            status.stringValue = "A feldolgozás megszakítva. Nem készült teljes leirat."
            return
        }
        guard succeeded, let result = try? JSONDecoder().decode(RecognitionOutput.self, from: data),
              FileManager.default.isReadableFile(atPath: result.transcript),
              FileManager.default.isReadableFile(atPath: result.markdown) else {
            status.stringValue = String(data: errors, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
                ?? "A helyi átírás nem sikerült. Új hangfelvétellel ismét megpróbálhatod."
            return
        }
        transcript = URL(fileURLWithPath: result.transcript)
        markdown = URL(fileURLWithPath: result.markdown)
        save.isEnabled = true
        status.stringValue = result.repetition_warnings > 0
            ? "A leirat elkészült, figyelmeztetést tartalmaz. Mentés után ellenőrizd a jelölt részeket a hang alapján."
            : "A leirat elkészült. A Leirat mentése gombbal választhatod ki a mentés helyét."
        if let note = result.quality_note { status.stringValue += " " + note }
    }

    @objc private func saveTranscript() {
        let isMarkdown = format.indexOfSelectedItem == 1
        guard let export = isMarkdown ? markdown : transcript else { return }
        let suffix = isMarkdown ? "md" : "txt"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [isMarkdown ? UTType(filenameExtension: "md")! : .plainText]
        panel.nameFieldStringValue = (source?.deletingPathExtension().lastPathComponent ?? "Leirat") + "." + suffix
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            do {
                // A text export must never overwrite the original recording.
                if destination.resolvingSymlinksInPath() == self.source?.resolvingSymlinksInPath() {
                    throw CocoaError(.fileWriteInvalidFileName)
                }
                try Data(contentsOf: export).write(to: destination, options: .atomic)
                self.status.stringValue = "Leirat elmentve: \(destination.path)"
            } catch {
                self.status.stringValue = "A leirat mentése nem sikerült. Válassz másik nevet vagy írható mappát."
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if process != nil {
            status.stringValue = "Átírás folyamatban. A Megszakítás gombbal leállíthatod; közben kis méretre teheted."
            return false
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if process != nil {
            status.stringValue = "Átírás folyamatban. Kilépés előtt a Megszakítás gombbal leállíthatod."
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
