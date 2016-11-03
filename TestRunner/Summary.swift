//
//  Summary.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/22/16.
//  Copyright © 2016 Stephan Heilner
//

import Foundation

class Summary {
    
    class func outputSummary(_ jsonOutput: Bool) {
        
        var simulatorRetries = [String: Int]()
        var testSummaries = [TestSummary]()
        var suiteSummaries = [SuiteSummary]()
        
        do {
            for filename in try FileManager.default.contentsOfDirectory(atPath: AppArgs.shared.logsDir) where filename.range(of: "Test Simulator") != nil {
                var simulatorName = filename
                
                if let range = filename.range(of: " (") {
                    simulatorName = filename.substring(with: filename.startIndex..<range.lowerBound)
                    simulatorRetries[simulatorName] = (simulatorRetries[simulatorName] ?? -1) + 1
                } else if let range = filename.range(of: ".json") {
                    simulatorName = filename.substring(with: filename.startIndex..<range.lowerBound)
                    simulatorRetries[simulatorName] = (simulatorRetries[simulatorName] ?? -1) + 1
                }
                
                if let jsonObjects = JSON.jsonObjectsFromJSONStreamFile(String(format: "%@/%@", AppArgs.shared.logsDir, filename)) {
                    testSummaries += jsonObjects.flatMap { jsonObject -> TestSummary? in
                        guard let event = jsonObject["event"] as? String, event == "end-test", let testName = jsonObject["test"] as? String, let succeeded = jsonObject["succeeded"] as? Bool, let duration = jsonObject["totalDuration"] as? TimeInterval else { return nil }
                        let exceptions = jsonObject["exceptions"] as? [[String: AnyObject]]
                        return TestSummary(simulatorName: simulatorName, testName: testName, passed: succeeded, duration: duration, exceptions: exceptions)
                    }
                    for jsonObject in jsonObjects {
                        if let event = jsonObject["event"] as? String, event == "end-test-suite", let testCaseCount = jsonObject["testCaseCount"] as? Int, let duration = jsonObject["totalDuration"] as? TimeInterval, let failureCount = jsonObject["totalFailureCount"] as? Int {
                            suiteSummaries.append(SuiteSummary(testCaseCount: testCaseCount, duration: duration, failureCount: failureCount))
                        }
                    }
                }
            }
        } catch {}

        let suiteSummary = suiteSummaries.reduce(SuiteSummary(testCaseCount: 0, duration: 0, failureCount: 0), { totalSummary, suiteSummary in
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
            
            testSummaries.sort { lhs, rhs -> Bool in
                if lhs.passed == rhs.passed {
                    return lhs.testName == rhs.testName
                } else {
                    return lhs.passed
                }
            }
            
            print("-------------------------------------------------------------------")
            
            // Get of list of test that never passed.
            var failureTestSummaries = testSummaries.filter { !$0.passed }.uniqueBy { $0.testName }
            for testSummary in testSummaries {
                for (index, failureSummary) in failureTestSummaries.enumerated() where testSummary.testName == failureSummary.testName && testSummary.passed {
                    // Even though this test summary shows it failed, it retried and eventually passed, so remove it from the list.
                    failureTestSummaries.remove(at: index)
                }
            }
            
            for testSummary in failureTestSummaries {
                print("-------------------------------------------------------------------")
                print(testSummary.testName, "Failed", String(format: "(%@)", testSummary.simulatorName))
                for exception in testSummary.exceptions ?? [] {
                    guard let line = exception["lineNumber"] as? Int, let filePath = exception["filePathInProject"] as? String, let reason = exception["reason"] as? String else { continue }
                    print("")
                    print("Reason:", reason)
                    print(filePath, String(format: "(line %d)", line))
                }
            }
            print("-------------------------------------------------------------------")
        }
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
