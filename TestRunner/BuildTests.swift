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
    fileprivate static let PlistValueName = "TestRunnerListTests"
    
    func build(listTests: Bool) throws {
        let actions: [String]
        if listTests {
            actions = ["test-without-building"]
            addPlistEntries(name: BuildTests.PlistValueName, value: "\(AppArgs.shared.logsDir)/tests.json")
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
            if let log = String(data: task.standardErrorData as Data, encoding: String.Encoding.utf8), !log.isEmpty {
                throw FailureError.failed(log: log)
            }
            return
        }

        if listTests {
            deletePlistEntries(name: BuildTests.PlistValueName)
        }
    }
    
    func deleteFilesInDirectory(_ path: String) {
        let task = Process()
        task.launchPath = "/bin/rm"
        task.arguments = ["-rf", path]
        task.standardError = Pipe()
        task.standardOutput = Pipe()
        task.launch()
        task.waitUntilExit()
    }
    
    func addPlistEntries(name: String, value: String) {
        [AppArgs.shared.scheme, AppArgs.shared.uiTestScheme].forEach { scheme in
            let task = Process()
            task.launchPath = "/bin/sh"
            let infoPlist = String(format: "%@/%@.app/Info.plist", AppArgs.shared.derivedDataPath, scheme)
            let arguments = ["/usr/libexec/PlistBuddy", infoPlist, "-c", "\"Add :\(name) string \(value)\""]
            task.arguments = ["-c", arguments.joined(separator: " ")]
            task.standardError = Pipe()
            task.standardOutput = Pipe()
            task.launch()
            task.waitUntilExit()
        }
    }
    
    func deletePlistEntries(name: String) {
        [AppArgs.shared.scheme, AppArgs.shared.uiTestScheme].forEach { scheme in
            let task = Process()
            task.launchPath = "/bin/sh"
        
            let infoPlist = String(format: "%@/%@.app/Info.plist", AppArgs.shared.derivedDataPath, scheme)
            let arguments = ["/usr/libexec/PlistBuddy", infoPlist, "-c", "\"Delete :\(name)\""]
            task.arguments = ["-c", arguments.joined(separator: " ")]
            task.standardError = Pipe()
            task.standardOutput = Pipe()
            task.launch()
            task.waitUntilExit()
        }
    }
    
}

extension BuildTests: XcodebuildTaskDelegate {
    
    func outputDataReceived(_ task: XcodebuildTask, data: Data) {
        TRLog(data)
    }
    
}
