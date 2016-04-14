//
//  TestPartitioner.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/10/16.
//  Copyright © 2016 Stephan Heilner
//

import Cocoa
import Swiftification

class TestPartitioner {
    
    static let sharedInstance = TestPartitioner()
    
    func loadTestsByPartition(retries: Int = 5) -> [[Int: [String]]]? {
        guard retries > 0 else { return nil }
        
        guard let allTests = listTests() where !allTests.isEmpty else {
            return loadTestsByPartition(retries - 1)
        }
        
        let partitionsCount = AppArgs.shared.partitionsCount ?? 1
        let numTestsPerPartition = Float(allTests.count) / Float(partitionsCount)
        
        var start = 0
        var end = 0
        
        var partitionTests = [[String]]()
        
        for i in 0..<partitionsCount {
            start = Int(round(numTestsPerPartition * Float(i)))
            end = Int(round(numTestsPerPartition * Float(i + 1)))
            
            let tests = allTests[start..<end]
            partitionTests.append(Array(tests))
        }
        
        let simulatorsCount = AppArgs.shared.simulatorsCount ?? 1
        
        var testsByPartition = [[Int: [String]]]()
        for (_, tests) in partitionTests.enumerate() {
            let numTestsPerSimulator = Float(tests.count) / Float(simulatorsCount)
            var testsBySimulator = [Int: [String]]()
            
            for i in 0..<simulatorsCount {
                start = Int(round(numTestsPerSimulator * Float(i)))
                end = Int(round(numTestsPerSimulator * Float(i + 1)))
                
                testsBySimulator[i] = Array(tests[start..<end])
            }
            
            testsByPartition.append(testsBySimulator)
        }
        
        return testsByPartition
    }
    
    private func listTests() -> [String]? {
        print("Listing tests...")
        
        let task = XCToolTask(arguments: ["run-tests", "-only", AppArgs.shared.target, "-listTestsOnly"], logFilename: nil, outputFileLogType: .JSON, standardOutputLogType: .JSON)
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
        guard task.terminationStatus == 0 else { return nil }

        var tests: [String]?
        if let jsonObjects = JSON.jsonObjectFromStandardOutputData(task.standardOutputData) {
            tests = jsonObjects.flatMap { jsonObject -> String? in
                guard let className = jsonObject["className"] as? String, methodName = jsonObject["methodName"] as? String else { return nil }
                return String(format: "%@/%@", className, methodName)
            }.unique()
        }
        
        return tests
    }
    
}