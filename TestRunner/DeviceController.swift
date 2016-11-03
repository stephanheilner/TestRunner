//
//  DeviceController.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/10/16.
//  Copyright © 2016 Stephan Heilner
//

import Cocoa

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
    
    func createTestDevice() -> String? {
        deleteTestDevices()
        return createTestDevices(1).values.flatMap { $0.first?.deviceID }.first
    }
    
    func resetAndCreateDevices() -> [String: [(simulatorName: String, deviceID: String)]]? {
        deleteTestDevices()
        return createTestDevices()
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
    
    func getTestDeviceIDs(_ jsonObject: [String: AnyObject]) -> [String] {
        var testDeviceIDs = [String]()
        
        for (key, values) in jsonObject where key == "devices" {
            guard let deviceValues = values as? [String: AnyObject] else { continue }
            
            for (_, devices) in deviceValues {
                guard let devices = devices as? [AnyObject] else { continue }
                
                for device in devices {
                    if let name = device["name"] as? String, name.hasPrefix(testDevicePrefix), let udid = device["udid"] as? String {
                        testDeviceIDs.append(udid)
                    }
                }
            }
        }
        
        return testDeviceIDs
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
    
    func deleteDevicesWithIDs(_ deviceIDs: [String]) {
        deviceIDs.forEach { deleteDeviceWithID($0) }
    }
    
    func deleteDeviceWithID(_ deviceID: String) {
        shutdownDeviceWithID(deviceID)
        killProcessesForDevice(deviceID)
        
        print("\n=== DELETING DEVICE \n\(deviceID) ===")
        
        let task = Process()
        task.launchPath = "/usr/bin/xcrun"
        task.arguments = ["simctl", "delete", deviceID]
        task.standardError = Pipe()
        task.standardOutput = Pipe()
        task.launch()
        task.waitUntilExit()
    }
    
    func shutdownDeviceWithID(_ deviceID: String) {
        print("\n=== SHUTDOWN DEVICE \n\(deviceID) ===")
        
        let task = Process()
        task.launchPath = "/usr/bin/xcrun"
        task.arguments = ["simctl", "shutdown", deviceID]
        task.standardError = Pipe()
        task.standardOutput = Pipe()
        task.launch()
        task.waitUntilExit()
    }
    
    func getProcessComponents(_ processString: String) -> [String] {
        return processString.components(separatedBy: " ").filter { !$0.trimmed().isEmpty }
    }
    
    func killProcessesForDevice(_ deviceID: String) {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "ps aux | grep \"\(deviceID)\""]
        
        let standardOutputData = NSMutableData()
        let pipe = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            standardOutputData.append(handle.availableData)
        }
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        if task.terminationStatus == 0, let processInfoString = String(data: standardOutputData as Data, encoding: String.Encoding.utf8) {
            for processString in processInfoString.components(separatedBy: "\n") {
                let parts = getProcessComponents(processString)
                if !parts.isEmpty && !parts.contains("grep") {
                    killProcess(parts)
                }
            }
        }
    }
    
    func killProcess(_ processParts: [String]) {
        for part in processParts {
            guard let processID = Int(part) else { continue }
            
            print("\n=== KILLING PROCESS ===\n\(processParts.joined(separator: " "))")
            
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", "kill -9 \(processID)"]
            
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
            
            return
        }
    }
    
    func resetDeviceWithID(_ deviceID: String, simulatorName: String) -> String? {
        killProcessesForDevice(deviceID)
        
        let parts = simulatorName.components(separatedBy: ",")
        if let deviceTypeID = deviceTypes[parts[1].trimmed()], let runtimeID = runtimes[parts[2].trimmed()] {
            deleteDeviceWithID(deviceID)
            return createTestDevice(simulatorName, deviceTypeID: deviceTypeID, runtimeID: runtimeID)
        }
        
        let task = Process()
        task.launchPath = "/usr/bin/xcrun"
        task.arguments = ["simctl", "erase", deviceID]
        task.standardError = Pipe()
        task.standardOutput = Pipe()
        task.launch()
        task.waitUntilExit()
        
        return deviceID
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
    
    func createTestDevices(_ numberOfDevices: Int? = nil) -> [String: [(simulatorName: String, deviceID: String)]] {
        var devices = [String: [(simulatorName: String, deviceID: String)]]()
        
        let devicesArg = AppArgs.shared.devices
        let numberOfSimulators = numberOfDevices ?? AppArgs.shared.simulatorsCount
        
        var simulatorNumber = 1
        
        for deviceFamily in devicesArg.components(separatedBy: ";") {
            let components = deviceFamily.components(separatedBy: ",")
            if components.count == 2, let name = components.first?.trimmed(), let runtime = components.last?.trimmed(), let deviceTypeID = deviceTypes[name], let runtimeID = runtimes[runtime] {
                for _ in 1...numberOfSimulators {
                    let simulatorName = String(format: simulatorNameFormat, simulatorNumber, name, runtime)
                    if let deviceID = createTestDevice(simulatorName, deviceTypeID: deviceTypeID, runtimeID: runtimeID) {
                        let simulatorDevice = (simulatorName: simulatorName, deviceID: deviceID)
                        
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
    
    func createTestDevice(_ simulatorName: String, deviceTypeID: String, runtimeID: String) -> String? {
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
        
        return String(data: data as Data, encoding: String.Encoding.utf8)?.trimmed()
    }
    
    func killAndDeleteTestDevices() {
        killallXcodebuild()
        killallSimulators()
        deleteTestDevices()
        print("\n")
    }
    
    func deleteTestDevices() {
        guard let deviceInfo = getDeviceInfoJSON() else { return }
        
        deleteDevicesWithIDs(getTestDeviceIDs(deviceInfo))
    }
    
}
