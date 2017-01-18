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
        self.tests = tests
        self.retryCount = retryCount
        self.launchRetryCount = launchRetryCount
        var logPrefix = "\(AppArgs.shared.logsDir)/\(deviceID)"
        
        if tests.count == 1 {
            logPrefix += "-" + tests[0].replacingOccurrences(of: "/", with: "-")
        }
        self.logFilePath = String(format: "%@-%d.json", logPrefix, retryCount + 1)
        
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
        }

        let logMessage = String(format: "Running Tests:\n\t%@\n\n", tests.joined(separator: "\n\t"))
        TRLog(logMessage, simulatorName: simulatorName)
        
        let task = XctoolTask(actions: ["run-tests"], deviceID: deviceID, tests: tests, logFilePath: logFilePath)
        task.delegate = self
        task.launch()
        task.waitUntilExit()
        
        let status: TestRunnerStatus = task.terminationStatus == 0 ? .success : .failed

        finishOperation(status: status)
    }
    
    func finishOperation(status: TestRunnerStatus) {
        simulatorDidLaunch()
        
        let results = JSON.testResults(logPath: self.logFilePath)

        Summary.outputSummary(logFile: logFilePath, simulatorName: simulatorName)
        
        let passedTests = results.filter { $0.passed }.map { $0.testName }
        let failedTests = tests.filter { !passedTests.contains($0) }
        let status: TestRunnerStatus = failedTests.isEmpty ? .success : .failed
        completion?(status, simulatorName, failedTests, deviceID, retryCount, launchRetryCount)
        
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
            if JSON.hasBeginTestSuiteEvent(logPath: self.logFilePath) {
                self.simulatorDidLaunch()
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: (.now() + DispatchTimeInterval.seconds(AppArgs.shared.launchTimeout))) {
            guard !self.simulatorLaunched else { return }
                
            TRLog("TIMED OUT Launching Simulator", simulatorName: self.simulatorName)
            self.finishOperation(status: .launchTimeout)
            return
        }
    }
    
}

extension TestRunnerOperation: XctoolTaskDelegate {

    func outputDataReceived(_ task: XctoolTask, data: Data) {
        guard data.count > 0 else { return }

        TRLog(data, simulatorName: simulatorName)

        let counter = timeoutCounter
        
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + AppArgs.shared.timeout) {
            guard counter < self.timeoutCounter else {
                self.finishOperation(status: .testTimeout)
                return
            }
        }
        timeoutCounter += 1
        
        notifyIfLaunched(data)
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
