//
//  Summary.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/22/16.
//  Copyright © 2016 Stephan Heilner
//

import Foundation

class Summary {
    
    static let TestCaseStartedRegex = try! NSRegularExpression(pattern: "Test Case '(.*)' started.", options: [])
    static let TestCasePassedRegex = try! NSRegularExpression(pattern: "Test Case '(.*)' passed (.*)", options: [])
    static let TestSuiteStartedRegex = try! NSRegularExpression(pattern: "Test Suite '(.*).xctest' started", options: [])
    
    class func outputSummary(logFile: String? = nil) {
        let logDirectoryURL = URL(fileURLWithPath: AppArgs.shared.logsDir)
        
        print("\n============================ SUMMARY ============================")
        
        var failedTests = Set<String>()
        var succeededTests = Set<String>()
        
        do {
            for fileURL in try FileManager.default.contentsOfDirectory(at: logDirectoryURL, includingPropertiesForKeys: nil, options: FileManager.DirectoryEnumerationOptions.skipsHiddenFiles) {
                if let logFile = logFile, logFile != fileURL.path {
                    continue
                }
                
                guard let testResults = getTestResults(logFile: fileURL.path) else { continue }
                
                succeededTests.formUnion(testResults.succeeded)
                failedTests.formUnion(testResults.failed)
            }
        } catch {
            print(error)
        }

        // If a test eventually succeeded, remove it from list of failed tests
        failedTests.subtract(succeededTests)

        if !succeededTests.isEmpty {
            print("\n---------- Passed Tests ----------")
            for test in Array(succeededTests).sorted() {
                print(test)
            }
        }

        if !failedTests.isEmpty {
            print("\n---------- Failed Tests ----------")
            for test in Array(failedTests).sorted() {
                print(test)
            }
        }
        
        print("\n=================================================================\n")
    }

    class func getTestResults(logFile: String) -> (succeeded: [String], failed: [String])? {
        var succeededTests = Set<String>()
        var failedTests = Set<String>()
        
        do {
            let log = try String(contentsOfFile: logFile, encoding: String.Encoding.utf8)
            let range = NSRange(location: 0, length: log.length)
            
            for match in Summary.TestCaseStartedRegex.matches(in: log, options: [], range: range) {
                let nameRange = match.rangeAt(1)
                guard let range = nameRange.range(from: log) else { continue }
                let testCase = log.substring(with: range)
                failedTests.insert(testCase)
            }
            
            for match in Summary.TestCasePassedRegex.matches(in: log, options: [], range: range) {
                let nameRange = match.rangeAt(1)
                guard let range = nameRange.range(from: log) else { continue }
                let testCase = log.substring(with: range)
                failedTests.remove(testCase)
                succeededTests.insert(testCase)
            }
            
            guard let match = Summary.TestSuiteStartedRegex.matches(in: log, options: [], range: range).first else { return nil }
            
            let nameRange = match.rangeAt(1)
            
            guard let testSuiteRange = nameRange.range(from: log) else { return nil }
            
            let testSuite = log.substring(with: testSuiteRange)
            let failed = failedTests.flatMap { formattedTestName(testCase: $0, testSuite: testSuite) }
            let succeeded = succeededTests.flatMap { formattedTestName(testCase: $0, testSuite: testSuite) }
            return (succeeded: succeeded, failed: failed)
        } catch {}
        
        return nil
    }
    
    class func formattedTestName(testCase: String, testSuite: String) -> String? {
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
            return "\(testSuite)/\(testClass)/\(testName)"
        }
        
        return nil
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

class TestSummary {
    
    let simulatorName: String
    let testName: String
    let passed: Bool
    let duration: TimeInterval
    let exceptions: [[String: AnyObject]]?
    
    init(simulatorName: String, testName: String, passed: Bool, duration: TimeInterval, exceptions: [[String: AnyObject]]?) {
        self.simulatorName = simulatorName
        self.testName = testName
        self.passed = passed
        self.duration = duration
        self.exceptions = exceptions
    }
    
    
}
