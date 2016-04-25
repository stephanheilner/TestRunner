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
    private var logFilePath: String?
    private var status: TestRunnerStatus = .Stopped
    private var lastCheck = NSDate().timeIntervalSince1970
    private var timeoutCounter = 0
    
    var loaded = false
    var completion: ((status: TestRunnerStatus, simulatorName: String, attemptedTests: [String], succeededTests: [String], deviceID: String) -> Void)?
    
    init(deviceFamily: String, simulatorName: String, deviceID: String, tests: [String], alreadyLoaded: Bool) {
        self.deviceFamily = deviceFamily
        self.simulatorName = simulatorName
        self.deviceID = deviceID
        self.tests = tests
        loaded = alreadyLoaded
        
        _executing = false
        _finished = false
        
        super.init()
    }
    
    override func start() {
        super.start()
        
        executing = true
        status = .Running

        var arguments = ["-destination", "id=\(deviceID)", "run-tests"]
        if !loaded {
            arguments.append("-newSimulatorInstance")
        }
        if let target = AppArgs.shared.target {
            let onlyTests: String = "\(target):" + tests.joinWithSeparator(",")
            arguments += ["-only", onlyTests]
        }

        let logFilename = String(format: "%@.json", simulatorName)
        
        TRLog(String(format: "Running the following tests:\n\t%@\n\n", tests.joinWithSeparator("\n\t")), simulatorName: simulatorName)
        
        let task = XCToolTask(arguments: arguments, logFilename: logFilename, outputFileLogType: .JSON, standardOutputLogType: .Text)
        logFilePath = task.logFilePath
        
        task.delegate = self
        task.launch()
        task.waitUntilExit()
        
        if !loaded {
            NSNotificationCenter.defaultCenter().postNotificationName(TestRunnerOperationQueue.SimulatorLoadedNotification, object: nil)
        }
        
        let succeededTests = getSucceededTests() ?? []
        status = (task.terminationStatus == 0 && succeededTests.sort() == tests.sort()) ? .Success : .Failed
        completion?(status: status, simulatorName: simulatorName, attemptedTests: tests, succeededTests: succeededTests, deviceID: deviceID)

        executing = false
        finished = true
    }
    
    func getSucceededTests() -> [String]? {
        guard let logFilePath = logFilePath, jsonObjects = JSON.jsonObjectsFromJSONStreamFile(logFilePath) else { return nil }

        let succeededTests = Set<String>(jsonObjects.flatMap { jsonObject -> String? in
            guard let succeeded = jsonObject["succeeded"] as? Bool where succeeded, let className = jsonObject["className"] as? String, methodName = jsonObject["methodName"] as? String else { return nil }
            return String(format: "%@/%@", className, methodName)
        })
        
        return Array(succeededTests)
    }

    func notifyIfLaunched(task: XCToolTask) {
        guard !loaded else { return }
        
        let now = NSDate().timeIntervalSince1970
        guard (lastCheck + 2) < now else { return }
        lastCheck = now
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            if let logFilePath = task.logFilePath where JSON.hasBeginTestSuiteEvent(logFilePath) {
                guard !self.loaded else { return }
                
                TRLog("TIMED OUT Running Tests", simulatorName: self.simulatorName)
                
                self.loaded = true
                NSNotificationCenter.defaultCenter().postNotificationName(TestRunnerOperationQueue.SimulatorLoadedNotification, object: nil)
                return
            }
        }
        
        let waitForLaunchTimeout = dispatch_time(DISPATCH_TIME_NOW, Int64(AppArgs.shared.launchTimeout * Double(NSEC_PER_SEC)))
        dispatch_after(waitForLaunchTimeout, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            guard !self.loaded else { return }
            
            TRLog("TIMED OUT Launching Simulator after \(Int64(AppArgs.shared.launchTimeout * Double(NSEC_PER_SEC))) seconds", simulatorName: self.simulatorName)
            
            // If not launched after 60 seconds, just mark as launched, something probably went wrong
            self.loaded = true
            NSNotificationCenter.defaultCenter().postNotificationName(TestRunnerOperationQueue.SimulatorLoadedNotification, object: nil)
            return
        }
    }
    
}

extension TestRunnerOperation: XCToolTaskDelegate {

    func outputDataReceived(task: XCToolTask, data: NSData) {
        guard data.length > 0 else { return }

        let counter = timeoutCounter + 2
        let timeoutTime = dispatch_time(DISPATCH_TIME_NOW, Int64(AppArgs.shared.timeout * Double(NSEC_PER_SEC)))
        dispatch_after(timeoutTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            if counter == self.timeoutCounter {
                task.terminate()
            }
        }
        timeoutCounter++
        
        TRLog(data, simulatorName: simulatorName)

        notifyIfLaunched(task)
    }
    
}
