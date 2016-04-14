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
        
        if task.terminationStatus == 0 {
            return
        }

        if let log = String(data: task.standardErrorData, encoding: NSUTF8StringEncoding) where !log.isEmpty {
            throw FailureError.Failed(log: log)
        }
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
