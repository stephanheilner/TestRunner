//
//  TestRunnerOperation.swift
//  TestRunner
//
//  Created by Stephan Heilner on 1/5/16.
//  Copyright © 2016 Stephan Heilner
//

import Foundation

enum TestRunnerStatus: Int {
    case stopped
    case running
    case testTimeout
    case launchTimeout
    case success
    case failed
}

class TestRunnerOperation: Operation {
    
    fileprivate let deviceFamily: String
    fileprivate let deviceID: String
    fileprivate let tests: [String]
    
    override var isExecuting: Bool {
        get {
            return _executing
        }
        set {
            willChangeValue(forKey: "isExecuting")
            _executing = newValue
            didChangeValue(forKey: "isExecuting")
        }
    }
    fileprivate var _executing: Bool
    
    override var isFinished: Bool {
        get {
            return _finished
        }
        set {
            willChangeValue(forKey: "isFinished")
            _finished = newValue
            didChangeValue(forKey: "isFinished")
        }
    }
    fileprivate var _finished: Bool
    
    fileprivate let simulatorName: String
    fileprivate let retryCount: Int
    fileprivate let launchRetryCount: Int
    fileprivate let logFilePath: String
    fileprivate var status: TestRunnerStatus = .stopped
    fileprivate var lastCheck = Date().timeIntervalSince1970
    fileprivate var timeoutCounter = 0
    
    var simulatorLaunched = false
    var completion: ((_ status: TestRunnerStatus, _ simulatorName: String, _ failedTests: [String], _ deviceID: String, _ retryCount: Int, _ launchRetryCount: Int) -> Void)?
    
    init(deviceFamily: String, simulatorName: String, deviceID: String, tests: [String], retryCount: Int, launchRetryCount: Int) {
        self.deviceFamily = deviceFamily
        self.simulatorName = simulatorName
        self.deviceID = deviceID
        self.tests = tests.shuffled()
        self.retryCount = retryCount
        self.launchRetryCount = launchRetryCount
        var logPrefix = "\(AppArgs.shared.logsDir)/\(deviceID)"
        if tests.count == 1 {
            logPrefix += "-" + tests[0].replacingOccurrences(of: "/", with: "-")
        }
        self.logFilePath = String(format: "%@-%d.log", logPrefix, retryCount + 1)
        print("log file path:", logFilePath)
        
        _executing = false
        _finished = false
        
        super.init()
    }
    
    override func start() {
        super.start()

        isExecuting = true
        self.status = .running
        
        // Clear device for reuse
        DeviceController.sharedController.reuseDevice(simulatorName: simulatorName, deviceID: deviceID)
        if retryCount == 0 {
            DeviceController.sharedController.installAppsOnDevice(deviceID: deviceID)
        } else {
            DeviceController.sharedController.killallSimulators()
        }

        let logMessage = String(format: "Running Tests:\n\t%@\n\n", tests.joined(separator: "\n\t"))
        if let logData = logMessage.data(using: String.Encoding.utf8) {
            TRLog(logData, simulatorName: simulatorName)
        }
        
        let task = XcodebuildTask(actions: ["test-without-building"], deviceID: deviceID, tests: tests, logFilePath: logFilePath)
        
        task.delegate = self
        task.launch()
        task.waitUntilExit()
        
        let status: TestRunnerStatus = task.terminationStatus == 0 ? .success : .failed

        finishOperation(status: status)
    }
    
    func launchSimulator() {
        let task = Process()
        task.launchPath = "/bin/sh"
        let arguments = ["-c", "/usr/bin/open -n /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app --args -CurrentDeviceUDID \(deviceID)"]
        task.arguments = arguments
        
        print(arguments)
        
        let outputPipe = Pipe()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            TRLog(handle.availableData)
        }
        task.standardOutput = outputPipe
        
        let errorPipe = Pipe()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            TRLog(handle.availableData)
        }
        task.standardError = errorPipe
        task.launch()
        task.waitUntilExit()

    }
    
    func finishOperation(status: TestRunnerStatus) {
        simulatorDidLaunch()
        
        var status = status
        
        let succeededTests = Summary.getSucceededTests(logFile: logFilePath)
        if tests.count > succeededTests.count {
            status = .failed
        }
        
        Summary.outputSummary(logFile: logFilePath, attemptedTests: tests)
        
        completion?(status, simulatorName, tests.filter { !succeededTests.contains($0) }, deviceID, retryCount, launchRetryCount)
        
        isExecuting = false
        isFinished = true
    }
    
    func simulatorDidLaunch() {
        guard !simulatorLaunched else { return }
        
        simulatorLaunched = true
        
        NotificationCenter.default.post(name: Notification.Name(rawValue: TestRunnerOperationQueue.SimulatorLoadedNotification), object: nil)
    }
    
    func notifyIfLaunched(_ data: Data) {
        guard !simulatorLaunched else { return }
        
        let now = Date().timeIntervalSince1970
        guard (lastCheck + 2) < now else { return }
        lastCheck = now
        
        DispatchQueue.global(qos: .background).async {
            do {
                let log = try String(contentsOfFile: self.logFilePath, encoding: String.Encoding.utf8)
                if Summary.TestSuiteStartedRegex.numberOfMatches(in: log, options: [], range: NSRange(location: 0, length: log.length)) > 0 {
                    self.simulatorDidLaunch()
                }
            } catch {}
        }
        
        DispatchQueue.main.asyncAfter(deadline: (.now() + DispatchTimeInterval.seconds(AppArgs.shared.launchTimeout))) {
            guard !self.simulatorLaunched else { return }

            TRLog("TIMED OUT Launching Simulator", simulatorName: self.simulatorName)
            self.finishOperation(status: .launchTimeout)
            return
        }
    }
    
}

extension TestRunnerOperation: XcodebuildTaskDelegate {

    func outputDataReceived(_ task: XcodebuildTask, data: Data) {
        guard data.count > 0 else { return }

        TRLog(data, simulatorName: simulatorName)

        timeoutCounter += 1
        let counter = timeoutCounter
        notifyIfLaunched(data)
        
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + AppArgs.shared.timeout) { [weak self] in
            guard self?.isFinished == false else { return }
            
            if counter >= self?.timeoutCounter ?? 0 {
                TRLog("**************************************************************************\n=============== No logs received for \(AppArgs.shared.timeout) seconds, failing ===============\n**************************************************************************", simulatorName: self?.simulatorName)
                self?.finishOperation(status: .testTimeout)
            }
        }
    }
    
}

extension NSRange {
    
    func range(from string: String) -> Range<String.Index>? {
        guard let from16 = string.utf16.index(string.utf16.startIndex, offsetBy: location, limitedBy: string.utf16.endIndex),
            let to16 = string.utf16.index(from16, offsetBy: length, limitedBy: string.utf16.endIndex),
            let from = String.Index(from16, within: string),
            let to = String.Index(to16, within: string) else { return nil }
        
        return from ..< to
    }
    
}
