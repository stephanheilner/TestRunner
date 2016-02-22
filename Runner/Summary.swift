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
        var jsonObjects = [[String: AnyObject]]()
        
        do {
            for filename in try NSFileManager.defaultManager().contentsOfDirectoryAtPath(AppArgs.shared.logsDir) {

                if let range = filename.rangeOfString(" (") {
                    let simulatorName = filename.substringWithRange(Range(start: filename.startIndex, end: range.startIndex))
                    simulatorRetries[simulatorName] = (simulatorRetries[simulatorName] ?? -1) + 1
                } else if let range = filename.rangeOfString(".json") {
                    let simulatorName = filename.substringWithRange(Range(start: filename.startIndex, end: range.startIndex))
                    simulatorRetries[simulatorName] = (simulatorRetries[simulatorName] ?? -1) + 1
                }
                
                jsonObjects += JSON.jsonObjectsFromJSONStreamFile(String(format: "%@/%@", AppArgs.shared.logsDir, filename)) ?? []
            }
        } catch {}
        
        let testSummaries = jsonObjects.flatMap { jsonObject -> TestSummary? in
            guard let event = jsonObject["event"] as? String where event == "end-test", let testName = jsonObject["test"] as? String, succeeded = jsonObject["succeeded"] as? Bool, duration = jsonObject["totalDuration"] as? NSTimeInterval else { return nil }
            let exceptions = jsonObject["exceptions"] as? [[String: AnyObject]]
            return TestSummary(testName: testName, passed: succeeded, duration: duration, exceptions: exceptions)
        }.sort { lhs, rhs -> Bool in
            if lhs.passed == rhs.passed {
                return lhs.testName == rhs.testName
            } else {
                return lhs.passed
            }
        }
        
        let suiteSummaries = jsonObjects.flatMap { jsonObject -> SuiteSummary? in
            guard let event = jsonObject["event"] as? String where event == "end-test-suite", let testCaseCount = jsonObject["testCaseCount"] as? Int, duration = jsonObject["totalDuration"] as? NSTimeInterval, failuresCount = jsonObject["totalFailureCount"] as? Int else { return nil }
            return SuiteSummary(testCaseCount: testCaseCount, duration: duration, failuresCount: failuresCount)
        }
        
        var totalSummary = SuiteSummary(testCaseCount: 0, duration: 0, failuresCount: 0)
        for suiteSummary in suiteSummaries {
            totalSummary = SuiteSummary(testCaseCount: (totalSummary.testCaseCount + suiteSummary.testCaseCount), duration: (totalSummary.duration + suiteSummary.duration), failuresCount: (totalSummary.failureCount + suiteSummary.failureCount))
        }
        
        if jsonOutput {
            // TODO: Output JSON
            
        } else {
            // Plain Text
            print("\n============================ SUMMARY ============================\n")
            for (simulatorName, retries) in simulatorRetries {
                print(String(format: "'%@': %d Retries", simulatorName, retries))
            }

            print("")
            print(totalSummary.testCaseCount, "Test Run in", totalSummary.duration, "seconds.", totalSummary.failureCount, "Failures")
            print("")

            // Number of each devices run
            // Number of retries on each
            
            for testSummary in testSummaries {
                if testSummary.passed {
                    print(testSummary.testName, "Passed")
                } else {
                    print("")
                    print(testSummary.testName, "Failed")
                    for exception in testSummary.exceptions ?? [] {
                        guard let line = exception["lineNumber"] as? Int, filePath = exception["filePathInProject"] as? String, reason = exception["reason"] as? String else { continue }
                        print("")
                        print("Reason:", reason)
                        print(filePath, String(format: "(line %d)", line))
                    }
                }
            }
        }
    }
    
}

class SuiteSummary {
    
    let testCaseCount: Int
    let duration: NSTimeInterval
    let failureCount: Int

    init(testCaseCount: Int, duration: NSTimeInterval, failuresCount: Int) {
        self.testCaseCount = testCaseCount
        self.duration = duration
        self.failureCount = failuresCount
    }
}

class TestSummary {
    
    let testName: String
    let passed: Bool
    let duration: NSTimeInterval
    let exceptions: [[String: AnyObject]]?
    
    init(testName: String, passed: Bool, duration: NSTimeInterval, exceptions: [[String: AnyObject]]?) {
        self.testName = testName
        self.passed = passed
        self.duration = duration
        self.exceptions = exceptions
    }
    
    
}
