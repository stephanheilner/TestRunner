//
//  DeviceController.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/10/16.
//  Copyright © 2016 Stephan Heilner
//

import Foundation

class DeviceController {
    
    static let sharedController = DeviceController()
    
    fileprivate lazy var deviceTypes: [String: String] = {
        var deviceTypes = [String: String]()
        for (key, values) in self.getDeviceInfoJSON() ?? [:] where key == "devicetypes" {
            for value in values as? [[String: String]] ?? [] {
                if let name = value["name"], let identifier = value["identifier"] {
                    deviceTypes[name] = identifier
                }
            }
        }
        return deviceTypes
    }()
    
    fileprivate lazy var runtimes: [String: String] = {
        var runtimes = [String: String]()
        for (key, values) in self.getDeviceInfoJSON() ?? [:] where key == "runtimes" {
            for value in values as? [[String: String]] ?? [] {
                if let name = value["name"], let identifier = value["identifier"] {
                    runtimes[name] = identifier
                }
            }
        }
        return runtimes
    }()
    
    fileprivate let testDevicePrefix = "Test Simulator"
    fileprivate lazy var simulatorNameFormat: String = {
        return self.testDevicePrefix + " %d, %@, %@" // number, device type, runtime
    }()
    
    func createTestDevice(prepare: Bool) -> String? {
        killallXcodebuild()
        killallSimulators()
        
        return createTestDevices(1, testDevices: getTestDevices(), prepare: prepare).values.flatMap { $0.first?.deviceID }.first
    }
    
    @discardableResult
    func resetAndCreateDevices(prepare: Bool = false) -> [String: [(simulatorName: String, deviceID: String)]]? {
        killallXcodebuild()
        killallSimulators()
        return createTestDevices(testDevices: getTestDevices(), prepare: prepare)
    }
    
    func getRuntimes(_ jsonObject: [String: AnyObject]) -> [String: String] {
        var runtimes = [String: String]()
        
        for (key, values) in jsonObject where key == "runtimes" {
            for value in values as? [[String: String]] ?? [] {
                if let name = value["name"], let identifier = value["identifier"] {
                    runtimes[name] = identifier
                }
            }
        }
        
        return runtimes
    }
    
    func getTestDevices() -> [(simulatorName: String, deviceID: String)] {
        var testDevices = [(simulatorName: String, deviceID: String)]()
        
        for (key, values) in getDeviceInfoJSON() ?? [:] where key == "devices" {
            guard let deviceValues = values as? [String: AnyObject] else { continue }
            
            for (_, devices) in deviceValues {
                guard let devices = devices as? [AnyObject] else { continue }
                
                for device in devices {
                    if let name = device["name"] as? String, name.hasPrefix(testDevicePrefix), let udid = device["udid"] as? String {
                        testDevices.append(simulatorName: name, deviceID: udid)
                    }
                }
            }
        }
        
        return testDevices
    }
    
    func getDeviceInfoJSON() -> [String: AnyObject]? {
        let outputPipe = Pipe()
        
        let task = Process()
        task.launchPath = "/usr/bin/xcrun"
        task.arguments = ["simctl", "list", "-j"]
        task.standardOutput = outputPipe
        
        let standardOutputData = NSMutableData()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            standardOutputData.append(handle.availableData)
        }
        
        task.launch()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else { return nil }
        
        do {
            return try JSONSerialization.jsonObject(with: standardOutputData as Data, options: []) as? [String: AnyObject]
        } catch let error as NSError {
            NSLog("Unable to deserialize simctl device list JSON: %@", error)
        }
        
