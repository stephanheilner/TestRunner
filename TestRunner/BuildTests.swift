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
        deleteFilesInDirectory(AppArgs.shared.logsDir)
        
        let testsJSONPath = "\(AppArgs.shared.derivedDataPath)/tests.json"
        print("Tests:", testsJSONPath)
        
//        xcodebuild -project /Users/stephan/projects/ios/TestRunner/MyTestProject/MyTestProject.xcodeproj -scheme MyTestProject -sdk iphonesimulator -derivedDataPath ${DERIVED_DATA_PATH} CONFIGURATION_BUILD_DIR=${DERIVED_DATA_PATH} clean build-for-testing

        let task = XcodebuildTask(args: ["-destination", "'platform=iOS Simulator,name=iPhone 5,OS=10.0'", "clean", "test"], standardOutputLogType: .Text, environmentVars: ["LIST_TESTS": testsJSONPath])
        task.delegate = self
        task.launch()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else {
            if let log = String(data: task.standardErrorData, encoding: NSUTF8StringEncoding) where !log.isEmpty {
                throw FailureError.Failed(log: log)
            }
            return
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

extension BuildTests: XcodebuildTaskDelegate {
    
    func outputDataReceived(task: XcodebuildTask, data: NSData) {
        TRLog(data)
    }
    
}
