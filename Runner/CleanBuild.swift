//
//  CleanBuild.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/10/16.
//  Copyright © 2016 The Church of Jesus Christ of Latter-day Saints. All rights reserved.
//

import Cocoa

class CleanBuild {
    
    static let sharedInstance = CleanBuild()
    
    func clean() throws {
        deleteFilesInDirectory(AppArgs.shared.derivedDataPath)
        
        let task = XCToolTask(arguments: ["clean"], logFilename: nil, outputFileLogType: nil, standardOutputLogType: .Text)
        task.delegate = self
        task.launch()
        task.waitUntilExit()
        
        if task.terminationStatus == 0 {
            return
        }
        
        if let log =  String(data: task.standardErrorData, encoding: NSUTF8StringEncoding) {
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

extension CleanBuild: XCToolTaskDelegate {
    
    func outputDataReceived(task: XCToolTask, data: NSData) {
        TRLog(data)
    }
    
}
