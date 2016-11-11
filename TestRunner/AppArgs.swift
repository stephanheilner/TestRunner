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
    var target: String?
    let partition: Int
    let devices: String
    let simulatorsCount: Int
    let partitionsCount: Int
    let currentDirectory: String
    let buildTests: Bool
    let runTests: Bool
    let timeout: TimeInterval
    let launchTimeout: Int
    let buildDir: String
    let derivedDataPath: String
    let logsDir: String
    let retryCount: Int
    let launchRetryCount: Int
    
    init() {
        if let scheme = UserDefaults.standard.string(forKey: "scheme") {
            self.scheme = scheme
        } else {
            exitWithMessage("'-scheme' needs to be specified")
        }
        
        if let buildTests = UserDefaults.standard.object(forKey: "build-tests") {
            self.buildTests = (buildTests as AnyObject).boolValue
        } else {
            buildTests = true
        }

        if let runTests = UserDefaults.standard.object(forKey: "run-tests") {
            self.runTests = (runTests as AnyObject).boolValue
        } else {
            runTests = true
        }
        
        if let retryCount = UserDefaults.standard.object(forKey: "retry-count") {
            self.retryCount = (retryCount as AnyObject).intValue
        } else {
            retryCount = 5 // Default
        }
        
        if let launchRetryCount = UserDefaults.standard.object(forKey: "launch-retry-count") {
            self.launchRetryCount = (launchRetryCount as AnyObject).intValue
        } else {
            launchRetryCount = 10 // Default
        }
        
        if let timeout = UserDefaults.standard.object(forKey: "timeout") {
            self.timeout = TimeInterval((timeout as AnyObject).doubleValue)
        } else {
            timeout = TimeInterval(120) // Default
        }
        
        let launchTimeout = UserDefaults.standard.integer(forKey: "launch-timeout")
        if launchTimeout > 0 {
            self.launchTimeout = launchTimeout
        } else {
            self.launchTimeout = 30 // Default
        }
        
        if let target = UserDefaults.standard.string(forKey: "target") {
            self.target = target
        }

        if let devices = UserDefaults.standard.string(forKey: "devices") {
            self.devices = devices
        } else {
            // Default
            self.devices = "iPhone 5, iOS 9.3; iPad 2, iOS 9.3"
        }

        // Defaults to partition 0
        partition = UserDefaults.standard.integer(forKey: "partition")

        if let simulatorsCount = UserDefaults.standard.object(forKey: "simulators-count") {
            self.simulatorsCount = (simulatorsCount as AnyObject).intValue
        } else {
            // Defaults to 1 simulator
            simulatorsCount = 1
        }

        if let partitionsCount = UserDefaults.standard.object(forKey: "partitions-count") {
            self.partitionsCount = (partitionsCount as AnyObject).intValue
        } else {
            // Defaults to 1 partition
            partitionsCount = 1
        }
        
        guard partition < partitionsCount else {
            exitWithMessage("-partition must be lower than -partitions-count")
        }

        var projectDirectory: String?
        
        if let project = UserDefaults.standard.string(forKey: "project") {
            let projectURL = URL(fileURLWithPath: project)

            projectPath = projectURL.path
            projectDirectory = projectURL.deletingLastPathComponent().path
            
        } else if let workspace = UserDefaults.standard.string(forKey: "workspace") {
            let workspaceURL = URL(fileURLWithPath: workspace)
            
            workspacePath = workspaceURL.path
            projectDirectory = workspaceURL.deletingLastPathComponent().path
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
    
    fileprivate static func createDirectoryAtPath(_ path: String) {
        if !FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                exitWithMessage(String(format: "Unable to create directory at path: %@", path))
            }
        }
    }
    
    var productPath: String {
        return derivedDataPath + "/Build/Products/Debug-iphonesimulator"
    }
    
}

func exitWithMessage(_ message: String, file: String = #file, line: Int = #line) -> Never  {
    NSLog("%@", "Failure at \(file):\(line): \(message)")
    exit(1)
}
