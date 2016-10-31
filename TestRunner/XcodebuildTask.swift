//
//  XcodebuildTask.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/12/16.
//  Copyright © 2016 Stephan Heilner
//

import Cocoa


protocol XcodebuildTaskDelegate {

    func outputDataReceived(task: XcodebuildTask, data: NSData)
    
}

class XcodebuildTask {
    
    private let task: NSTask
    
    let standardOutputData = NSMutableData()
    let standardErrorData = NSMutableData()
    var delegate: XcodebuildTaskDelegate?
    var logFilePath: String?
    
    var terminationHandler: (NSTask -> Void)? {
        set {
            task.terminationHandler = newValue
        }
        get {
            return task.terminationHandler
        }
    }
    
    var terminationStatus: Int32 {
        get {
            return task.terminationStatus
        }
    }
    
    var isRunning: Bool {
        get {
            return task.running
        }
    }

    var terminationReason: NSTaskTerminationReason {
        get {
            return task.terminationReason
        }
    }
    
    lazy var standardErrorPipe: NSPipe = {
        let pipe = NSPipe()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            self.standardErrorData.appendData(handle.availableData)
        }
        return pipe
    }()
    
    lazy var standardOutputPipe: NSPipe = {
        let pipe = NSPipe()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            self.standardOutputData.appendData(data)
            self.delegate?.outputDataReceived(self, data: data)
        }
        return pipe
    }()
    var running: Bool {
        return task.running
    }
    
    init(actions: [String], deviceID: String? = nil, tests: [String]? = nil, logFilePath: String? = nil) {
        task = NSTask()
        task.launchPath = "/bin/sh"
        task.currentDirectoryPath = AppArgs.shared.currentDirectory
        task.environment = NSProcessInfo.processInfo().environment
        
        var arguments = ["xcodebuild"] + actions
        
        if let project = AppArgs.shared.projectPath {
            arguments += ["-project", project]
        } else if let workspace = AppArgs.shared.workspacePath {
            arguments += ["-workspace", workspace]
        }
        arguments += ["-scheme", AppArgs.shared.scheme]
        arguments += ["-sdk", "iphonesimulator"]
        arguments += ["-derivedDataPath", AppArgs.shared.derivedDataPath]
        
        if let deviceID = deviceID {
            arguments += ["-destination", "'id=\(deviceID)'"]
        }
        
        arguments.append("CONFIGURATION_BUILD_DIR='\(AppArgs.shared.derivedDataPath)'")
        
        if let tests = tests {
            arguments += tests.map { "-only-testing:\($0)" }
        }
        
        var output: [String] = []
        if let logFilePath = logFilePath {
            output = ["|", "tee", "\"\(logFilePath)\""]
        } else {
            output = ["|", "/usr/local/bin/xcpretty"]
        }

        let shellCommand = (arguments + output).joinWithSeparator(" ")
        print("\n\n\(shellCommand)\n\n")
        
        task.arguments = ["-c", shellCommand]
        task.standardError = standardErrorPipe
        task.standardOutput = standardOutputPipe
    }

    func launch() {
        task.launch()
    }
    
    func waitUntilExit() {
        task.waitUntilExit()
    }
    
    func terminate() {
        task.terminate()
    }
    
}
