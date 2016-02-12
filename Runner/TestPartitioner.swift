//
//  TestPartitioner.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/10/16.
//  Copyright © 2016 The Church of Jesus Christ of Latter-day Saints. All rights reserved.
//

import Cocoa
import Swiftification

class TestPartitioner {
    
    static let sharedInstance = TestPartitioner()
    
    func loadTestsByPartition() -> [[Int: [String]]]? {
        guard let allTests = listTests() where !allTests.isEmpty else { return nil }
        
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
        let task = XCToolTask(arguments: ["run-tests", "-only", AppArgs.shared.target, "-listTestsOnly"], logFilename: "list-tests.json", outputFileLogType: .JSON, standardOutputLogType: .Text)
        task.launch()
        task.delegate = self
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else { return nil }

        var tests: [String]?
        if let logFilePath = task.logFilePath, jsonObjects = JSONObject.jsonObjectFromJSONStreamFile(logFilePath) {
            tests = jsonObjects.flatMap { jsonObject -> String? in
                guard let className = jsonObject["className"] as? String, methodName = jsonObject["methodName"] as? String else { return nil }
                return String(format: "%@/%@", className, methodName)
            }.unique()
        }
        return tests
    }
    
}

extension TestPartitioner: XCToolTaskDelegate {
    
    func outputDataReceived(task: XCToolTask, data: NSData) {
        TRLog(data)
    }
}
