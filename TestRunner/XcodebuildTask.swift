//
//  XcodebuildTask.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/12/16.
//  Copyright © 2016 Stephan Heilner
//

import Cocoa

enum LogType: String {
    case JSON = "json-stream"
    case Text = "pretty"
}

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
            self.delegate?.outputDataReceived(self, data: data)
            self.standardOutputData.appendData(data)
        }
        return pipe
    }()
    var running: Bool {
        return task.running
    }
    
    init(args: [String], logFilename: String? = nil, outputFileLogType: LogType? = nil, standardOutputLogType: LogType, environmentVars: [String: String]? = nil) {
        task = NSTask()
        task.launchPath = "/bin/sh"
        task.currentDirectoryPath = AppArgs.shared.currentDirectory
        task.environment = NSProcessInfo.processInfo().environment
        
        var arguments = ["/usr/bin/xcodebuild"]
        if let project = AppArgs.shared.projectPath {
            arguments += ["-project", project]
        } else if let workspace = AppArgs.shared.workspacePath {
            arguments += ["-workspace", workspace]
        }
        
        var outputLogArgs = [String]()

//        if let logFilename = logFilename {
//            let logFilePath = String(format: "%@/%@", AppArgs.shared.logsDir, logFilename)
//            self.logFilePath = logFilePath
//            
//            outputLogArgs += ["|", "tee", logFilePath]
//        }
//        
//        switch standardOutputLogType {
//        case .JSON:
            outputLogArgs += ["|", "/usr/local/bin/xcpretty", "-r", "json-compilation-database"]
//        case .Text:
//            outputLogArgs += ["|", "/usr/local/bin/xcpretty"]
//        }
        
        arguments += ["-scheme", AppArgs.shared.scheme]
        arguments += ["-sdk", "iphonesimulator"]
        arguments += ["-derivedDataPath", AppArgs.shared.derivedDataPath]
        
        let envVars = environmentVars?.map { "-\($0)=\"\($1)\" " } ?? []
        let shellCommand = (arguments + envVars + args + outputLogArgs).joinWithSeparator(" ")
        print(shellCommand)
        
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
