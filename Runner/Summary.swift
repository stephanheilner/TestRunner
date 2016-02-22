//
//  Summary.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/22/16.
//  Copyright © 2016 Stephan Heilner
//

import Foundation
import Swiftification

class Summary {
    
    class func outputSummary(jsonOutput: Bool) {
        
        var simulatorRetries = [String: Int]()
        var testSummaries = [TestSummary]()
        var suiteSummaries = [SuiteSummary]()
        
        do {
            for filename in try NSFileManager.defaultManager().contentsOfDirectoryAtPath(AppArgs.shared.logsDir) {
                var simulatorName = filename
                
                if let range = filename.rangeOfString(" (") {
                    simulatorName = filename.substringWithRange(Range(start: filename.startIndex, end: range.startIndex))
                    simulatorRetries[simulatorName] = (simulatorRetries[simulatorName] ?? -1) + 1
                } else if let range = filename.rangeOfString(".json") {
                    simulatorName = filename.substringWithRange(Range(start: filename.startIndex, end: range.startIndex))
                    simulatorRetries[simulatorName] = (simulatorRetries[simulatorName] ?? -1) + 1
                }
                
                let jsonObjects = JSON.jsonObjectsFromJSONStreamFile(String(format: "%@/%@", AppArgs.shared.logsDir, filename)) ?? []

                testSummaries += jsonObjects.flatMap { jsonObject -> TestSummary? in
                    guard let event = jsonObject["event"] as? String where event == "end-test", let testName = jsonObject["test"] as? String, succeeded = jsonObject["succeeded"] as? Bool, duration = jsonObject["totalDuration"] as? NSTimeInterval else { return nil }
                    let exceptions = jsonObject["exceptions"] as? [[String: AnyObject]]
                    return TestSummary(simulatorName: simulatorName, testName: testName, passed: succeeded, duration: duration, exceptions: exceptions)
                }
                
                for jsonObject in jsonObjects {
                    if let event = jsonObject["event"] as? String where event == "end-test-suite", let testCaseCount = jsonObject["testCaseCount"] as? Int, duration = jsonObject["totalDuration"] as? NSTimeInterval, failureCount = jsonObject["totalFailureCount"] as? Int {
                        suiteSummaries.append(SuiteSummary(testCaseCount: testCaseCount, duration: duration, failureCount: failureCount))
                    }
                }

            }
        } catch {}

        let suiteSummary = suiteSummaries.reduce(SuiteSummary(testCaseCount: 0, duration: 0, failureCount: 0), combine: { totalSummary, suiteSummary in
            return SuiteSummary(testCaseCount: (suiteSummary.testCaseCount + totalSummary.testCaseCount), duration: (suiteSummary.duration + totalSummary.duration), failureCount: (suiteSummary.failureCount + totalSummary.failureCount))
        })
        
        if jsonOutput {
            // TODO: Output JSON
            
        } else {
            // Plain Text
            print("\n============================ SUMMARY ============================\n")
            for (simulatorName, retries) in simulatorRetries {
                print(String(format: "%d Retries: '%@'", retries, simulatorName))
            }

            print("")
            print(suiteSummary.testCaseCount, "Test Run in", suiteSummary.duration, "seconds.", suiteSummary.failureCount, "Failures")
            print("")

            // Number of each devices run
            // Number of retries on each
            
            testSummaries.sortInPlace { lhs, rhs -> Bool in
                if lhs.passed == rhs.passed {
                    return lhs.testName == rhs.testName
                } else {
                    return lhs.passed
                }
            }
            
            print("-------------------------------------------------------------------")
            for testSummary in testSummaries {
                if testSummary.passed {
                    print(testSummary.testName, "Passed", String(format: "(%@)", testSummary.simulatorName))
                } else {
                    print("-------------------------------------------------------------------")
                    print(testSummary.testName, "Failed", String(format: "(%@)", testSummary.simulatorName))
                    for exception in testSummary.exceptions ?? [] {
                        guard let line = exception["lineNumber"] as? Int, filePath = exception["filePathInProject"] as? String, reason = exception["reason"] as? String else { continue }
                        print("")
                        print("Reason:", reason)
                        print(filePath, String(format: "(line %d)", line))
                    }
                }
            }
            print("-------------------------------------------------------------------")
        }
    }
    
}

class SuiteSummary {
    
    var testCaseCount: Int
    var duration: NSTimeInterval
    var failureCount: Int

    init(testCaseCount: Int, duration: NSTimeInterval, failureCount: Int) {
        self.testCaseCount = testCaseCount
        self.duration = duration
        self.failureCount = failureCount
    }
}

class TestSummary {
    
    let simulatorName: String
    let testName: String
    let passed: Bool
    let duration: NSTimeInterval
    let exceptions: [[String: AnyObject]]?
    
    init(simulatorName: String, testName: String, passed: Bool, duration: NSTimeInterval, exceptions: [[String: AnyObject]]?) {
        self.simulatorName = simulatorName
        self.testName = testName
        self.passed = passed
        self.duration = duration
        self.exceptions = exceptions
    }
    
    
}
