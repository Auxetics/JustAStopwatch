import Cocoa
import ServiceManagement

enum UpdateState {
    case upToDate
    case downloading
    case updateReady(dmgURL: URL)
}

class AutoUpdater: NSObject {
    var currentState: UpdateState = .upToDate
    let currentVersion = "1.0"
    
    func checkForUpdates() {
        let url = URL(string: "https://api.github.com/repos/Auxetics/JustAStopwatch/releases/latest")!
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let tagName = json["tag_name"] as? String,
                   let assets = json["assets"] as? [[String: Any]] {
                    
                    let version = tagName.replacingOccurrences(of: "v", with: "")
                    if version.compare(self.currentVersion, options: .numeric) == .orderedDescending {
                        // Found newer version!
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
            let destinationURL = tempDir.appendingPathComponent("JustAStopwatch_Update.dmg")
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
        sleep 2
        hdiutil attach "\(dmgURL.path)" -nobrowse -mountpoint /Volumes/JustAStopwatchUpdate
        rm -rf "/Applications/JustAStopwatch.app"
        cp -R "/Volumes/JustAStopwatchUpdate/JustAStopwatch.app" "/Applications/"
        hdiutil detach /Volumes/JustAStopwatchUpdate -force
        open "/Applications/JustAStopwatch.app"
        """
        
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("update_stopwatch.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptURL.path]
            try process.run()
            
            NSApp.terminate(nil)
        } catch {
            print("Failed to run update script: \(error)")
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    
    var timer: Timer?
    var startTime: Date?
    var accumulatedTime: TimeInterval = 0
    var isRunning = false
    
    var lastClickTime: Date?
    let updater = AutoUpdater()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            let fontSize = NSFont.systemFontSize
            button.font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
            
            button.title = "00:00"
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        
        updater.checkForUpdates()
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
            accumulatedTime += Date().timeIntervalSince(start)
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
        updateTime()
    }
    
    @objc func updateTime() {
        var elapsed = accumulatedTime
        if let start = startTime {
            elapsed += Date().timeIntervalSince(start)
        }
        
        let totalSeconds = Int(elapsed)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        let timeString: String
        if hours >= 1 {
            timeString = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            timeString = String(format: "%02d:%02d", minutes, seconds)
        }
        
        if let button = statusItem.button {
            button.title = timeString
        }
    }
    
    func showMenu(event: NSEvent) {
        let menu = NSMenu()
        
        // Auto-Updater
        let updateItem = NSMenuItem()
        updateItem.target = self
        switch updater.currentState {
        case .upToDate:
            updateItem.title = "Up to Date (v1.0)"
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
        let quitItem = NSMenuItem(title: "Quit JustAStopwatch", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        if let button = statusItem.button {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        }
    }
    
    @objc func checkUpdatesManually() {
        updater.checkForUpdates()
    }
    
    @objc func performUpdate() {
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
