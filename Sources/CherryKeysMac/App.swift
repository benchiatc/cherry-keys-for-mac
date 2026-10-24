import AppKit
import ApplicationServices
import IOKit.hidsystem
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

final class AppModel: ObservableObject {
    @Published var config = Configuration()
    @Published var enabled = false
    @Published var status = "Ready. Add an assignment, then enable remapping."
    @Published var error: String?
    @Published var devices: [String] = []
    @Published var trusted = false
    @Published var inputMonitoring = false
    @Published var helperStatus = SMAppService.daemon(plistName: CaptureServiceInfo.plist).status
    @Published var helperSetupBusy = false
    private var helperSetupActive = false
    private var helperSetupError: NSError?
    private var helperSetupReturned: Date?
    private var helperSetupRequest = UUID()
    @Published var editing: Assignment? {
        didSet {
            if editing != nil {
                engine.stop()
                status = "Remapping paused while the assignment editor is open."
            } else if enabled {
                setEnabled(true)
            }
        }
    }
    @Published var login = SMAppService.mainApp.status == .enabled
    let engine = InputEngine()
    let store = ConfigurationStore()
    private var loadFailed = false
    init() {
        do { config = try store.load() } catch {
            loadFailed = true
            self.error =
                "Could not read your saved settings. The existing file has been preserved. \(error.localizedDescription)"
        }
        refresh()
        engine.onPause = { [weak self] in
            self?.enabled = false
            self?.status = "Remapping paused. Normal keyboard input is restored."
        }
        engine.onSuspend = { [weak self] in self?.enabled = true }
        engine.runner.onResult = { [weak self] in self?.status = $0 }
        engine.onStatus = { [weak self] in self?.status = $0 }
    }
    func refresh() {
        devices = Hardware.cherryDevices()
        trusted = AXIsProcessTrusted()
        inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        helperStatus = SMAppService.daemon(plistName: CaptureServiceInfo.plist).status
        updateHelperSetup()
    }
    private func updateHelperSetup() {
        guard helperSetupActive else { return }
        switch HelperSetupResult.resolve(
            status: helperStatus, returned: helperSetupReturned != nil,
            error: helperSetupError,
            elapsed: helperSetupReturned.map { Date().timeIntervalSince($0) } ?? 0)
        {
        case .registering: status = "Waiting for macOS to finish helper setup…"
        case .awaitingApproval:
            status =
                "Complete helper approval in macOS Login Items & Extensions. Approval is pending."
        case .ready:
            helperSetupActive = false
            helperSetupError = nil
            status = "Helper setup complete. Enable remapping without an administrator password."
        case .failed(let message):
            // Registration feedback stays inline so it cannot obstruct the OS
            // consent flow. Keep observing: later approval supersedes it.
            status = "Helper setup needs attention: \(message)"
        }
    }
    func setupHelper() {
        guard !helperSetupBusy else { return }
        guard Bundle.main.bundlePath == CaptureServiceInfo.appPath else {
            error = "Open the installed app in Applications before helper setup."
            return
        }
        let service = SMAppService.daemon(plistName: CaptureServiceInfo.plist)
        do { _ = try CaptureServiceInfo.requirement(identifier: "local.cherrykeys.mac") } catch {
            self.error = "Helper setup failed: \(error.localizedDescription)"
            return
        }
        let request = UUID()
        helperSetupRequest = request
        helperSetupActive = true
        helperSetupError = nil
        helperSetupReturned = nil
        helperSetupBusy = true
        status = "Waiting for macOS to finish helper setup…"
        // Keep the main run loop available while macOS presents consent UI and
        // updates registration state. Approval is a normal in-progress state.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var failure: NSError?
            do {
                if service.status != .enabled && service.status != .requiresApproval {
                    try service.register()
                }
            } catch { failure = error as NSError }
            let registrationError = failure
            DispatchQueue.main.async {
                guard let self, self.helperSetupRequest == request else { return }
                self.helperSetupBusy = false
                self.helperSetupReturned = Date()
                self.helperSetupError = registrationError
                self.refresh()
                if HelperSetupResult.resolve(
                    status: self.helperStatus, returned: true, error: registrationError, elapsed: 0)
                    == .awaitingApproval
                {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        }
    }
    func removeHelper() {
        helperSetupRequest = UUID()
        helperSetupActive = false
        helperSetupBusy = false
        setEnabled(false)
        do {
            try SMAppService.daemon(plistName: CaptureServiceInfo.plist).unregister()
            status = "Helper removed. Set it up again before enabling remapping."
        } catch { self.error = "Could not remove helper: \(error.localizedDescription)" }
        refresh()
    }
    func persist() {
        guard !loadFailed else {
            error =
                "Saved settings could not be read. Restore configuration.json.backup in Application Support before saving."
            return
        }
        do {
            try store.save(config)
            engine.assignments = config.active.assignments
        } catch { self.error = error.localizedDescription }
    }
    func setEnabled(_ value: Bool) {
        if !value {
            engine.stop()
            enabled = false
            status = "Remapping paused. Normal keyboard input is restored."
            return
        }
        guard !loadFailed else {
            error = "Restore the saved configuration before enabling remapping."
            return
        }
        if editing != nil {
            enabled = true
            status = "Remapping will resume when the assignment editor closes."
            return
        }
        do {
            try config.active.validate()
            engine.assignments = config.active.assignments
            try engine.start()
            enabled = true
        } catch {
            enabled = false
            self.error = error.localizedDescription
        }
        refresh()
    }
    func upsert(_ a: Assignment) throws {
        var next = config
        guard let p = next.profiles.firstIndex(where: { $0.id == config.active.id }) else { return }
        if let i = next.profiles[p].assignments.firstIndex(where: { $0.id == a.id }) {
            next.profiles[p].assignments[i] = a
        } else {
            next.profiles[p].assignments.append(a)
        }
        try next.validate()
        guard !loadFailed else {
            throw AppError.message("Restore the saved configuration before editing.")
        }
        try store.save(next)
        config = next
        engine.assignments = config.active.assignments
    }
    func swapWindowsAndAlt() {
        guard let index = config.profiles.firstIndex(where: { $0.id == config.active.id }) else {
            return
        }
        engine.router.releaseAll()
        config.profiles[index].assignments.removeAll {
            $0.trigger.kind == .key && [55, 58, 54, 61].contains($0.trigger.code)
        }
        for (source, destination) in [(55, 58), (58, 55), (54, 61), (61, 54)] {
            var a = Assignment()
            a.trigger = Trigger(kind: .key, code: source)
            a.action = .modifier
            a.outputKey = destination
            config.profiles[index].assignments.append(a)
        }
        persist()
        status = "Windows/Command and Alt/Option swapped on both sides of CHERRY keyboards."
    }
    func remove(_ a: Assignment) {
        guard let p = config.profiles.firstIndex(where: { $0.id == config.active.id }) else {
            return
        }
        config.profiles[p].assignments.removeAll { $0.id == a.id }
        persist()
    }
    func addProfile() {
        let p = Profile(name: "Profile \(config.profiles.count + 1)")
        config.profiles.append(p)
        config.selectedProfile = p.id
        persist()
    }
    func select(_ id: UUID) {
        engine.runner.cancel()
        config.selectedProfile = id
        persist()
    }
    func permissions() {
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrusted() { _ = AXIsProcessTrustedWithOptions(options) }
        NSWorkspace.shared.open(
            URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }
    func inputPermissions() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        NSWorkspace.shared.open(
            URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
    func showRunningApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
    func setLogin(_ value: Bool) {
        do {
            if value {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            login = value
        } catch { self.error = error.localizedDescription }
    }
    func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "CherryKeysMac-profile.json"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let e = JSONEncoder()
                e.outputFormatting = [.prettyPrinted, .sortedKeys]
                try e.encode(config).write(to: url, options: .atomic)
            } catch { self.error = error.localizedDescription }
        }
    }
    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let imported = try ConfigurationStore.read(url)
                var next = config
                // Import as new profiles so existing assignments remain available.
                for var p in imported.profiles {
                    p.id = UUID()
                    p.name += " (imported)"
                    next.profiles.append(p)
                }
                try next.validate()
                guard !loadFailed else {
                    throw AppError.message("Restore your saved settings before importing.")
                }
                try store.save(next)
                config = next
                status = "Imported profiles. Select one to use its assignments."
            } catch { self.error = error.localizedDescription }
        }
    }
}

