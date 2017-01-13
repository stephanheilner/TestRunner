//
//  BuildTests.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/10/16.
//  Copyright © 2016 Stephan Heilner
//

import Foundation

class BuildTests {
    
    static let sharedInstance = BuildTests()
    fileprivate static let PlistValueName = "TestRunnerListTests"
    
    func build(listTests: Bool) throws {
        let actions: [String]
        var plistPaths: [String]?
        
        if listTests {
            actions = ["test-without-building"]
            plistPaths = getPlistPaths()
            plistPaths?.forEach { self.addEntries(toPlist: $0, value: "\(AppArgs.shared.logsDir)/tests.json") }
        } else {
            do {
                try FileManager.default.removeItem(atPath: AppArgs.shared.derivedDataPath)
                try FileManager.default.removeItem(atPath: AppArgs.shared.logsDir)
            } catch {
                print("Couldn't remove working directories")
            }

            actions = ["clean", "build-for-testing"]
        }
        
        guard let destination = AppArgs.shared.devices.components(separatedBy: ";").first.flatMap({ arg -> String? in
            let parts = arg.components(separatedBy: ",")
            guard parts.count == 2, let device = parts.first?.trimmed(), let osString = parts.last?.trimmed(), let range = osString.range(of: " ") else { return nil }
            let os = osString.substring(from: range.upperBound)
            return "platform=iOS Simulator,name=\(device),OS=\(os)"
        }) else { throw FailureError.failed(log: "Unable to derive device name") }

        let start = Date()
        let task = XcodebuildTask(actions: actions, destination: destination)
        task.delegate = self
        task.launch()
        task.waitUntilExit()
        print("\n\n=== Built in \(Date().timeIntervalSince(start)) seconds ===\n")
        
        guard task.terminationStatus == 0 else {
            if let log = String(data: task.standardErrorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: String.Encoding.utf8), !log.isEmpty {
                throw FailureError.failed(log: log)
            } else {
                throw FailureError.failed(log: "Build failed.")
            }
        }

        if listTests {
            plistPaths?.forEach { self.deleteEntries(fromPlist: $0) }
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
    
    private func getPlistPaths() -> [String] {
        var plistPaths = [String]()
        if let regex = try? NSRegularExpression(pattern: ".*\\.app$", options: []) {
            do {
                let productPath = AppArgs.shared.outputDirectory
                for filename in try FileManager.default.contentsOfDirectory(atPath: productPath) {
                    guard regex.numberOfMatches(in: filename, options: [], range: NSRange(location: 0, length: filename.length)) > 0 else { continue }
                    
                    plistPaths.append("\(productPath)/\(filename)/Info.plist")
                }
            } catch {
                print("Unable to find any app bundles!", error)
            }
        }
        return plistPaths
    }

}

extension BuildTests: XcodebuildTaskDelegate {
    
    func outputDataReceived(_ task: XcodebuildTask, data: Data) {
        TRLog(data)
    }
    
}
