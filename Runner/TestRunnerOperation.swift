//
//  TestRunnerOperation.swift
//  TestRunner
//
//  Created by Stephan Heilner on 1/5/16.
//  Copyright © 2016 The Church of Jesus Christ of Latter-day Saints. All rights reserved.
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
    private let retryCount: Int
    private var logFilePath: String?
    private var status: TestRunnerStatus = .Stopped
    private var lastCheck = NSDate().timeIntervalSince1970
    private var timeoutCounter = 0
    
    var loaded = false
    var completion: ((status: TestRunnerStatus, simulatorName: String, failedTests: [String], deviceID: String, retryCount: Int) -> Void)?
    
    init(deviceFamily: String, simulatorName: String, deviceID: String, tests: [String], retryCount: Int) {
        self.deviceFamily = deviceFamily
        self.simulatorName = simulatorName
        self.deviceID = deviceID
        self.tests = tests
        self.retryCount = retryCount
        
        _executing = false
        _finished = false
        
        super.init()
    }
    
    override func start() {
        super.start()
        
        executing = true
        status = .Running

        let onlyTests: String = "\(AppArgs.shared.target):" + tests.joinWithSeparator(",")
        let arguments = ["-destination", "id=\(deviceID)", "run-tests", "-newSimulatorInstance", "-only", onlyTests]

        let logFilename: String
        if retryCount > 0 {
            logFilename = String(format: "%@ (%d).json", simulatorName, retryCount+1)
        } else {
            logFilename = String(format: "%@.json", simulatorName)
        }
        
        let logMessage = String(format: "Running the following tests:\n\t%@", tests.joinWithSeparator("\n\t"))
        if let logData = logMessage.dataUsingEncoding(NSUTF8StringEncoding) {
            TRLog(logData, simulatorName: simulatorName)
        }
        
        let task = XCToolTask(arguments: arguments, logFilename: logFilename, outputFileLogType: .JSON, standardOutputLogType: .Text)
        logFilePath = task.logFilePath
        task.delegate = self
        task.launch()
        task.waitUntilExit()
        
        status = (task.terminationStatus == 0) ? .Success : .Failed
        completion?(status: status, simulatorName: simulatorName, failedTests: getFailedTests(), deviceID: deviceID, retryCount: retryCount)

        executing = false
        finished = true
    }
    
    func getFailedTests() -> [String] {
        guard let logFilePath = logFilePath, jsonObjects = JSONObject.jsonObjectFromJSONStreamFile(logFilePath) else { return [] }

        let succeededTests = Set<String>(jsonObjects.flatMap { jsonObject -> String? in
            guard let succeeded = jsonObject["succeeded"] as? Bool where succeeded, let className = jsonObject["className"] as? String, methodName = jsonObject["methodName"] as? String else { return nil }
            return String(format: "%@/%@", className, methodName)
        })
        return tests.filter { !succeededTests.contains($0) }
    }

    func notifyIfLaunched(task: XCToolTask) {
        guard !loaded else { return }
        
        let now = NSDate().timeIntervalSince1970
        guard (lastCheck + 2) < now else { return }
        lastCheck = now
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            if let logFilePath = task.logFilePath, jsonObjects = JSONObject.jsonObjectFromJSONStreamFile(logFilePath) {
                for jsonObject in jsonObjects {
                    if let event = jsonObject["event"] as? String where event == "begin-test-suite" {
                        self.loaded = true
                        NSNotificationCenter.defaultCenter().postNotificationName(TestRunnerOperationQueue.SimulatorLoadedNotification, object: nil)
                        return
                    }
                }
            }
        }
    }
    
}

extension TestRunnerOperation: XCToolTaskDelegate {

    func outputDataReceived(task: XCToolTask, data: NSData) {
        guard data.length > 0 else { return }

        let counter = timeoutCounter + 1
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
