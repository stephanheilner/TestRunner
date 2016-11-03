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
    case success
    case failed
}

class TestRunnerOperation: Operation {
    
    fileprivate static let TestCaseStartedRegex = try! NSRegularExpression(pattern: "Test Case '(.*)' started.", options: [])
    fileprivate static let TestCasePassedRegex = try! NSRegularExpression(pattern: "Test Case '(.*)' passed (.*)", options: [])
    fileprivate static let TestSuiteStartedRegex = try! NSRegularExpression(pattern: "Test Suite '(.*).xctest' started", options: [])
    
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
        self.logFilePath = String(format: "%@/%@-%d.log", AppArgs.shared.logsDir, deviceID, retryCount + 1)
        
        _executing = false
        _finished = false
        
        super.init()
    }
    
    override func start() {
        super.start()
        
        isExecuting = true
        self.status = .running

        let logMessage = String(format: "Running the following tests:\n\t%@\n\n", tests.joined(separator: "\n\t"))
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
    
    func finishOperation(status: TestRunnerStatus) {
        simulatorDidLaunch()
        
        var status = status
        
        let failedTests = getFailedTests()
        if !failedTests.isEmpty {
            status = .failed
        }
        completion?(status, simulatorName, failedTests, deviceID, retryCount, launchRetryCount)
        
        isExecuting = false
        isFinished = true
    }
    
    func simulatorDidLaunch() {
        guard !simulatorLaunched else { return }
        
        simulatorLaunched = true
        
        NotificationCenter.default.post(name: Notification.Name(rawValue: TestRunnerOperationQueue.SimulatorLoadedNotification), object: nil)
    }
    
    func getFailedTests() -> [String] {
        var tests = [String]()

        do {
            let log = try String(contentsOfFile: logFilePath, encoding: String.Encoding.utf8)
            let range = NSRange(location: 0, length: log.length)
            
            var failedTests = Set<String>()
            
            for match in TestRunnerOperation.TestCaseStartedRegex.matches(in: log, options: [], range: range) {
                let nameRange = match.rangeAt(1)
                guard let range = nameRange.range(from: log) else { continue }
                let testCase = log.substring(with: range)
                failedTests.insert(testCase)
            }
            
            for match in TestRunnerOperation.TestCasePassedRegex.matches(in: log, options: [], range: range) {
                let nameRange = match.rangeAt(1)
                guard let range = nameRange.range(from: log) else { continue }
                let testCase = log.substring(with: range)
                failedTests.remove(testCase)
            }
            
            if let match = TestRunnerOperation.TestSuiteStartedRegex.matches(in: log, options: [], range: range).first {
                let nameRange = match.rangeAt(1)
                let testSuiteName = nameRange.range(from: log)
                
                for testCase in failedTests {
                    var testName: String?
                    var testClass: String?
                    
                    if let testNameRange = testCase.range(of: " ", options: .backwards, range: nil, locale: nil) {
                        testName = testCase.substring(with: testNameRange.upperBound..<testCase.characters.index(testCase.endIndex, offsetBy: -1))
                        testClass = testCase.substring(with: testCase.characters.index(testCase.startIndex, offsetBy: 2)..<testNameRange.lowerBound)
                    }
                    
                    if let testTargetRange = testClass?.range(of: ".", options: .literal, range: nil, locale: nil) {
                        testClass = testClass?.substring(from: testTargetRange.upperBound)
                    }
                    
                    if let testName = testName, let testClass = testClass {
                        tests.append("\(testSuiteName)/\(testClass)/\(testName)")
                    }
                }
            }
        } catch {}
        
        return tests
    }

    func notifyIfLaunched(_ data: Data) {
        guard !simulatorLaunched else { return }
        
        let now = Date().timeIntervalSince1970
        guard (lastCheck + 2) < now else { return }
        lastCheck = now
        
        DispatchQueue.global(qos: .background).async {
            do {
                let log = try String(contentsOfFile: self.logFilePath, encoding: String.Encoding.utf8)
                if TestRunnerOperation.TestSuiteStartedRegex.numberOfMatches(in: log, options: [], range: NSRange(location: 0, length: log.length)) > 0 {
                    self.simulatorDidLaunch()
                }
            } catch {}
        }
    }
    
}

extension TestRunnerOperation: XcodebuildTaskDelegate {

    func outputDataReceived(_ task: XcodebuildTask, data: Data) {
        guard data.count > 0 else { return }

        TRLog(data, simulatorName: simulatorName)

        let counter = timeoutCounter
        
        let timeoutTime = DispatchTime.now() + Double(Int64(AppArgs.shared.timeout * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
        DispatchQueue.global(qos: .background).asyncAfter(deadline: timeoutTime) {
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
