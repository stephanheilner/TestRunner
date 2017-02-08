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
    
    func resetAndCreateDevices() -> [String: [Simulator]]? {
        killallSimulators()
        return createTestDevices(testDevices: getTestDevices())
    }
    
    func resetDevices() {
        killallSimulators()
        
        getTestDevices().forEach {
            reuseDevice(simulator: $0)
            deleteApplicationBundles(simulator: $0)
        }
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
    
    func getTestDevices() -> [Simulator] {
        var testDevices = [Simulator]()
        
        for (key, values) in getDeviceInfoJSON() ?? [:] where key == "devices" {
            guard let deviceValues = values as? [String: AnyObject] else { continue }
            
            for (_, devices) in deviceValues {
                guard let devices = devices as? [AnyObject] else { continue }
                
                for device in devices {
                    if let name = device["name"] as? String, name.hasPrefix(testDevicePrefix), let udid = device["udid"] as? String {
                        testDevices.append(Simulator(name: name, deviceID: udid))
                    }
                }
            }
        }
        
        return testDevices
    }
    
    func getDeviceInfoJSON(retryCount: Int = 1) -> [String: AnyObject]? {
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
        
        if retryCount > 20 {
            NSLog("Failed to get devices after 20 tries.")
            return nil
        } else {
            sleep(1)
            return getDeviceInfoJSON(retryCount: retryCount + 1)
        }
    }
    
    func simctl(command: String, simulator: Simulator, appPath: String? = nil, retryCount: Int = 1) {
        guard retryCount < 5 else { return }
        
        var arguments = ["/usr/bin/xcrun", "simctl", command, simulator.deviceID]
        
        if let appPath = appPath {
            arguments.append(appPath)
        }
        
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", arguments.joined(separator: " ")]
        
        let outputPipe = Pipe()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            TRLog(handle.availableData, simulator: simulator)
        }
        task.standardOutput = outputPipe
        
//        let errorPipe = Pipe()
//        errorPipe.fileHandleForReading.readabilityHandler = { handle in
//            TRLog(handle.availableData, simulator: simulator)
//        }
//        task.standardError = errorPipe
        
        let start = Date()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + AppArgs.shared.launchTimeout) { [weak self] in
            if task.terminationStatus != 0 {
                // Retry
                self?.simctl(command: command, simulator: simulator, appPath: appPath, retryCount: retryCount + 1)
            }
        }
        
        task.launch()
        task.waitUntilExit()
        
        TRLog("\t* simctl \(command) \(simulator.deviceID) (\(Date().timeIntervalSince(start)) seconds)", simulator: simulator)
    }
    
    func killProcessesForDevice(simulator: Simulator) {
        TRLog("\t* Killing processes for device: \(simulator.deviceID)", simulator: simulator)
        
        let grepArgs = [simulator.deviceID]
        
        grepArgs.forEach { killProcesses(grepArg: $0, simulator: simulator) }
    }
    
    func killProcesses(grepArg: String, simulator: Simulator? = nil) {
        let task = Process()
        task.launchPath = "/bin/sh"
        
        let arguments = ["/usr/local/bin/pstree -U -w | grep", grepArg, "; /bin/ps aux | grep", grepArg]
        task.arguments = ["-c", arguments.joined(separator: " ")]
        
        TRLog("\t\(arguments.joined(separator: " "))", simulator: simulator)
        
        var standardOutputData = Data()
        let pipe = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            standardOutputData.append(handle.availableData)
        }
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        if task.terminationStatus == 0, let processInfoString = String(data: standardOutputData, encoding: .utf8) {
            for processString in processInfoString.components(separatedBy: "\n") {
                let parts = processString.components(separatedBy: " ")
                for part in parts {
                    guard let processID = Int(part) else { continue }
                    killProcess(processID: processID, simulator: simulator)
                    break
                }
            }
        }
    }
    
    func killProcess(processID: Int, simulator: Simulator? = nil) {
        let showProcess = Process()
        showProcess.launchPath = "/bin/sh"
        
        let arguments = ["/bin/kill", "-9", "\(processID)"]
        TRLog("\t\t\(arguments.joined(separator: " "))", simulator: simulator)
        
        showProcess.arguments = ["-c", arguments.joined(separator: " ")]
        showProcess.standardOutput = Pipe()
        showProcess.standardError = Pipe()
        showProcess.launch()
        showProcess.waitUntilExit()
    }
    
    func killallSimulators() {
        TRLog("\n=== KILLING SIMULATORS ===")
        
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "/usr/bin/killall Simulator"]
        
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
        
        let processesToKill = [
            "xcodebuild",
            "xctool",
            "Simulator",
            "pkd",
            "IDSKeychainSyncingProxy",
            "CloudKeychainProxy",
            "aslmanager",
            "launchd_sim",
            "UserEventAgent",
            "MobileSMSSpotlightImporter",
            "UserEventAgent",
            "mdworker"
        ]
        processesToKill.forEach { killProcesses(grepArg: $0) }
    }
    
    func createTestDevices(_ numberOfDevices: Int? = nil, testDevices: [Simulator] = []) -> [String: [Simulator]] {
        var devices = [String: [Simulator]]()
        
        let devicesArg = AppArgs.shared.devices
        let numberOfSimulators = numberOfDevices ?? AppArgs.shared.simulatorsCount
        
        var simulatorNumber = 1
        
        for deviceFamily in devicesArg.components(separatedBy: ";") {
            let components = deviceFamily.components(separatedBy: ",")
            if components.count == 2, let name = components.first?.trimmed(), let runtime = components.last?.trimmed(), let deviceTypeID = deviceTypes[name], let runtimeID = runtimes[runtime] {
                for _ in 1...numberOfSimulators {
                    let simulatorName = String(format: simulatorNameFormat, simulatorNumber, name, runtime)
                    
                    if let simulator = testDevices.find(where: { $0.name == simulatorName }) {
                        reuseDevice(simulator: simulator)
                        
                        if var simulators = devices[deviceFamily] {
                            simulators.append(simulator)
                            devices[deviceFamily] = simulators
                        } else {
                            devices[deviceFamily] = [simulator]
                        }
                        
                        simulatorNumber += 1
                    } else if let simulatorDevice = createTestDevice(name: simulatorName, deviceTypeID: deviceTypeID, runtimeID: runtimeID) {
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
        
        return devices
    }
    
    func reuseDevice(simulator: Simulator) {
        TRLog("\t* Preparing device for reuse", simulator: simulator)
        
        killProcessesForDevice(simulator: simulator)
        simctl(command: "shutdown", simulator: simulator)
        deleteApplicationData(simulator: simulator)
    }
    
    func deleteApplicationBundles(simulator: Simulator) {
        TRLog("\t* Deleting app bundles", simulator: simulator)
        
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "/bin/rm -rf \(NSHomeDirectory())/Library/Developer/CoreSimulator/Devices/\(simulator.deviceID)/data/Containers/Bundle/Application/*"]
        
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
    
    func deleteApplicationData(simulator: Simulator) {
        TRLog("\t* Deleting app data", simulator: simulator)
        
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "/bin/rm -rf \(NSHomeDirectory())/Library/Developer/CoreSimulator/Devices/\(simulator.deviceID)/data/Containers/Data/Application/*"]
        
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
    
    func createTestDevice(name: String, deviceTypeID: String, runtimeID: String) -> Simulator? {
        let task = Process()
        task.launchPath = "/bin/sh"
        
        let arguments = ["/usr/bin/xcrun", "simctl", "create", name, deviceTypeID, runtimeID]
        task.arguments = ["-c", arguments.joined(separator: " ")]
        
        let createDeviceOutput = Pipe()
        task.standardOutput = createDeviceOutput
        let data = NSMutableData()
        createDeviceOutput.fileHandleForReading.readabilityHandler = { handle in
            data.append(handle.availableData)
        }
        
        task.launch()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else { return nil }
        
        if let deviceID = String(data: data as Data, encoding: .utf8)?.trimmed() {
            let simulator = Simulator(name: name, deviceID: deviceID)
            TRLog("\n=== CREATED DEVICE (\(deviceID)) ===", simulator: simulator)
            return simulator
        }
        return nil
    }
    
    func installAppsOnDevice(simulator: Simulator) {
        deleteApplicationBundles(simulator: simulator)
        
        TRLog("\t* Installing apps on device", simulator: simulator)
        
        simctl(command: "boot", simulator: simulator)
        
        if let regex = try? NSRegularExpression(pattern: ".*\\.app$", options: []) {
            do {
                let productPath = AppArgs.shared.outputDirectory
                for filename in try FileManager.default.contentsOfDirectory(atPath: productPath) {
                    guard regex.numberOfMatches(in: filename, options: [], range: NSRange(location: 0, length: filename.length)) > 0 else { continue }
                    
                    simctl(command: "install", simulator: simulator, appPath: "\(productPath)/\(filename)")
                }
            } catch {
                TRLog("Unable to find any app bundles! \(error)", simulator: simulator)
            }
        }
        
        simctl(command: "shutdown", simulator: simulator)
    }
    
}
