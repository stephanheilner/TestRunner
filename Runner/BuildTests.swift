//
//  BuildTests.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/10/16.
//  Copyright © 2016 The Church of Jesus Christ of Latter-day Saints. All rights reserved.
//

import Cocoa

class BuildTests {
    
    static let sharedInstance = BuildTests()
    
    func build() throws {
        let task = XCToolTask(arguments: ["build-tests"], logFilename: "build-tests.txt", outputFileLogType: .Text, standardOutputLogType: .Text)
        task.delegate = self
        task.launch()
        task.waitUntilExit()
        
        if task.terminationStatus == 0 {
            return
        }

        if let log = String(data: task.standardErrorData, encoding: NSUTF8StringEncoding) where !log.isEmpty {
            throw FailureError.Failed(log: log)
        }
    }
    
}

extension BuildTests: XCToolTaskDelegate {
    
    func outputDataReceived(task: XCToolTask, data: NSData) {
        TRLog(data)
    }
    
}
