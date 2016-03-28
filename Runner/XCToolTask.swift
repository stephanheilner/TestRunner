//
//  XCToolTask.swift
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

protocol XCToolTaskDelegate {

    func outputDataReceived(task: XCToolTask, data: NSData)
    
}

class XCToolTask {
    
    private let task: NSTask
    
    let standardOutputData = NSMutableData()
    let standardErrorData = NSMutableData()
    var delegate: XCToolTaskDelegate?
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
    
    init(arguments: [String], logFilename: String?, outputFileLogType: LogType?, standardOutputLogType: LogType) {
        task = NSTask()
        task.launchPath = "/bin/sh"
        task.currentDirectoryPath = AppArgs.shared.currentDirectory

        var xctoolArguments = ["xctool"]
        if let project = AppArgs.shared.projectPath {
            xctoolArguments += ["-project", project]
        } else if let workspace = AppArgs.shared.workspacePath {
            xctoolArguments += ["-workspace", workspace]
        }
        
        var outputLogArgs = [String]()
        
        switch standardOutputLogType {
        case .JSON:
            outputLogArgs += ["-reporter", "json-stream"]
        case .Text:
            outputLogArgs += ["-reporter", "pretty"]
        }
        
        if let logFilename = logFilename, outputFileLogType = outputFileLogType {
            let logFilePath = String(format: "%@/%@", AppArgs.shared.logsDir, logFilename)
            self.logFilePath = logFilePath
            
            switch outputFileLogType {
            case .JSON:
                outputLogArgs += ["-reporter", "json-stream:\"\(logFilePath)\""]
            case .Text:
                outputLogArgs += ["-reporter", "plain:\"\(logFilePath)\""]
            }
        }
        
        xctoolArguments += ["-scheme", AppArgs.shared.scheme, "-sdk", "iphonesimulator", "CONFIGURATION_BUILD_DIR=\"\(AppArgs.shared.derivedDataPath)\"", "-derivedDataPath", AppArgs.shared.derivedDataPath] + outputLogArgs
        
        let shellCommand = (xctoolArguments + arguments).joinWithSeparator(" ")
        
        task.arguments = ["-c", shellCommand]
        task.standardError = standardErrorPipe
        task.standardOutput = standardOutputPipe
        
        var environment = NSProcessInfo.processInfo().environment
        if let path = environment["PATH"] {
            if !path.containsString("/usr/bin:") {
                environment["PATH"] = "/usr/bin:" + path
            }
            if !path.containsString("/usr/local/bin:") {
                environment["PATH"] = "/usr/local/bin:" + path
            }
        }
        task.environment = environment
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
