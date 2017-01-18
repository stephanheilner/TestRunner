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
    fileprivate var numberOfLogsReceived = 0
    
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
        
        if task.terminationStatus != 0 {
            TRLog("****************=============== TASK TERMINATED ABNORMALLY WITH STATUS \(task.terminationStatus) ===============****************", simulatorName: simulatorName)
            if case task.terminationReason = Process.TerminationReason.uncaughtSignal {
                TRLog("****************=============== TASK TERMINATED DUE TO UNCAUGHT EXCEPTION ===============****************", simulatorName: simulatorName)
            }
        }

        finishOperation()
    }
    
    func finishOperation() {
        simulatorDidLaunch()
        
        let results = JSON.testResults(logPath: logFilePath)

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
            self.finishOperation()
            return
        }
    }
    
}

extension TestRunnerOperation: XctoolTaskDelegate {

    func outputDataReceived(data: Data, isError: Bool) {
        guard data.count > 0 else { return }
        
        if isError {
            TRLog("Error logs incoming!", simulatorName: simulatorName)
        }
        
        TRLog(data, simulatorName: simulatorName)
        
        numberOfLogsReceived += 1
        let currentLogCount = numberOfLogsReceived
        notifyIfLaunched(data)
        
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + AppArgs.shared.timeout) { [weak self] in
            guard let strongSelf = self, !strongSelf.isFinished, currentLogCount < strongSelf.numberOfLogsReceived else {
                TRLog("****************=============== No logs received for \(AppArgs.shared.timeout) seconds, failing ===============****************", simulatorName: self?.simulatorName)
                self?.finishOperation()
                return
            }
        }
    }
    
}
