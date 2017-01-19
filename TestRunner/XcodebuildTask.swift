//
//  XcodebuildTask.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/12/16.
//  Copyright © 2016 Stephan Heilner
//

import Cocoa


protocol XcodebuildTaskDelegate {

    func outputDataReceived(_ task: XcodebuildTask, data: Data)
    
}

class XcodebuildTask {
    
    fileprivate let task: Process
    
    var delegate: XcodebuildTaskDelegate?
    var logFilePath: String?
    
    var terminationHandler: ((Process) -> Void)? {
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
            return task.isRunning
        }
    }

    var terminationReason: Process.TerminationReason {
        get {
            return task.terminationReason
        }
    }
    
    let standardErrorPipe = Pipe()
    let standardOutputPipe = Pipe()
    
    var running: Bool {
        return task.isRunning
    }
    
    init(actions: [String], destination: String? = nil, tests: [String]? = nil, logFilePath: String? = nil) {
        task = Process()
        task.launchPath = "/bin/sh"
        task.currentDirectoryPath = AppArgs.shared.currentDirectory
        task.environment = ProcessInfo.processInfo.environment
        
        var arguments = ["xcodebuild"] + actions
        
        if let project = AppArgs.shared.projectPath {
            arguments += ["-project", project]
        } else if let workspace = AppArgs.shared.workspacePath {
            arguments += ["-workspace", workspace]
        }
        arguments += ["-scheme", AppArgs.shared.scheme]
        arguments += ["-sdk", "iphonesimulator"]
        arguments += ["-derivedDataPath", AppArgs.shared.derivedDataPath]
        arguments += ["CONFIGURATION_BUILD_DIR=\(AppArgs.shared.outputDirectory)"]
        
        if let destination = destination {
            arguments += ["-destination", "'\(destination)'"]
        }
        
        if let tests = tests {
            arguments += tests.map { "-only-testing:\($0)" }
        }
        
        var output: [String] = []
        if let logFilePath = logFilePath {
            output = ["|", "tee", "\"\(logFilePath)\""]
        }
        output += ["|", "LC_ALL='en_US.UTF-8'", "/usr/local/bin/xcpretty"]

        let shellCommand = (arguments + output).joined(separator: " ")
        TRLog("\n\n\(shellCommand)\n\n")
        
        task.arguments = ["-c", shellCommand]
        task.standardError = standardErrorPipe
        task.standardOutput = standardOutputPipe

        standardOutputPipe.fileHandleForReading.readabilityHandler = { handle in
            self.delegate?.outputDataReceived(self, data: handle.availableData)
        }
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
