//
//  AppArgs.swift
//  GLContentPackager
//
//  Created by Nick Shelley on 10/9/14.
//  Copyright (c) 2014 Intellectual Reserve, Inc. All rights reserved.
//

import Foundation

struct AppArgs {
    
    static let shared = AppArgs()

    var projectPath: String?
    var workspacePath: String?
    let scheme: String
    let target: String
    let partition: Int
    let devices: String
    let simulatorsCount: Int
    let partitionsCount: Int
    let currentDirectory: String
    let buildTests: Bool
    let runTests: Bool
    let timeout: NSTimeInterval
    let buildDir: String
    let derivedDataPath: String
    let logsDir: String
    let retryCount: Int
    
    init() {
        if let scheme = NSUserDefaults.standardUserDefaults().stringForKey("scheme") {
            self.scheme = scheme
        } else {
            exitWithMessage("'-scheme' needs to be specified")
        }
        
        if let buildTests = NSUserDefaults.standardUserDefaults().objectForKey("build-tests") {
            self.buildTests = buildTests.boolValue
        } else {
            buildTests = true
        }

        if let runTests = NSUserDefaults.standardUserDefaults().objectForKey("run-tests") {
            self.runTests = runTests.boolValue
        } else {
            runTests = true
        }
        
        if let retryCount = NSUserDefaults.standardUserDefaults().objectForKey("retry-count") {
            self.retryCount = retryCount.integerValue
        } else {
            retryCount = 5 // Default
        }
        
        if let timeout = NSUserDefaults.standardUserDefaults().objectForKey("timeout") {
            self.timeout = NSTimeInterval(timeout.doubleValue)
        } else {
            timeout = NSTimeInterval(120) // Default
        }
        
        if let target = NSUserDefaults.standardUserDefaults().stringForKey("target") {
            self.target = target
        } else {
            exitWithMessage("'-target' needs to be specified")
        }

        if let devices = NSUserDefaults.standardUserDefaults().stringForKey("devices") {
            self.devices = devices
        } else {
            // Default
            self.devices = "iPhone 5, iOS 9.3; iPad 2, iOS 9.3"
        }

        // Defaults to partition 0
        partition = NSUserDefaults.standardUserDefaults().integerForKey("partition")

        if let simulatorsCount = NSUserDefaults.standardUserDefaults().objectForKey("simulators-count") {
            self.simulatorsCount = simulatorsCount.integerValue
        } else {
            // Defaults to 1 simulator
            simulatorsCount = 1
        }

        if let partitionsCount = NSUserDefaults.standardUserDefaults().objectForKey("partitions-count") {
            self.partitionsCount = partitionsCount.integerValue
        } else {
            // Defaults to 1 partition
            partitionsCount = 1
        }
        
        guard partition < partitionsCount else {
            exitWithMessage("-partition must be lower than -partitions-count")
        }

        var projectDirectory: String?
        
        if let project = NSUserDefaults.standardUserDefaults().stringForKey("project") {
            let projectURL = NSURL(fileURLWithPath: project)

            projectPath = projectURL.lastPathComponent
            projectDirectory = projectURL.URLByDeletingLastPathComponent?.path
            
        } else if let workspace = NSUserDefaults.standardUserDefaults().stringForKey("workspace") {
            let workspaceURL = NSURL(fileURLWithPath: workspace)
            
            workspacePath = workspaceURL.lastPathComponent
            projectDirectory = workspaceURL.URLByDeletingLastPathComponent?.path
        } else {
            exitWithMessage("'-workspace' or '-project' needs to be specified")
        }

        guard let currentDirectory = projectDirectory else {
            exitWithMessage("-workspace or -project must be absolute path")
        }
        
        self.currentDirectory = currentDirectory

        buildDir = currentDirectory + "/build"
        
        derivedDataPath = buildDir + "/derivedData"
        AppArgs.createDirectoryAtPath(derivedDataPath)

        logsDir = buildDir + "/logs"
        AppArgs.createDirectoryAtPath(logsDir)
    }
    
    private static func createDirectoryAtPath(path: String) {
        if !NSFileManager.defaultManager().fileExistsAtPath(path) {
            do {
                try NSFileManager.defaultManager().createDirectoryAtPath(path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                exitWithMessage(String(format: "Unable to create directory at path: %@", path))
            }
        }
    }
    
}

@noreturn func exitWithMessage(message: String, file: String = __FILE__, line: Int = __LINE__) {
    NSLog("%@", "Failure at \(file):\(line): \(message)")
    exit(1)
}
