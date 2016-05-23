//
//  TestRunnerOperation.swift
//  TestRunner
//
//  Created by Stephan Heilner on 1/5/16.
//  Copyright © 2016 Stephan Heilner
//

import Foundation

enum TestRunnerStatus: Int {
    case Stopped
    case Running
    case TestTimeout
    case LaunchTimeout
    case Success
    case Failed
}

class TestRunnerOperation: NSOperation {
    
    private let deviceFamily: String
    private let deviceID: String
    private let tests: [String]
    
    override var executing: Bool {
        get {
            return _executing
        }
        set {
            willChangeValueForKey("isExecuting")
            _executing = newValue
            didChangeValueForKey("isExecuting")
        }
    }
    private var _executing: Bool
    
    override var finished: Bool {
        get {
            return _finished
        }
        set {
            willChangeValueForKey("isFinished")
            _finished = newValue
            didChangeValueForKey("isFinished")
        }
    }
    private var _finished: Bool
    
    private let simulatorName: String
    private let retryCount: Int
    private let launchRetryCount: Int
    private var logFilePath: String?
    private var status: TestRunnerStatus = .Stopped
    private var lastCheck = NSDate().timeIntervalSince1970
    private var timeoutCounter = 0
    
    var simulatorLaunched = false
    var completion: ((status: TestRunnerStatus, simulatorName: String, failedTests: [String], deviceID: String, retryCount: Int, launchRetryCount: Int) -> Void)?
    
    init(deviceFamily: String, simulatorName: String, deviceID: String, tests: [String], retryCount: Int, launchRetryCount: Int) {
        self.deviceFamily = deviceFamily
        self.simulatorName = simulatorName
        self.deviceID = deviceID
        self.tests = tests
        self.retryCount = retryCount
        self.launchRetryCount = launchRetryCount
        
        _executing = false
        _finished = false
        
        super.init()
    }
    
    override func start() {
        super.start()
        
        executing = true
        self.status = .Running

        var arguments = ["-destination", "id=\(deviceID)", "run-tests", "-newSimulatorInstance"]
        if let target = AppArgs.shared.target {
            let onlyTests: String = "\(target):" + tests.joinWithSeparator(",")
            arguments += ["-only", onlyTests]
        }

        let logFilename: String
        if retryCount > 0 {
            logFilename = String(format: "%@ (%d).json", simulatorName, retryCount+1)
        } else {
            logFilename = String(format: "%@.json", simulatorName)
        }
        
        let logMessage = String(format: "Running the following tests:\n\t%@\n\n", tests.joinWithSeparator("\n\t"))
        if let logData = logMessage.dataUsingEncoding(NSUTF8StringEncoding) {
            TRLog(logData, simulatorName: simulatorName)
        }
        
        let task = XCToolTask(arguments: arguments, logFilename: logFilename, outputFileLogType: .JSON, standardOutputLogType: .Text)
        logFilePath = task.logFilePath
        
        task.delegate = self
        task.launch()
        task.waitUntilExit()
        
        let status: TestRunnerStatus = task.terminationStatus == 0 ? .Success : .Failed

        finishOperation(status: status)
    }
    
    func finishOperation(status status: TestRunnerStatus) {
        simulatorDidLaunch()
        
        completion?(status: status, simulatorName: simulatorName, failedTests: getFailedTests(), deviceID: deviceID, retryCount: retryCount, launchRetryCount: launchRetryCount)
        
        executing = false
        finished = true
    }
    
    func simulatorDidLaunch() {
        guard !simulatorLaunched else { return }
        
        simulatorLaunched = true
        
        NSNotificationCenter.defaultCenter().postNotificationName(TestRunnerOperationQueue.SimulatorLoadedNotification, object: nil)
    }
    
    func getFailedTests() -> [String] {
        guard let logFilePath = logFilePath, jsonObjects = JSON.jsonObjectsFromJSONStreamFile(logFilePath) else { return [] }

        let succeededTests = Set<String>(jsonObjects.flatMap { jsonObject -> String? in
            guard let succeeded = jsonObject["succeeded"] as? Bool where succeeded, let className = jsonObject["className"] as? String, methodName = jsonObject["methodName"] as? String else { return nil }
            return String(format: "%@/%@", className, methodName)
        })
        return tests.filter { !succeededTests.contains($0) }
    }

    func notifyIfLaunched(task: XCToolTask) {
        guard !simulatorLaunched else { return }
        
        let now = NSDate().timeIntervalSince1970
        guard (lastCheck + 2) < now else { return }
        lastCheck = now
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            if let logFilePath = task.logFilePath where JSON.hasBeginTestSuiteEvent(logFilePath) {
                self.simulatorDidLaunch()
                
                return
            }
        }
        
        let waitForLaunchTimeout = dispatch_time(DISPATCH_TIME_NOW, Int64(AppArgs.shared.launchTimeout * Double(NSEC_PER_SEC)))
        dispatch_after(waitForLaunchTimeout, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            guard !self.simulatorLaunched else { return }
            
            if let data = "TIMED OUT Launching Simulator".dataUsingEncoding(NSUTF8StringEncoding) {
                TRLog(data, simulatorName: self.simulatorName)
            }
            
            self.finishOperation(status: .LaunchTimeout)
            
            return
        }
    }
    
}

extension TestRunnerOperation: XCToolTaskDelegate {

    func outputDataReceived(task: XCToolTask, data: NSData) {
        guard data.length > 0 else { return }

        let counter = timeoutCounter
        
        let timeoutTime = dispatch_time(DISPATCH_TIME_NOW, Int64(AppArgs.shared.timeout * Double(NSEC_PER_SEC)))
        dispatch_after(timeoutTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            guard counter < self.timeoutCounter else {
                self.finishOperation(status: .TestTimeout)
                return
            }
        }
        
        timeoutCounter += 1
        
        TRLog(data, simulatorName: simulatorName)

        notifyIfLaunched(task)
    }
    
}
