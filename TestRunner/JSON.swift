//
//  JSON.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/15/16.
//  Copyright © 2016 Stephan Heilner
//

import Foundation

class JSON {
    
    class func hasBeginTestSuiteEvent(logPath: String) -> Bool {
        do {
            let jsonFileContents = try String(contentsOfFile: logPath, encoding: .utf8)
            let jsonStrings = jsonFileContents.components(separatedBy: .newlines)
            for jsonString in jsonStrings {
                if let jsonData = jsonString.data(using: .utf8), let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: AnyObject] {
                    guard let event = jsonObject["event"] as? String, event == "begin-test-suite" else { continue }
                    
                    return true
                }
            }
        } catch {}
        return false
    }
    
    class func testResults(logPath: String) -> [TestResult] {
        var testResults = [TestResult]()
        
        do {
            let jsonFileContents = try String(contentsOfFile: logPath, encoding: .utf8)
            let jsonStrings = jsonFileContents.components(separatedBy: .newlines)
            for jsonString in jsonStrings {
                if let jsonData = jsonString.data(using: .utf8), let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                    guard jsonObject["result"] != nil, let succeeded = jsonObject["succeeded"] as? Bool, let className = jsonObject["className"] as? String, let methodName = jsonObject["methodName"] as? String, let duration = jsonObject["totalDuration"] as? TimeInterval else { continue }
                    
                    let testResult = TestResult(testName: "\(className)/\(methodName)", passed: succeeded, duration: duration)
                    testResults.append(testResult)
                }
            }
        } catch {}
        
        return testResults
    }
    
}

class SuiteSummary {
    
    var testCaseCount: Int
    var duration: TimeInterval
    var failureCount: Int
    
    init(testCaseCount: Int, duration: TimeInterval, failureCount: Int) {
        self.testCaseCount = testCaseCount
        self.duration = duration
        self.failureCount = failureCount
    }
}

class TestResult {
    
    let testName: String
    let passed: Bool
    let duration: TimeInterval
    
    init(testName: String, passed: Bool, duration: TimeInterval) {
        self.testName = testName
        self.passed = passed
        self.duration = duration
    }
    
    
}

