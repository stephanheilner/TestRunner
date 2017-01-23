//
//  BluepillTask.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/12/16.
//  Copyright © 2016 Stephan Heilner
//

import Cocoa


protocol BluepillTaskDelegate {
    
    func outputDataReceived(data: Data, isError: Bool)
    
}

class BluepillTask {
    
    fileprivate let task: Process
    
    var delegate: BluepillTaskDelegate?
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
    
    init(simulator: Simulator, tests: [String], logFilePath: String? = nil) {
        task = Process()
        task.launchPath = "/bin/sh"
        task.currentDirectoryPath = AppArgs.shared.currentDirectory
        task.environment = ProcessInfo.processInfo.environment
        
        var arguments = ["/Users/stephan/projects/ios/TestRunner/bluepill"]
        
        arguments += ["-a", "./build/derivedData/output/GospelLibrary.app"]
        arguments += ["-s", "./GospelLibrary.xcodeproj/xcshareddata/xcschemes/GospelLibrary.xcscheme"]
        arguments += ["-d", "'iPhone 5s'"]
        arguments += ["-n", "1"]
        
        //        if let project = AppArgs.shared.projectPath {
        //            arguments += ["-project", project]
        //        } else if let workspace = AppArgs.shared.workspacePath {
        //            arguments += ["-workspace", workspace]
        //        }
        //        arguments += ["-scheme", AppArgs.shared.scheme]
        //        arguments += ["-sdk", "iphonesimulator"]
        //        arguments += ["-derivedDataPath", AppArgs.shared.derivedDataPath]
        //        arguments += ["CONFIGURATION_BUILD_DIR=\(AppArgs.shared.outputDirectory)"]
        //        arguments += ["-destination", "'id=\(simulator.deviceID)'"]
        //        arguments += actions
        //        arguments += ["-newSimulatorInstance"]
        //
        //        if let target = AppArgs.shared.target {
        //            arguments += ["-only", "\(target):\(tests.joined(separator: ","))"]
        //        }
        
        arguments += tests.map { "-i \($0)" }
        
        let shellCommand = arguments.joined(separator: " ")
        print(shellCommand)
        
        task.arguments = ["-c", shellCommand]
        task.standardError = standardErrorPipe
        task.standardOutput = standardOutputPipe
        
        standardOutputPipe.fileHandleForReading.readabilityHandler = { handle in
            self.delegate?.outputDataReceived(data: handle.availableData, isError: false)
        }
        
        standardErrorPipe.fileHandleForReading.readabilityHandler = { handle in
            self.delegate?.outputDataReceived(data: handle.availableData, isError: true)
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
