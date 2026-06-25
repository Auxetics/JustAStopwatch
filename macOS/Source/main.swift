import Cocoa
import ServiceManagement
import UserNotifications

enum UpdateState {
    case upToDate
    case downloading
    case updateReady(dmgURL: URL)
}

enum AppMode {
    case stopwatch
    case pomodoro
}

enum PomodoroSession {
    case work
    case `break`
}

class AutoUpdater: NSObject {
    var currentState: UpdateState = .upToDate
    var currentVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    func checkForUpdates() {
        let url = URL(string: "https://api.github.com/repos/Auxetics/WFHTimer/releases/latest")!
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let tagName = json["tag_name"] as? String,
                   let assets = json["assets"] as? [[String: Any]] {
                    
                    let version = tagName.replacingOccurrences(of: "v", with: "")
                    if version.compare(self.currentVersion, options: .numeric) == .orderedDescending {
                        if let dmgAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
                           let downloadURLString = dmgAsset["browser_download_url"] as? String,
                           let downloadURL = URL(string: downloadURLString) {
                            self.downloadUpdate(url: downloadURL)
                        }
                    }
                }
            } catch {
                print("Error parsing JSON: \(error)")
            }
        }
        task.resume()
    }
    
    func downloadUpdate(url: URL) {
        DispatchQueue.main.async {
            self.currentState = .downloading
        }
        
        let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
            guard let localURL = localURL, error == nil else {
                DispatchQueue.main.async { self.currentState = .upToDate }
                return
            }
            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory
            let destinationURL = tempDir.appendingPathComponent("WFHTimer_Update.dmg")
            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.moveItem(at: localURL, to: destinationURL)
                
                DispatchQueue.main.async {
                    self.currentState = .updateReady(dmgURL: destinationURL)
                }
            } catch {
                print("Failed to save update DMG: \(error)")
                DispatchQueue.main.async { self.currentState = .upToDate }
            }
        }
        task.resume()
    }
    
    func applyUpdate(dmgURL: URL) {
        let script = """
        #!/bin/bash
        sleep 3
        hdiutil attach "\(dmgURL.path)" -nobrowse -mountpoint /Volumes/WFHTimerUpdate
        rm -rf "/Applications/WFHTimer.app"
        cp -R "/Volumes/WFHTimerUpdate/WFHTimer.app" "/Applications/"
        hdiutil detach /Volumes/WFHTimerUpdate -force
        open "/Applications/WFHTimer.app"
        """
        
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("update_wfhtimer.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            process.arguments = ["/bin/bash", scriptURL.path]
            if #available(macOS 10.13, *) {
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
            }
            try process.run()
            
            NSApp.terminate(nil)
        } catch {
            print("Failed to run update script: \(error)")
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    
    var timer: Timer?
    var startTime: Date?
    var accumulatedTime: TimeInterval = 0
    var isRunning = false
    var mode: AppMode = .stopwatch
    var pomodoroSession: PomodoroSession = .work
    var pomodoroRemainingSeconds: TimeInterval = 0
    
    var lastClickTime: Date?
    let updater = AutoUpdater()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in }
        UNUserNotificationCenter.current().delegate = self
        
        // Load defaults if empty
        if UserDefaults.standard.integer(forKey: "workDuration") == 0 {
            UserDefaults.standard.set(25, forKey: "workDuration")
        }
        if UserDefaults.standard.integer(forKey: "breakDuration") == 0 {
            UserDefaults.standard.set(5, forKey: "breakDuration")
        }
        
        reset()
        updater.checkForUpdates()
    }
    
    // Show notifications even if app is focused
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
    
    @objc func handleClick() {
        guard let currentEvent = NSApp.currentEvent else { return }
        
        if currentEvent.type == .rightMouseDown {
            showMenu(event: currentEvent)
            return
        }
        
        let now = Date()
        if let lastClick = lastClickTime, now.timeIntervalSince(lastClick) < 0.35 {
            lastClickTime = nil
            handleDoubleClick()
        } else {
            lastClickTime = now
            handleSingleClick()
        }
    }
    
    @objc func handleSingleClick() {
        if isRunning {
            pause()
        } else {
            start()
        }
    }
    
    @objc func handleDoubleClick() {
        reset()
    }
    
    func start() {
        if isRunning { return }
        isRunning = true
        startTime = Date()
        
        updateTime()
        timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateTime), userInfo: nil, repeats: true)
        RunLoop.current.add(timer!, forMode: .common)
    }
    
    func pause() {
        if !isRunning { return }
        isRunning = false
        if let start = startTime {
            if mode == .stopwatch {
                accumulatedTime += Date().timeIntervalSince(start)
            } else {
                pomodoroRemainingSeconds -= Date().timeIntervalSince(start)
            }
        }
        startTime = nil
        timer?.invalidate()
        timer = nil
        updateTime()
    }
    
    func reset() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        accumulatedTime = 0
        startTime = nil
        
        if mode == .pomodoro {
            let workMins = UserDefaults.standard.integer(forKey: "workDuration")
            pomodoroRemainingSeconds = TimeInterval(workMins * 60)
            pomodoroSession = .work
        }
        
        updateTime()
    }
    
    @objc func updateTime() {
        if mode == .stopwatch {
            var elapsed = accumulatedTime
            if let start = startTime, isRunning {
                elapsed += Date().timeIntervalSince(start)
            }
            updateDisplay(seconds: Int(elapsed))
        } else {
            var remaining = pomodoroRemainingSeconds
            if let start = startTime, isRunning {
                remaining -= Date().timeIntervalSince(start)
            }
            
            if remaining <= 0 && isRunning {
                handlePomodoroEnd()
                return
            }
            updateDisplay(seconds: Int(max(0, remaining)))
        }
    }
    
    func sendRobustNotification(title: String, body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = UNNotificationSound.default
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
            } else {
                DispatchQueue.main.async {
                    let script = "display notification \"\(body)\" with title \"\(title)\" sound name \"Glass\""
                    var error: NSDictionary?
                    if let appleScript = NSAppleScript(source: script) {
                        appleScript.executeAndReturnError(&error)
                    }
                }
            }
        }
    }
    
    func handlePomodoroEnd() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        startTime = nil
        
        if pomodoroSession == .work {
            pomodoroSession = .break
            let breakMins = UserDefaults.standard.integer(forKey: "breakDuration")
            pomodoroRemainingSeconds = TimeInterval(breakMins * 60)
            sendRobustNotification(title: "Work Session Complete!", body: "Time for a break.")
        } else {
            pomodoroSession = .work
            let workMins = UserDefaults.standard.integer(forKey: "workDuration")
            pomodoroRemainingSeconds = TimeInterval(workMins * 60)
            sendRobustNotification(title: "Break Over!", body: "Back to work.")
        }
        
        // Auto start next phase
        start()
    }
    
    func updateDisplay(seconds totalSeconds: Int) {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        let timeString: String
        if hours >= 1 {
            timeString = String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            timeString = String(format: "%02d:%02d", minutes, secs)
        }
        
        if let button = statusItem.button {
            let fontSize = NSFont.systemFontSize
            let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
            
            let textColor: NSColor = (mode == .pomodoro && pomodoroSession == .break) ? NSColor.systemOrange : NSColor.labelColor
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            
            let attributedTime = NSMutableAttributedString(string: timeString, attributes: attributes)
            
            let hasStartedStopwatch = mode == .stopwatch && (accumulatedTime > 0 || isRunning)
            let hasStartedPomodoro = mode == .pomodoro && (pomodoroRemainingSeconds < TimeInterval(UserDefaults.standard.integer(forKey: "workDuration") * 60) || isRunning)
            let shouldShowDot = hasStartedStopwatch || hasStartedPomodoro
            
            let finalString = NSMutableAttributedString()
            
            if shouldShowDot {
                let dotColor: NSColor = isRunning ? NSColor.systemGreen : NSColor.systemOrange
                let dotAttr: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: dotColor
                ]
                let dotString = NSAttributedString(string: "● ", attributes: dotAttr)
                finalString.append(dotString)
            }
            
            finalString.append(attributedTime)
            
            button.attributedTitle = finalString
        }
    }
    
    func showMenu(event: NSEvent) {
        let menu = NSMenu()
        
        // Toggle Mode
        let modeItem = NSMenuItem(title: mode == .stopwatch ? "Switch to Pomodoro Mode" : "Switch to Stopwatch Mode", action: #selector(toggleMode), keyEquivalent: "")
        modeItem.target = self
        menu.addItem(modeItem)
        
        // Preferences
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Auto-Updater
        let updateItem = NSMenuItem()
        updateItem.target = self
        switch updater.currentState {
        case .upToDate:
            updateItem.title = "Up to Date (v\(updater.currentVersion))"
            updateItem.action = #selector(checkUpdatesManually)
        case .downloading:
            updateItem.title = "Downloading Update..."
            updateItem.action = nil
        case .updateReady(_):
            updateItem.title = "Update Now!"
            updateItem.action = #selector(performUpdate)
        }
        menu.addItem(updateItem)
        menu.addItem(NSMenuItem.separator())
        
        // Launch on Startup
        let autorunItem = NSMenuItem(title: "Launch on Startup", action: #selector(toggleAutorun), keyEquivalent: "")
        autorunItem.target = self
        if #available(macOS 13.0, *) {
            autorunItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        menu.addItem(autorunItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Donate
        let donateItem = NSMenuItem(title: "Donate", action: #selector(openDonate), keyEquivalent: "")
        donateItem.target = self
        menu.addItem(donateItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit WFHTimer", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        if let button = statusItem.button {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        }
    }
    
    @objc func toggleMode() {
        mode = (mode == .stopwatch) ? .pomodoro : .stopwatch
        reset()
    }
    
    @objc func openPreferences() {
        let alert = NSAlert()
        alert.messageText = "Pomodoro Preferences"
        alert.informativeText = "Set your Work and Break durations (in minutes):"
        
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 60))
        
        let workLabel = NSTextField(labelWithString: "Work:")
        workLabel.frame = NSRect(x: 0, y: 35, width: 60, height: 20)
        view.addSubview(workLabel)
        
        let workInput = NSTextField(frame: NSRect(x: 60, y: 35, width: 140, height: 20))
        workInput.stringValue = String(UserDefaults.standard.integer(forKey: "workDuration"))
        view.addSubview(workInput)
        
        let breakLabel = NSTextField(labelWithString: "Break:")
        breakLabel.frame = NSRect(x: 0, y: 5, width: 60, height: 20)
        view.addSubview(breakLabel)
        
        let breakInput = NSTextField(frame: NSRect(x: 60, y: 5, width: 140, height: 20))
        breakInput.stringValue = String(UserDefaults.standard.integer(forKey: "breakDuration"))
        view.addSubview(breakInput)
        
        alert.accessoryView = view
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        // Bring to front
        NSApp.activate(ignoringOtherApps: true)
        
        if alert.runModal() == .alertFirstButtonReturn {
            if let w = Int(workInput.stringValue), w > 0 { UserDefaults.standard.set(w, forKey: "workDuration") }
            if let b = Int(breakInput.stringValue), b > 0 { UserDefaults.standard.set(b, forKey: "breakDuration") }
            if mode == .pomodoro && !isRunning {
                reset() // refresh immediately
            }
        }
    }
    
    @objc func checkUpdatesManually() {
        updater.checkForUpdates()
    }
    
    @objc func performUpdate() {
        if isRunning || (mode == .stopwatch ? accumulatedTime > 0 : pomodoroRemainingSeconds < TimeInterval(UserDefaults.standard.integer(forKey: "workDuration") * 60)) {
            let alert = NSAlert()
            alert.messageText = "Cannot Update"
            alert.informativeText = "Please reset the timer before applying an update to prevent losing your tracked time."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        
        if case .updateReady(let url) = updater.currentState {
            updater.applyUpdate(dmgURL: url)
        }
    }
    
    @objc func toggleAutorun() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                print("Failed to toggle autorun: \(error)")
            }
        }
    }
    
    @objc func openDonate() {
        if let url = URL(string: "https://ko-fi.com/auxetics") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
