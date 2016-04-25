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
    
    func loadTestsForPartition(partition: Int, retries: Int = 5) -> [String]? {
        guard retries > 0 else { return nil }
        
        var tests: [String]?
        do {
            if let data = try NSData(contentsOfFile: AppArgs.shared.logsDir + "/testsByTarget.json") {
                if let targetTests = try NSJSONSerialization.JSONObjectWithData(data, options: []) as? [String: [String]] {
                    if let target = AppArgs.shared.target {
                        tests = targetTests[target]
                    }
                }
            }
        } catch {}
        
        guard let allTests = tests where !allTests.isEmpty else {
            return loadTestsForPartition(partition, retries: retries - 1)
        }
        
        let partitionsCount = AppArgs.shared.partitionsCount ?? 1
        let numTestsPerPartition = Float(allTests.count) / Float(partitionsCount)
        
        let start = Int(round(numTestsPerPartition * Float(partition)))
        let end = Int(round(numTestsPerPartition * Float(partition + 1)))
        
        return Array(allTests[start..<end])
    }
    
}