        return nil
    }
    
    func simctl(command: String, deviceID: String, appPath: String? = nil) {
        var arguments = ["/usr/bin/xcrun", "simctl", command, deviceID]
        
        if let appPath = appPath {
            arguments.append(appPath)
        }
        
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", arguments.joined(separator: " ")]
        
        let outputPipe = Pipe()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            TRLog(handle.availableData)
        }
        task.standardOutput = outputPipe
        
        let errorPipe = Pipe()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            TRLog(handle.availableData)
        }
        task.standardError = errorPipe
        
        let start = Date()
        task.launch()
        task.waitUntilExit()
        
        print("simctl", command, deviceID, "(\(Date().timeIntervalSince(start)) seconds)")
    }
    
    func getProcessComponents(_ processString: String) -> [String] {
        return processString.components(separatedBy: " ").filter { !$0.trimmed().isEmpty }
    }
    
    func killProcessesForDevice(deviceID: String) {
        print("\n=== KILLING PROCESSES FOR DEVICE (\(deviceID)) ===")
        
        killProcessesWithGrepArg(grepArg: deviceID)
        killProcessesWithGrepArg(grepArg: "iPhoneSimulator.platform")
        killProcessesWithGrepArg(grepArg: "pkd")
        killProcessesWithGrepArg(grepArg: "aslmanager")
    }
    
    func killProcessesWithGrepArg(grepArg: String) {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "/usr/local/bin/pstree -U -w | grep \(grepArg); /bin/ps aux | grep \(grepArg)"]
        
        var standardOutputData = Data()
        let pipe = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            standardOutputData.append(handle.availableData)
        }
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        if task.terminationStatus == 0, let processInfoString = String(data: standardOutputData, encoding: String.Encoding.utf8) {
            for processString in processInfoString.components(separatedBy: "\n") {
                let parts = processString.components(separatedBy: " ")
                for part in parts {
                    guard let processID = Int(part) else { continue }
                    killProcess(processID: processID)
                    break
                }
            }
        }
    }
    
    func killProcess(processID: Int) {
        let task = Process()
        task.launchPath = "/bin/sh"
        let command = "/bin/kill -9 \(processID)"
        print(command)
        task.arguments = ["-c", command]
        
        let standardOutputPipe = Pipe()
        task.standardOutput = standardOutputPipe
        standardOutputPipe.fileHandleForReading.readabilityHandler = { handle in
            TRLog(handle.availableData)
        }
        let standardErrorPipe = Pipe()
        task.standardError = standardErrorPipe
//        standardErrorPipe.fileHandleForReading.readabilityHandler = { handle in
//            TRLog(handle.availableData)
//        }
        task.launch()
        task.waitUntilExit()
    }
    
    func killallSimulators() {
        print("\n=== KILLING SIMULATORS ===")
        
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["Simulator"]
        
        let standardOutputPipe = Pipe()
        task.standardOutput = standardOutputPipe
        standardOutputPipe.fileHandleForReading.readabilityHandler = { handle in
            TRLog(handle.availableData)
        }
        let standardErrorPipe = Pipe()
        task.standardError = standardErrorPipe
        standardErrorPipe.fileHandleForReading.readabilityHandler = { handle in
            TRLog(handle.availableData)
        }
        task.launch()
        task.waitUntilExit()
    }
    
    func killallXcodebuild() {
        print("\n=== KILLING xcodebuild ===")
        
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["xcodebuild"]
        
        let standardOutputPipe = Pipe()
        task.standardOutput = standardOutputPipe
        standardOutputPipe.fileHandleForReading.readabilityHandler = { handle in
            TRLog(handle.availableData)
        }
        let standardErrorPipe = Pipe()
        task.standardError = standardErrorPipe
        standardErrorPipe.fileHandleForReading.readabilityHandler = { handle in
            TRLog(handle.availableData)
        }
        task.launch()
        task.waitUntilExit()
    }
    
    func createTestDevices(_ numberOfDevices: Int? = nil, testDevices: [(simulatorName: String, deviceID: String)] = [], prepare: Bool = false) -> [String: [(simulatorName: String, deviceID: String)]] {
        var devices = [String: [(simulatorName: String, deviceID: String)]]()
        
        let devicesArg = AppArgs.shared.devices
        let numberOfSimulators = numberOfDevices ?? AppArgs.shared.simulatorsCount
        
        var simulatorNumber = 1
        
        for deviceFamily in devicesArg.components(separatedBy: ";") {
            let components = deviceFamily.components(separatedBy: ",")
            if components.count == 2, let name = components.first?.trimmed(), let runtime = components.last?.trimmed(), let deviceTypeID = deviceTypes[name], let runtimeID = runtimes[runtime] {
                for _ in 1...numberOfSimulators {
                    let simulatorName = String(format: simulatorNameFormat, simulatorNumber, name, runtime)
                    
                    if let simulatorDevice = testDevices.find(where: { $0.simulatorName == simulatorName }) {
                        reuseDevice(simulatorName: simulatorDevice.simulatorName, deviceID: simulatorDevice.deviceID)
                        
                        if var simulatorDevices = devices[deviceFamily] {
                            simulatorDevices.append(simulatorDevice)
                            devices[deviceFamily] = simulatorDevices
                        } else {
                            devices[deviceFamily] = [simulatorDevice]
                        }
                        
                        simulatorNumber += 1
                    } else if let simulatorDevice = createTestDevice(simulatorName, deviceTypeID: deviceTypeID, runtimeID: runtimeID) {
                        if var simulatorDevices = devices[deviceFamily] {
                            simulatorDevices.append(simulatorDevice)
                            devices[deviceFamily] = simulatorDevices
                        } else {
                            devices[deviceFamily] = [simulatorDevice]
                        }
                        
                        simulatorNumber += 1
                    }
                }
            }
        }
        
        print("\n=== TEST DEVICES ===")
        for (deviceName, simulators) in devices {
            for simulator in simulators {
                print(deviceName, ":", simulator.simulatorName, "(", simulator.deviceID, ")")
                if prepare {
                    installAppsOnDevice(deviceID: simulator.deviceID)
                }
            }
        }
        
        return devices
    }
    
    func reuseDevice(simulatorName: String, deviceID: String) {
        print("\n=== REUSE DEVICE (\(deviceID)) ===")
        
        killProcessesForDevice(deviceID: deviceID)
        
        deleteApplicationData(deviceID: deviceID)
        deleteApplicationBundles(deviceID: deviceID)
    }
    
    func deleteApplicationBundles(deviceID: String) {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "/bin/rm -rf \(NSHomeDirectory())/Library/Developer/CoreSimulator/Devices/\(deviceID)/data/Containers/Bundle/Application/*"]
        
        let standardOutputPipe = Pipe()
        task.standardOutput = standardOutputPipe
        standardOutputPipe.fileHandleForReading.readabilityHandler = { handle in
            TRLog(handle.availableData)
        }
        let standardErrorPipe = Pipe()
        task.standardError = standardErrorPipe
        standardErrorPipe.fileHandleForReading.readabilityHandler = { handle in
            TRLog(handle.availableData)
        }
        task.launch()
        task.waitUntilExit()
    }
    
    func deleteApplicationData(deviceID: String) {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "/bin/rm -rf \(NSHomeDirectory())/Library/Developer/CoreSimulator/Devices/\(deviceID)/data/Containers/Data/Application/*"]
        
        let standardOutputPipe = Pipe()
        task.standardOutput = standardOutputPipe
        standardOutputPipe.fileHandleForReading.readabilityHandler = { handle in
            TRLog(handle.availableData)
        }
        let standardErrorPipe = Pipe()
        task.standardError = standardErrorPipe
        standardErrorPipe.fileHandleForReading.readabilityHandler = { handle in
            TRLog(handle.availableData)
        }
        task.launch()
        task.waitUntilExit()
    }
    
    func createTestDevice(_ simulatorName: String, deviceTypeID: String, runtimeID: String) -> (simulatorName: String, deviceID: String)? {
        let task = Process()
        task.launchPath = "/usr/bin/xcrun"
        task.arguments = ["simctl", "create", simulatorName, deviceTypeID, runtimeID]
        
        let createDeviceOutput = Pipe()
        task.standardOutput = createDeviceOutput
        let data = NSMutableData()
        createDeviceOutput.fileHandleForReading.readabilityHandler = { handle in
            data.append(handle.availableData)
        }
        
        task.launch()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else { return nil }
        
        if let deviceID = String(data: data as Data, encoding: String.Encoding.utf8)?.trimmed() {
            print("\n=== CREATED DEVICE (\(deviceID)) ===")
            return (simulatorName: simulatorName, deviceID: deviceID)
        }
        return nil
    }
    
    func installAppsOnDevice(deviceID: String) {
        print("\n=== PREPARING DEVICE FOR USE ===")
        simctl(command: "boot", deviceID: deviceID)
        
        if let regex = try? NSRegularExpression(pattern: ".*\\.app$", options: []) {
            do {
                let productPath = AppArgs.shared.derivedDataPath + "/Build/Products/Debug-iphonesimulator"
                for filename in try FileManager.default.contentsOfDirectory(atPath: productPath) {
                    guard regex.numberOfMatches(in: filename, options: [], range: NSRange(location: 0, length: filename.length)) > 0 else { continue }
                    
                    simctl(command: "install", deviceID: deviceID, appPath: "\(productPath)/\(filename)")
                }
            } catch {
                print("Unable to find any app bundles!", error)
            }
        }

        simctl(command: "shutdown", deviceID: deviceID)
    }
    
    func killAndDeleteTestDevices() {
        killallXcodebuild()
        killallSimulators()
        print("\n")
    }
    
}
