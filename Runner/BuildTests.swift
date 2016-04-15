//
//  BuildTests.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/10/16.
//  Copyright © 2016 Stephan Heilner
//

import Cocoa

class BuildTests {
    
    static let sharedInstance = BuildTests()
    
    func build() throws {
        deleteFilesInDirectory(AppArgs.shared.derivedDataPath)
        
        let task = XCToolTask(arguments: ["clean", "build-tests"], logFilename: "build-tests.txt", outputFileLogType: .Text, standardOutputLogType: .Text)
        task.delegate = self
        task.launch()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else {
            if let log = String(data: task.standardErrorData, encoding: NSUTF8StringEncoding) where !log.isEmpty {
                throw FailureError.Failed(log: log)
            }
            return
        }

        if let bundleTests = listTests() {
            do {
                let data = try NSJSONSerialization.dataWithJSONObject(bundleTests, options: [])
                try data.writeToFile(AppArgs.shared.logsDir + "/testsByTarget.json", options: [])
            } catch {
                print("Unable to output tests", error)
            }
        }
        
    }
    
    private func listTests() -> [String: [String]]? {
        print("Listing tests...")
        
        let task = XCToolTask(arguments: ["run-tests", "-listTestsOnly"], logFilename: "listTests.json", outputFileLogType: .JSON, standardOutputLogType: .Text)
        task.delegate = self
        task.launch()
        
        let launchTimeout: NSTimeInterval = 60
        let waitForLaunchTimeout = dispatch_time(DISPATCH_TIME_NOW, Int64(launchTimeout * Double(NSEC_PER_SEC)))
        dispatch_after(waitForLaunchTimeout, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            if task.isRunning {
                task.terminate()
                print("Timed out getting list of tests")
                return
            }
        }
        
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            return nil
        }
        
        var bundleName = ""
        var tests = [String]()
        var bundleTests: [String: [String]] = [:]
        
        if let jsonObjects = JSON.jsonObjectsFromJSONStreamFile(AppArgs.shared.logsDir + "/listTests.json") {
            for jsonObject in jsonObjects {
                if let name = jsonObject["bundleName"] as? String {
                    bundleName = name.stringByReplacingOccurrencesOfString(".xctest", withString: "")
                    tests = bundleTests[bundleName] ?? [String]()
                }
                guard let className = jsonObject["className"] as? String, methodName = jsonObject["methodName"] as? String else { continue }
                tests.append(String(format: "%@/%@", className, methodName))
                bundleTests[bundleName] = tests.unique()
            }
        }
        
        return bundleTests
    }
    
    func deleteFilesInDirectory(path: String) {
        let task = NSTask()
        task.launchPath = "/bin/rm"
        task.arguments = ["-rf", path]
        task.standardError = NSPipe()
        task.standardOutput = NSPipe()
        task.launch()
        task.waitUntilExit()
    }
    
}

extension BuildTests: XCToolTaskDelegate {
    
    func outputDataReceived(task: XCToolTask, data: NSData) {
        TRLog(data)
    }
    
}
