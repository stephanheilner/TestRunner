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
    fileprivate static let PlistValueName = "TestRunnerListTests"
    
    func build(listTests: Bool) throws {
        let actions: [String]
        if listTests {
            actions = ["test-without-building"]
            if let regex = try? NSRegularExpression(pattern: ".*\\.app$", options: []) {
                _ = try? FileManager.default.contentsOfDirectory(atPath: AppArgs.shared.derivedDataPath).forEach { fileName in
                    guard regex.numberOfMatches(in: fileName, options: [], range: NSRange(location: 0, length: fileName.length)) > 0 else { return }

                    self.addEntries(toPlist: "\(AppArgs.shared.derivedDataPath)/\(fileName)", value: "\(AppArgs.shared.logsDir)/tests.json")
                }
            }
        } else {
            do {
                try FileManager.default.removeItem(atPath: AppArgs.shared.derivedDataPath)
                try FileManager.default.removeItem(atPath: AppArgs.shared.logsDir)
            } catch {
                print("Couldn't remove working directories")
            }

            actions = ["clean", "build-for-testing"]
        }
        
        let deviceID = DeviceController.sharedController.createTestDevice()
        let task = XcodebuildTask(actions: actions, deviceID: deviceID)
        task.delegate = self
        task.launch()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else {
            if let log = String(data: task.standardErrorData as Data, encoding: String.Encoding.utf8), !log.isEmpty {
                throw FailureError.failed(log: log)
            }
            return
        }

        if listTests, let regex = try? NSRegularExpression(pattern: ".*\\.app$", options: []) {
            _ = try? FileManager.default.contentsOfDirectory(atPath: AppArgs.shared.derivedDataPath).forEach { fileName in
                guard regex.numberOfMatches(in: fileName, options: [], range: NSRange(location: 0, length: fileName.length)) > 0 else { return }

                self.deleteEntries(fromPlist: "\(AppArgs.shared.derivedDataPath)/\(fileName)")
            }
        }
    }
    
    func addEntries(toPlist path: String, value: String) {
        let arguments = ["/usr/libexec/PlistBuddy", path, "-c", "\"Add :\(BuildTests.PlistValueName) string \(value)\""]
        let task = self.task(withLaunchPath: "/bin/sh", andArguments: ["-c", arguments.joined(separator: " ")])
        task.launch()
        task.waitUntilExit()
    }
    
    func deleteEntries(fromPlist path: String) {
        let arguments = ["/usr/libexec/PlistBuddy", path, "-c", "\"Delete :\(BuildTests.PlistValueName)\""]
        let task = self.task(withLaunchPath: "/bin/sh", andArguments: ["-c", arguments.joined(separator: " ")])
        task.launch()
        task.waitUntilExit()
    }

    private func task(withLaunchPath launchPath: String, andArguments arguments: [String]? = nil) -> Process {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = arguments
        task.standardError = Pipe()
        task.standardOutput = Pipe()
        return task
    }
    
}

extension BuildTests: XcodebuildTaskDelegate {
    
    func outputDataReceived(_ task: XcodebuildTask, data: Data) {
        TRLog(data)
    }
    
}
