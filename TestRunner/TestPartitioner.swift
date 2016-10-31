//
//  TestPartitioner.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/10/16.
//  Copyright © 2016 Stephan Heilner
//

import Cocoa


class TestPartitioner {
    
    static let sharedInstance = TestPartitioner()
    
    func loadTestsByPartition(retries: Int = 5) -> [[Int: [String]]]? {
        guard retries > 0 else { return nil }
        
        var tests: [String]?
        do {
            if let data = NSData(contentsOfFile: AppArgs.shared.logsDir + "/tests.json") {
                let targetTests = try NSJSONSerialization.JSONObjectWithData(data, options: [])
                if let target = AppArgs.shared.target {
                    tests = targetTests[target] as? [String]
                }
            }
        } catch {
            print(error)
        }
        
        guard let allTests = tests where !allTests.isEmpty else {
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
    
}
