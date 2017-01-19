//
//  Summary.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/22/16.
//  Copyright © 2016 Stephan Heilner
//

import Foundation

class Summary {
    
    class func outputSummary(logFile: String? = nil, simulator: Simulator? = nil) {
        let logDirectoryURL = URL(fileURLWithPath: AppArgs.shared.logsDir)
        
        var logs = [String]()
        
        logs.append("\n============================ SUMMARY ============================")
        
        var testResults = [TestResult]()
        
        do {
            for fileURL in try FileManager.default.contentsOfDirectory(at: logDirectoryURL, includingPropertiesForKeys: nil, options: FileManager.DirectoryEnumerationOptions.skipsHiddenFiles) {
                if let logFile = logFile, logFile != fileURL.path {
                    continue
                }
                
                testResults += JSON.testResults(logPath: fileURL.path)
            }
        } catch {
            TRLog(error.localizedDescription, simulator: simulator)
        }

        let succeededTests = testResults.filter { $0.passed }
        if !succeededTests.isEmpty {
            logs.append("\n---------- Passed Tests ----------")
            for test in succeededTests.sorted(by: { $0.0.testName < $0.1.testName }) {
                logs.append("\(test.testName) (\(test.duration) seconds)")
            }
        }
        
        let failedTests = testResults.filter { failedTest -> Bool in
            return !failedTest.passed && !succeededTests.contains(where: { succeededTest -> Bool in
                return failedTest.testName == succeededTest.testName
            })
        }
        if !failedTests.isEmpty {
            logs.append("\n---------- Failed Tests ----------")
            for test in failedTests.sorted(by: { $0.0.testName < $0.1.testName }) {
                logs.append("\(test.testName) (\(test.duration) seconds)")
            }
        }
        
        logs.append("\n=================================================================\n")
        TRLog(logs.joined(separator: "\n"), simulator: simulator)
    }
    
}