final class MacroRecorder: ObservableObject {
    @Published var active = false
    @Published var steps: [MacroStep] = []
    @Published var captured: Trigger?
    @Published var shortcut: (Int, UInt64)?
    private var monitor: Any?
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var last = Date()
    enum Mode { case trigger, shortcut, macro }
    func start(_ mode: Mode) {
        stop()
        steps = []
        captured = nil
        shortcut = nil
        active = true
        last = Date()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown, .keyUp, .flagsChanged, .systemDefined,
        ]) { [weak self] event in
            guard let self, self.active else { return event }
            switch mode {
            case .trigger:
                if event.type == .flagsChanged
                    && KeyCatalog.modifierKeys.contains(Int(event.keyCode))
                {
                    self.captured = Trigger(kind: .key, code: Int(event.keyCode))
                    self.stop()
                    return nil
                }
                if event.type == .keyDown {
                    self.captured = Trigger(kind: .key, code: Int(event.keyCode))
                    self.stop()
                    return nil
                }
                if event.type == .systemDefined && event.subtype.rawValue == 8
                    && ((event.data1 >> 8) & 0xff) == 0xA
                {
                    self.captured = Trigger(kind: .media, code: (event.data1 >> 16) & 0xffff)
                    self.stop()
                    return nil
                }
            case .shortcut:
                if event.type == .keyDown {
                    self.shortcut = (
                        Int(event.keyCode),
                        UInt64(event.modifierFlags.rawValue) & shortcutMask.rawValue
                    )
                    self.stop()
                    return nil
                }
            case .macro:
                if event.type == .systemDefined { return event }
                let now = Date()
                let delay = self.steps.isEmpty ? 0 : min(now.timeIntervalSince(self.last), 30)
                self.last = now
                var down = event.type == .keyDown
                if event.type == .flagsChanged {
                    let bit: NSEvent.ModifierFlags
                    switch event.keyCode {
                    case 54, 55: bit = .command
                    case 56, 60: bit = .shift
                    case 58, 61: bit = .option
                    case 59, 62: bit = .control
                    case 57: bit = .capsLock
                    default: return nil
                    }
                    down = event.modifierFlags.contains(bit)
                }
                self.steps.append(
                    MacroStep(
                        code: Int(event.keyCode), down: down,
                        flags: UInt64(event.modifierFlags.rawValue), delay: delay))
                if self.steps.count >= 4000 { self.stop() }
                return nil
            }
            return event
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.stop() }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            self?.stop()
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        timer?.invalidate()
        timer = nil
        active = false
    }
    deinit { stop() }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: UUID?
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Image(systemName: "keyboard.fill").font(.title)
                    Text("CHERRY KEYS\nfor Mac").font(.title2.bold())
                }.foregroundStyle(.white)
                Text("KW X ULP").font(.headline).foregroundStyle(.white.opacity(0.65))
                Divider().overlay(.white.opacity(0.2))
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        model.enabled ? "Remapping on" : "Remapping paused",
                        systemImage: model.enabled ? "checkmark.circle.fill" : "pause.circle"
                    ).foregroundStyle(model.enabled ? .green : .white)
                    Button(model.enabled ? "Pause remapping" : "Enable remapping") {
                        model.setEnabled(!model.enabled)
                    }.buttonStyle(.borderedProminent).tint(model.enabled ? .gray : .red)
                    Text("CHERRY keyboards only.\n⌃⌥⌘Esc on CHERRY pauses.").font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                    if model.helperStatus != .enabled {
                        Button(
                            model.helperSetupBusy
                                ? "Setting up helper…"
                                : model.helperStatus == .requiresApproval
                                    ? "Approve helper…" : "Set up helper…"
                        ) { model.setupHelper() }.disabled(model.helperSetupBusy)
                        Text(
                            "One-time macOS approval. Pause and Enable then work without a password, including after reopening the app."
                        ).font(.caption2).foregroundStyle(.white.opacity(0.65))
                    } else {
                        Text(
                            "Helper approved. Pause releases the keyboard; Enable works without a password."
                        ).font(.caption2).foregroundStyle(.white.opacity(0.65))
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("HARDWARE").font(.caption.bold()).foregroundStyle(.white.opacity(0.5))
                    ForEach(model.devices, id: \.self) {
                        Text($0).font(.caption).foregroundStyle(.white.opacity(0.85)).fixedSize(
                            horizontal: false, vertical: true)
                    }
                    if model.devices.isEmpty {
                        Text("No CHERRY device detected").font(.caption).foregroundStyle(
                            .white.opacity(0.65))
                    }
                    Button("Refresh devices") { model.refresh() }.buttonStyle(.link)
                    Button("Swap Windows ↔ Alt") { model.swapWindowsAndAlt() }
                    Text("Swaps Command and Option on both sides in this profile.").font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(
                    "Independent macOS reconstruction.\nBased on CHERRY KEYS 1.0.7.\nNot an official CHERRY release."
                ).font(.caption2).foregroundStyle(.white.opacity(0.5))
            }.padding(24).frame(width: 245).frame(maxHeight: .infinity).background(
                Color(red: 0.13, green: 0.14, blue: 0.16))
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Make every key yours.").font(.largeTitle.bold())
                        Text("Launch, automate, and remap your keyboard.").foregroundStyle(
                            .secondary)
                    }
                    Spacer()
                    Button {
                        model.editing = Assignment()
                    } label: {
                        Label("Add assignment", systemImage: "plus")
                    }.buttonStyle(.borderedProminent).tint(.red)
                }
                HStack {
                    Picker(
                        "Profile",
                        selection: Binding(
                            get: { model.config.active.id }, set: { model.select($0) })
                    ) { ForEach(model.config.profiles) { Text($0.name).tag($0.id) } }.frame(
                        width: 280)
                    Button {
                        model.addProfile()
                    } label: {
                        Image(systemName: "plus")
                    }.help("Create profile")
                    Spacer()
                    Menu("Profiles") {
                        Button("Import…") { model.importSettings() }
                        Button("Export…") { model.exportSettings() }
                    }
                }
                Text(
                    "Two independent layers: preset functions and standard F-keys. With the KW X ULP Fn light off, hold Fn for standard F-keys. Ctrl+Fn switches Fn Lock and reverses the layers."
                ).font(.caption).foregroundStyle(.secondary)
                if !model.trusted || !model.inputMonitoring {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(
                                model.trusted
                                    ? "Accessibility: allowed"
                                    : "Accessibility: this copy needs approval",
                                systemImage: model.trusted ? "checkmark.circle" : "hand.raised")
                            Spacer()
                            Button("Accessibility…") { model.permissions() }
                        }
                        HStack {
                            Label(
                                model.inputMonitoring
                                    ? "Input Monitoring: allowed"
                                    : "Input Monitoring: approval needed",
                                systemImage: model.inputMonitoring ? "checkmark.circle" : "keyboard"
                            )
                            Spacer()
                            Button("Input Monitoring…") { model.inputPermissions() }
                        }
                        Text(
                            "An enabled entry for an older build may not approve this copy. Remove the old entry, add this running app, then quit and reopen it."
                        ).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text(Bundle.main.bundlePath).font(.caption2).textSelection(.enabled)
                                .lineLimit(2)
                            Spacer()
                            Button("Show this app") { model.showRunningApp() }
                            Button("Recheck") { model.refresh() }
                        }
                    }.padding(12).background(
                        .orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                }
                if model.config.active.assignments.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "keyboard").font(.system(size: 58)).foregroundStyle(
                            .secondary)
                        Text("Your first shortcut starts here.").font(.title2.bold())
                        Text(
                            "Choose a function or special key and give it an action.\nUse Ctrl + Fn on the KW X ULP to toggle Fn-lock.\nThe red Fn light means standard F1–F12 keys."
                        ).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("Add an assignment") { model.editing = Assignment() }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selected) {
                        ForEach(model.config.active.assignments) { a in
                            HStack(spacing: 16) {
                                Text(a.trigger.title).font(
                                    .system(.body, design: .monospaced).bold()
                                ).frame(width: 140, alignment: .leading)
                                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(a.action.title).fontWeight(.medium)
                                    Text(a.summary).font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Button("Edit") { model.editing = a }
                                Button {
                                    model.remove(a)
                                } label: {
                                    Image(systemName: "trash")
                                }.help("Delete assignment")
                            }.padding(.vertical, 8).tag(a.id)
                        }
                    }.listStyle(.inset).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Divider()
                HStack {
                    Circle().fill(model.enabled ? .green : .gray).frame(width: 7, height: 7)
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                HStack {
                    Toggle(
                        "Launch at login",
                        isOn: Binding(get: { model.login }, set: { model.setLogin($0) })
                    ).toggleStyle(.checkbox)
                    Spacer()
                    if model.helperStatus == .enabled || model.helperStatus == .requiresApproval {
                        Button("Remove helper") { model.removeHelper() }
                    }
                    Button("Show settings file") {
                        NSWorkspace.shared.selectFile(
                            model.store.url.path, inFileViewerRootedAtPath: "")
                    }
                }.font(.caption)
            }.padding(28).frame(minWidth: 650)
        }.frame(minWidth: 980, minHeight: 630)
            .sheet(item: $model.editing) { a in
                AssignmentEditor(assignment: a).environmentObject(model)
            }
            .alert(
                "Cherry Keys for Mac",
                isPresented: Binding(
                    get: { model.error != nil }, set: { if !$0 { model.error = nil } })
            ) {
                Button("OK") { model.error = nil }
            } message: {
                Text(model.error ?? "")
            }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                model.refresh()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            ) { _ in model.refresh() }
    }
}

