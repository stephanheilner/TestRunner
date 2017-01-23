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
    case terminatedAbnormally
    case success
    case failed
}

class TestRunnerOperation: Operation {
    
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
    
    fileprivate let simulator: Simulator
    fileprivate let retryCount: Int
    fileprivate let launchRetryCount: Int
    fileprivate let logFilePath: String
    fileprivate var status: TestRunnerStatus = .stopped
    fileprivate var lastCheck = Date().timeIntervalSince1970
    fileprivate var numberOfLogsReceived = 0
    
    var simulatorLaunched = false
    var completion: ((_ status: TestRunnerStatus, _ simulator: Simulator, _ failedTests: [String], _ retryCount: Int, _ launchRetryCount: Int) -> Void)?
    
    init(simulator: Simulator, tests: [String], retryCount: Int, launchRetryCount: Int) {
        self.simulator = simulator
        self.tests = tests
        self.retryCount = retryCount
        self.launchRetryCount = launchRetryCount
        var logPrefix = "\(AppArgs.shared.logsDir)/\(simulator.deviceID)"
        
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
//        DeviceController.sharedController.reuseDevice(simulator: simulator)
//        if retryCount == 0 {
//            DeviceController.sharedController.installAppsOnDevice(simulator: simulator)
//        }

        let logMessage = String(format: "\nRunning Tests:\n\t%@\n\n", tests.joined(separator: "\n\t"))
        TRLog(logMessage, simulator: simulator)
        
        let task = BluepillTask(simulator: simulator, tests: tests, logFilePath: logFilePath)
        task.delegate = self
        task.launch()
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            TRLog("****************=============== TASK TERMINATED ABNORMALLY WITH STATUS \(task.terminationStatus) ===============****************", simulator: simulator)
            if case task.terminationReason = Process.TerminationReason.uncaughtSignal {
                TRLog("****************=============== TASK TERMINATED DUE TO UNCAUGHT EXCEPTION ===============****************", simulator: simulator)
            }
            finishOperation(status: .terminatedAbnormally)
        } else {
            finishOperation()
        }
    }
    
    func finishOperation(status: TestRunnerStatus? = nil) {
        simulatorDidLaunch()
        
        let results = JSON.testResults(logPath: logFilePath)

        let passedTests = results.filter { $0.passed }.map { $0.testName }
        let failedTests = tests.filter { !passedTests.contains($0) }

        var status = status
        if status == nil {
            Summary.outputSummary(logFile: logFilePath, simulator: simulator)
            status = failedTests.isEmpty ? .success : .failed
        }
        
        completion?(status ?? .success, simulator, failedTests, retryCount, launchRetryCount)
        
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + AppArgs.shared.launchTimeout) { [weak self] in
            guard self?.simulatorLaunched == false else { return }
                
            TRLog("TIMED OUT Launching Simulator", simulator: self?.simulator)
            self?.finishOperation(status: .launchTimeout)
            return
        }
    }
    
}

extension TestRunnerOperation: BluepillTaskDelegate {

    func outputDataReceived(data: Data, isError: Bool) {
        guard data.count > 0 else { return }
        
        if isError {
            TRLog("Error logs incoming!", simulator: simulator)
        }
        
        TRLog(data, simulator: simulator)
        
        numberOfLogsReceived += 1
        let currentLogCount = numberOfLogsReceived
        notifyIfLaunched(data)
        
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + AppArgs.shared.timeout) { [weak self] in
            guard self?.isFinished == false else { return }
            
            if currentLogCount >= self?.numberOfLogsReceived ?? 0 {
                TRLog("**************************************************************************\n=============== No logs received for \(AppArgs.shared.timeout) seconds, failing ===============\n**************************************************************************", simulator: self?.simulator)
                self?.finishOperation(status: .testTimeout)
            }
        }
    }
    
}
