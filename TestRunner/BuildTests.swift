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
    private static let PlistValueName = "TestRunnerListTests"
    
    func build(listTests listTests: Bool) throws {
        
        let actions: [String]
        if listTests {
            actions = ["test-without-building"]
            addPlistEntry(name: BuildTests.PlistValueName, value: "\(AppArgs.shared.logsDir)/tests.json")
        } else {
            deleteFilesInDirectory(AppArgs.shared.derivedDataPath)
            deleteFilesInDirectory(AppArgs.shared.logsDir)
            actions = ["clean", "build-for-testing"]
        }
        
        let deviceID = DeviceController.sharedController.createTestDevice()
        let task = XcodebuildTask(actions: actions, deviceID: deviceID)
        task.delegate = self
        task.launch()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else {
            if let log = String(data: task.standardErrorData, encoding: NSUTF8StringEncoding) where !log.isEmpty {
                throw FailureError.Failed(log: log)
            }
            return
        }

        if listTests {
            deletePlistEntry(name: BuildTests.PlistValueName)
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
    
    func addPlistEntry(name name: String, value: String) {
        let task = NSTask()
        task.launchPath = "/bin/sh"
        let infoPlist = String(format: "%@/%@.app/Info.plist", AppArgs.shared.derivedDataPath, AppArgs.shared.scheme)
        let arguments = ["/usr/libexec/PlistBuddy", infoPlist, "-c", "\"Add :\(name) string \(value)\""]
        task.arguments = ["-c", arguments.joinWithSeparator(" ")]
        task.standardError = NSPipe()
        task.standardOutput = NSPipe()
        task.launch()
        task.waitUntilExit()
    }
    
    func deletePlistEntry(name name: String) {
        let task = NSTask()
        task.launchPath = "/bin/sh"
        
        let infoPlist = String(format: "%@/%@.app/Info.plist", AppArgs.shared.derivedDataPath, AppArgs.shared.scheme)
        let arguments = ["/usr/libexec/PlistBuddy", infoPlist, "-c", "\"Delete :\(name)\""]
        task.arguments = ["-c", arguments.joinWithSeparator(" ")]
        task.standardError = NSPipe()
        task.standardOutput = NSPipe()
        task.launch()
        task.waitUntilExit()
    }
    
}

extension BuildTests: XcodebuildTaskDelegate {
    
    func outputDataReceived(task: XcodebuildTask, data: NSData) {
        TRLog(data)
    }
    
}
