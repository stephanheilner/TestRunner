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
    
    init(arguments: [String], logFilename: String?, outputFileLogType: LogType?, standardOutputLogType: LogType) {
        task = NSTask()
        task.launchPath = "/bin/sh"
        task.currentDirectoryPath = AppArgs.shared.currentDirectory
        task.environment = NSProcessInfo.processInfo().environment
        
        var xctoolArguments = ["/usr/local/bin/xctool"]
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
        
        
        
        let envVars = [
            "CONFIGURATION_TEMP_DIR": "\(AppArgs.shared.derivedDataPath)",
            "PROJECT_TEMP_ROOT": "\(AppArgs.shared.buildDir)/project",
            "PROJECT_TEMP_DIR": "\(AppArgs.shared.buildDir)/project/\(NSUUID().UUIDString)",
            "TARGET_TEMP_DIR": "\(AppArgs.shared.buildDir)/\(NSUUID().UUIDString)",
            "TEMP_DIR": "\(AppArgs.shared.buildDir)/temp/\(NSUUID().UUIDString)",
            "TEMP_FILES_DIR": "\(AppArgs.shared.buildDir)/temp/\(NSUUID().UUIDString)",
            "TEMP_FILE_DIR": "\(AppArgs.shared.buildDir)/temp/\(NSUUID().UUIDString)",
            "TEMP_ROOT": "\(AppArgs.shared.buildDir)/temp",
            "AD_HOC_CODE_SIGNING_ALLOWED": "NO",
            "CODE_SIGNING_ALLOWED": "NO",
            "CODE_SIGNING_REQUIRED": "NO"
        ].toArray { key, value -> String in
            return String(format: "%@=\"%@\"", key, value)
        }
        
        xctoolArguments += [
            "-scheme", AppArgs.shared.scheme,
            "-sdk", "iphonesimulator",
            "-derivedDataPath", AppArgs.shared.derivedDataPath
            ] + outputLogArgs + envVars
        
        let shellCommand = (xctoolArguments + arguments).joinWithSeparator(" ")
        
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
