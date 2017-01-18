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
    
    func loadTestsByPartition() -> [[Int: [String]]]? {
        var allTests = Set<String>()
        do {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: AppArgs.shared.logsDir + "/tests.json")) {
                if let targetTests = try JSONSerialization.jsonObject(with: data, options: []) as? [String: [String]] {
                    if let target = AppArgs.shared.target, let tests = targetTests[target] {
                        let testNames = tests.map { $0.replacingOccurrences(of: "\(target)/", with: "") }
                        allTests.formUnion(testNames)
                    } else {
                        targetTests.forEach { target, tests in
                            allTests.formUnion(tests)
                        }
                    }
                }
            }
        } catch {
            print(error)
        }
        
        let partitionsCount = AppArgs.shared.partitionsCount
        let numTestsPerPartition = Float(allTests.count) / Float(partitionsCount)
        
        var start = 0
        var end = 0
        
        var tests = Array(allTests).sorted()
        var partitionTests = [[String]]()
        
        for i in 0..<partitionsCount {
            start = Int(round(numTestsPerPartition * Float(i)))
            end = Int(round(numTestsPerPartition * Float(i + 1)))
            partitionTests.append(Array(tests[start..<end]))
        }
        
        let simulatorsCount = AppArgs.shared.simulatorsCount
        
        var testsByPartition = [[Int: [String]]]()
        for (_, tests) in partitionTests.enumerated() {
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