struct AssignmentEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State var assignment: Assignment
    @StateObject private var recorder = MacroRecorder()
    @State private var issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Key assignment").font(.title2.bold())
            Text("CHERRY keys and modifiers").font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("Trigger", selection: $assignment.trigger) {
                    Section("Preset functions — Fn light off") {
                        ForEach(ConsumerControl.allCases, id: \.self) { control in
                            Text(control.title).tag(
                                Trigger(kind: .consumer, code: control.rawValue))
                        }
                        ForEach(KeyCatalog.media.keys.sorted(), id: \.self) { code in
                            let trigger = Trigger(kind: .media, code: code)
                            Text(trigger.title).tag(trigger)
                        }
                    }
                    Section("Standard F-keys — hold Fn when Fn light is off") {
                        ForEach(KeyCatalog.functionKeys, id: \.self) { code in
                            let trigger = Trigger(kind: .key, code: code)
                            Text(trigger.title).tag(trigger)
                        }
                    }
                    Section("Modifier keys") {
                        ForEach(KeyCatalog.modifierKeys, id: \.self) { code in
                            Text(KeyCatalog.name(code)).tag(Trigger(kind: .key, code: code))
                        }
                    }
                    if !KeyCatalog.functionKeys.contains(assignment.trigger.code)
                        && !KeyCatalog.modifierKeys.contains(assignment.trigger.code)
                        && assignment.trigger.kind == .key
                    {
                        Text(assignment.trigger.title).tag(assignment.trigger)
                    }
                }
                Button(recorder.active ? "Listening…" : "Detect key") { recorder.start(.trigger) }
                    .disabled(recorder.active)
            }
            Text(
                "Preset functions and Fn + F-keys have separate assignments. With the KW X ULP Fn light off, F12 sends Mail; Fn + F12 sends standard F12. Ctrl+Fn reverses these layers. For preset launch keys, choose the named trigger above; Detect key may not see them."
            ).font(.caption).foregroundStyle(.secondary)
            Picker("Action", selection: $assignment.action) {
                ForEach(ActionKind.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Group {
                switch assignment.action {
                case .modifier:
                    Picker("Modifier", selection: $assignment.outputKey) {
                        ForEach(KeyCatalog.modifierKeys, id: \.self) { code in
                            Text(KeyCatalog.name(code)).tag(code)
                        }
                    }
                    Text(
                        "Held modifier behavior is preserved for shortcuts. Applies only to CHERRY keyboards."
                    ).font(.caption)
                case .macAction:
                    Picker("Mac action", selection: $assignment.value) {
                        Text("Choose…").tag("")
                        ForEach(MacAction.allCases, id: \.self) { action in
                            Text(action.title).tag(action.rawValue)
                        }
                    }
                    Text("Uses standard macOS shortcuts; customized system shortcuts may differ.")
                        .font(.caption)
                case .shortcut:
                    HStack {
                        Text(
                            KeyCatalog.modifierLabel(assignment.modifiers)
                                + KeyCatalog.name(assignment.outputKey)
                        ).font(.title.monospaced()).frame(maxWidth: .infinity)
                        Button("Record shortcut") { recorder.start(.shortcut) }.disabled(
                            recorder.active)
                    }
                case .text:
                    TextEditor(text: $assignment.value).font(.body.monospaced()).frame(height: 145)
                        .border(.gray.opacity(0.3))
                    Text("Typed directly; your clipboard stays unchanged.").font(.caption)
                        .foregroundStyle(.secondary)
                case .macro:
                    HStack {
                        Button(recorder.active ? "Stop recording" : "Record macro") {
                            if recorder.active {
                                recorder.stop()
                                assignment.steps = recorder.steps
                            } else {
                                recorder.start(.macro)
                            }
                        }
                        Text(
                            "\(recorder.active ? recorder.steps.count : assignment.steps.count) events"
                        )
                    }
                    Text(
                        "Records keyboard input only inside this app. Original delays are preserved, up to 30 seconds between events. Click Stop when finished. Recording stops if you switch apps."
                    ).font(.caption).foregroundStyle(.secondary)
                case .application, .file:
                    HStack {
                        TextField("Choose a file…", text: $assignment.value)
                        Button("Choose…") { chooseFile() }
                    }
                case .website:
                    TextField("https://example.com", text: $assignment.value)
                case .media:
                    Picker("Control", selection: $assignment.mediaCode) {
                        ForEach(KeyCatalog.media.keys.sorted(), id: \.self) {
                            Text(KeyCatalog.media[$0]!).tag($0)
                        }
                    }
                case .browserBack, .browserForward:
                    Text("Sends the standard macOS browser navigation shortcut.").foregroundStyle(
                        .secondary)
                case .defaultMail:
                    Text("Opens the mail app selected in macOS without composing a message.")
                        .foregroundStyle(.secondary)
                case .disable:
                    Text("The trigger is suppressed while remapping is enabled.").foregroundStyle(
                        .secondary)
                case .lock:
                    Text("Sends the standard macOS Control–Command–Q lock shortcut.")
                        .foregroundStyle(.secondary)
                case .sleep:
                    Text("Puts this Mac to sleep when you release the assigned key.")
                        .foregroundStyle(.secondary)
                }
            }
            if recorder.active {
                Label(
                    "Listening in this window. Click Stop listening to cancel.",
                    systemImage: "record.circle"
                ).foregroundStyle(.red)
                Button("Stop listening") { recorder.stop() }
            }
            if let issue { Text(issue).foregroundStyle(.red).font(.caption) }
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save assignment") { save() }.buttonStyle(.borderedProminent).tint(.red)
                    .disabled(recorder.active)
            }
        }.padding(28).frame(width: 600)
            .onDisappear { recorder.stop() }
            .onChange(of: recorder.captured) { value in
                if let value {
                    assignment.trigger = value
                    if value.kind == .key && KeyCatalog.modifierKeys.contains(value.code) {
                        assignment.action = .modifier
                        assignment.outputKey = value.code
                    }
                }
            }
            .onChange(of: assignment.trigger) { trigger in
                if trigger.kind == .key && KeyCatalog.modifierKeys.contains(trigger.code) {
                    assignment.action = .modifier
                    assignment.outputKey = trigger.code
                }
            }
            .onChange(of: recorder.active) { active in
                if !active, !recorder.steps.isEmpty, assignment.action == .macro {
                    assignment.steps = recorder.steps
                }
                if let shortcut = recorder.shortcut {
                    assignment.outputKey = shortcut.0
                    assignment.modifiers = shortcut.1
                }
            }
    }
    private func save() {
        do {
            try assignment.validate()
            try model.upsert(assignment)
            dismiss()
        } catch { issue = error.localizedDescription }
    }
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = assignment.action == .file
        panel.canChooseFiles = true
        if assignment.action == .application { panel.allowedContentTypes = [.applicationBundle] }
        if panel.runModal() == .OK, let url = panel.url { assignment.value = url.path }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { note in
            guard let closing = note.object as? NSWindow, closing.title == "Cherry Keys for Mac"
            else { return }
            DispatchQueue.main.async {
                if !NSApp.windows.contains(where: {
                    $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && !$0.isSheet
                }) {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
    func applicationWillTerminate(_ notification: Notification) { model?.engine.stop() }
}

@main
struct CherryKeysMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    init() {
        if CommandLine.arguments.contains("--diagnostics") {
            let diagnostics: [String: Any] = [
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    ?? "development", "accessibility": AXIsProcessTrusted(),
                "inputMonitoring": CGPreflightListenEventAccess(),
                "cherryDevices": Hardware.cherryDevices(),
                "engine": "Native per-device HID capture and relay",
                "scope": "CHERRY keyboards only (USB 046A; verified KW X ULP Bluetooth identity)",
                "karabinerRequired": false,
            ]
            if let data = try? JSONSerialization.data(
                withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys])
            {
                print(String(decoding: data, as: UTF8.self))
            }
            exit(0)
        }
    }
    var body: some Scene {
        WindowGroup("Cherry Keys for Mac", id: "main") {
            ContentView().environmentObject(model).onAppear {
                delegate.model = model
                NSApp.setActivationPolicy(.regular)
            }
        }.defaultSize(width: 1030, height: 690)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("Add assignment") { model.editing = Assignment() }.keyboardShortcut("n")
                }
                CommandMenu("Remapping") {
                    Button(model.enabled ? "Pause remapping" : "Enable remapping") {
                        model.setEnabled(!model.enabled)
                    }
                    Button("Cancel running macro") { model.engine.runner.cancel() }
                }
            }
        MenuBarExtra("Cherry Keys", systemImage: model.enabled ? "keyboard.fill" : "keyboard") {
            MenuBarContent().environmentObject(model)
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(
            model.editing != nil
                ? "Paused while editing"
                : (model.enabled ? "Remapping enabled" : "Remapping paused"))
        Button("Open Cherry Keys") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(model.enabled ? "Pause remapping" : "Enable remapping") {
            model.setEnabled(!model.enabled)
        }
        Button("Cancel running macro") { model.engine.runner.cancel() }
        Divider()
        Button("Quit") {
            model.engine.stop()
            NSApp.terminate(nil)
        }.keyboardShortcut("q")
    }
}
