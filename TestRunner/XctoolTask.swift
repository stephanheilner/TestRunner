//
//  XctoolTask.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/12/16.
//  Copyright © 2016 Stephan Heilner
//

import Cocoa


protocol XctoolTaskDelegate {
    
    func outputDataReceived(_ task: XctoolTask, data: Data)
    
}

class XctoolTask {
    
    fileprivate let task: Process
    
    var delegate: XctoolTaskDelegate?
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
    
    init(actions: [String], deviceID: String? = nil, destination: String? = nil, tests: [String], logFilePath: String? = nil) {
        task = Process()
        task.launchPath = "/bin/sh"
        task.currentDirectoryPath = AppArgs.shared.currentDirectory
        task.environment = ProcessInfo.processInfo.environment
        
        var arguments = ["/usr/local/bin/xctool"]
        
        if let project = AppArgs.shared.projectPath {
            arguments += ["-project", project]
        } else if let workspace = AppArgs.shared.workspacePath {
            arguments += ["-workspace", workspace]
        }
        arguments += ["-scheme", AppArgs.shared.scheme]
        arguments += ["-sdk", "iphonesimulator"]
        arguments += ["-derivedDataPath", AppArgs.shared.derivedDataPath]
        arguments += ["CONFIGURATION_BUILD_DIR=\(AppArgs.shared.outputDirectory)"]
        
        if let deviceID = deviceID {
            arguments += ["-destination", "'id=\(deviceID)'"]
        }
        if let destination = destination {
            arguments += ["-destination", "'\(destination)'"]
        }
        
        arguments += actions
        arguments += ["-newSimulatorInstance"]
        
        if let target = AppArgs.shared.target {
            arguments += ["-only", "\(target):\(tests.joined(separator: ","))"]
        }
        
        arguments += ["-reporter", "pretty"]
        if let logFilePath = logFilePath {
            arguments += ["-reporter", "json-stream:\(logFilePath)"]
        }
        
        let shellCommand = arguments.joined(separator: " ")
        
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
