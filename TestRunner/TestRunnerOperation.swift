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
    case Success
    case Failed
}

class TestRunnerOperation: NSOperation {
    
    private static let TestCaseStartedRegex = try! NSRegularExpression(pattern: "Test Case '(.*)' started.", options: [])
    private static let TestCasePassedRegex = try! NSRegularExpression(pattern: "Test Case '(.*)' passed (.*)", options: [])
    private static let TestSuiteStartedRegex = try! NSRegularExpression(pattern: "Test Suite '(.*).xctest' started", options: [])
    
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
    private let logFilePath: String
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
        self.logFilePath = String(format: "%@/%@-%d.log", AppArgs.shared.logsDir, deviceID, retryCount + 1)
        
        _executing = false
        _finished = false
        
        super.init()
    }
    
    override func start() {
        super.start()
        
        executing = true
        self.status = .Running

        let logMessage = String(format: "Running the following tests:\n\t%@\n\n", tests.joinWithSeparator("\n\t"))
        if let logData = logMessage.dataUsingEncoding(NSUTF8StringEncoding) {
            TRLog(logData, simulatorName: simulatorName)
        }
        
        let task = XcodebuildTask(actions: ["test-without-building"], deviceID: deviceID, tests: tests, logFilePath: logFilePath)
        
        task.delegate = self
        task.launch()
        task.waitUntilExit()
        
        let status: TestRunnerStatus = task.terminationStatus == 0 ? .Success : .Failed

        finishOperation(status: status)
    }
    
    func finishOperation(status status: TestRunnerStatus) {
        simulatorDidLaunch()
        
        var status = status
        
        let failedTests = getFailedTests()
        if !failedTests.isEmpty {
            status = .Failed
        }
        completion?(status: status, simulatorName: simulatorName, failedTests: failedTests, deviceID: deviceID, retryCount: retryCount, launchRetryCount: launchRetryCount)
        
        executing = false
        finished = true
    }
    
    func simulatorDidLaunch() {
        guard !simulatorLaunched else { return }
        
        simulatorLaunched = true
        
        NSNotificationCenter.defaultCenter().postNotificationName(TestRunnerOperationQueue.SimulatorLoadedNotification, object: nil)
    }
    
    func getFailedTests() -> [String] {
        var tests = [String]()

        do {
            let log = try String(contentsOfFile: logFilePath, encoding: NSUTF8StringEncoding)
            let range = NSRange(location: 0, length: log.length)
            
            var failedTests = Set<String>()
            
            for match in TestRunnerOperation.TestCaseStartedRegex.matchesInString(log, options: [], range: range) {
                let nameRange = match.rangeAtIndex(1)
                let startIndex = log.startIndex.advancedBy(nameRange.location)
                let testCase = log.substringWithRange(startIndex..<startIndex.advancedBy(nameRange.length))
                failedTests.insert(testCase)
            }
            
            for match in TestRunnerOperation.TestCasePassedRegex.matchesInString(log, options: [], range: range) {
                let nameRange = match.rangeAtIndex(1)
                let startIndex = log.startIndex.advancedBy(nameRange.location)
                let testCase = log.substringWithRange(startIndex..<startIndex.advancedBy(nameRange.length))
                failedTests.remove(testCase)
            }
            
            if let match = TestRunnerOperation.TestSuiteStartedRegex.matchesInString(log, options: [], range: range).first {
                let nameRange = match.rangeAtIndex(1)
                let startIndex = log.startIndex.advancedBy(nameRange.location)
                let testSuiteName = log.substringWithRange(startIndex..<startIndex.advancedBy(nameRange.length))
                
                for testCase in failedTests {
                    var testName: String?
                    var testClass: String?
                    
                    if let testNameRange = testCase.rangeOfString(" ", options: .BackwardsSearch, range: nil, locale: nil) {
                        testName = testCase.substringWithRange(testNameRange.endIndex..<testCase.endIndex.advancedBy(-1))
                        testClass = testCase.substringWithRange(testCase.startIndex.advancedBy(2)..<testNameRange.startIndex)
                    }
                    
                    if let testTargetRange = testClass?.rangeOfString(".", options: .LiteralSearch, range: nil, locale: nil) {
                        testClass = testClass?.substringFromIndex(testTargetRange.endIndex)
                    }
                    
                    if let testName = testName, testClass = testClass {
                        tests.append("\(testSuiteName)/\(testClass)/\(testName)")
                    }
                }
            }
        } catch {}
        
        return tests
    }

    func notifyIfLaunched(data: NSData) {
        guard !simulatorLaunched else { return }
        
        let now = NSDate().timeIntervalSince1970
        guard (lastCheck + 2) < now else { return }
        lastCheck = now
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            do {
                let log = try String(contentsOfFile: self.logFilePath, encoding: NSUTF8StringEncoding)
                if TestRunnerOperation.TestSuiteStartedRegex.numberOfMatchesInString(log, options: [], range: NSRange(location: 0, length: log.length)) > 0 {
                    self.simulatorDidLaunch()
                }
            } catch {}
        }
    }
    
}

extension TestRunnerOperation: XcodebuildTaskDelegate {

    func outputDataReceived(task: XcodebuildTask, data: NSData) {
        guard data.length > 0 else { return }

        TRLog(data, simulatorName: simulatorName)

        let counter = timeoutCounter
        
        let timeoutTime = dispatch_time(DISPATCH_TIME_NOW, Int64(AppArgs.shared.timeout * Double(NSEC_PER_SEC)))
        dispatch_after(timeoutTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            guard counter < self.timeoutCounter else {
                self.finishOperation(status: .TestTimeout)
                return
            }
        }
        timeoutCounter += 1
        
        notifyIfLaunched(data)
    }
    
}
