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
    
    private lazy var deviceTypes: [String: String] = {
        var deviceTypes = [String: String]()
        for (key, values) in self.getDeviceInfoJSON() ?? [:] where key == "devicetypes" {
            for value in values as? [[String: String]] ?? [] {
                if let name = value["name"], identifier = value["identifier"] {
                    deviceTypes[name] = identifier
                }
            }
        }
        return deviceTypes
    }()
    
    private lazy var runtimes: [String: String] = {
        var runtimes = [String: String]()
        for (key, values) in self.getDeviceInfoJSON() ?? [:] where key == "runtimes" {
            for value in values as? [[String: String]] ?? [] {
                if let name = value["name"], identifier = value["identifier"] {
                    runtimes[name] = identifier
                }
            }
        }
        return runtimes
    }()

    private let testDevicePrefix = "Test Simulator"
    private lazy var simulatorNameFormat: String = {
        return self.testDevicePrefix + " %d, %@, %@" // number, device type, runtime
    }()
    
    func resetAndCreateDevices() -> [String: [(simulatorName: String, deviceID: String)]]? {
        deleteTestDevices()
        return createTestDevices()
    }
    
    func getRuntimes(jsonObject: [String: AnyObject]) -> [String: String] {
        var runtimes = [String: String]()
        
        for (key, values) in jsonObject where key == "runtimes" {
            for value in values as? [[String: String]] ?? [] {
                if let name = value["name"], identifier = value["identifier"] {
                    runtimes[name] = identifier
                }
            }
        }
        
        return runtimes
    }
    
    func getTestDeviceIDs(jsonObject: [String: AnyObject]) -> [String] {
        var testDeviceIDs = [String]()
        
        for (key, values) in jsonObject where key == "devices" {
            guard let deviceValues = values as? [String: AnyObject] else { continue }

            for (_, devices) in deviceValues {
                guard let devices = devices as? [AnyObject] else { continue }

                for device in devices {
                    if let name = device["name"] as? String where name.hasPrefix(testDevicePrefix), let udid = device["udid"] as? String {
                        testDeviceIDs.append(udid)
                    }
                }
            }
        }
        
        return testDeviceIDs
    }
    
    func getDeviceInfoJSON() -> [String: AnyObject]? {
        let outputPipe = NSPipe()
        
        let task = NSTask()
        task.launchPath = "/usr/bin/xcrun"
        task.arguments = ["simctl", "list", "-j"]
        task.standardOutput = outputPipe
        
        let standardOutputData = NSMutableData()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            standardOutputData.appendData(handle.availableData)
        }
        
        task.launch()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else { return nil }
        
        do {
            return try NSJSONSerialization.JSONObjectWithData(standardOutputData, options: []) as? [String: AnyObject]
        } catch let error as NSError {
            NSLog("Unable to deserialize simctl device list JSON: %@", error)
        }
        
        return nil
    }
    
    func deleteDevicesWithIDs(deviceIDs: [String]) {
        deviceIDs.forEach { deleteDeviceWithID($0) }
    }
    
    func shutdownDeviceWithID(deviceID: String) {
        let task = NSTask()
        task.launchPath = "/usr/bin/xcrun"
        task.arguments = ["simctl", "shutdown", deviceID]
        task.standardError = NSPipe()
        task.standardOutput = NSPipe()
        task.launch()
        task.waitUntilExit()
    }

    func deleteDeviceWithID(deviceID: String) {
        shutdownDeviceWithID(deviceID)

        let task = NSTask()
        task.launchPath = "/usr/bin/xcrun"
        task.arguments = ["simctl", "delete", deviceID]
        task.standardError = NSPipe()
        task.standardOutput = NSPipe()
        task.launch()
        task.waitUntilExit()
        
        print("Deleted device with ID:", deviceID)
        
        killProcessesForDevice(deviceID)
    }
    
    func getProcessComponents(processString: String) -> [String] {
        return processString.componentsSeparatedByString(" ").filter { !$0.trimmed().isEmpty }
    }
    
    func killProcessesForDevice(deviceID: String) {
        let task = NSTask()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "ps aux | grep \"\(deviceID)\""]
        
        let standardOutputData = NSMutableData()
        let pipe = NSPipe()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            standardOutputData.appendData(handle.availableData)
        }
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()

        if task.terminationStatus == 0, let processInfoString = String(data: standardOutputData, encoding: NSUTF8StringEncoding) {
            for processString in processInfoString.componentsSeparatedByString("\n") {
                let parts = getProcessComponents(processString)
                if !parts.isEmpty && !parts.contains("grep") {
                    killProcess(parts)
                }
            }
        }
    }
    
    func killProcess(processParts: [String]) {
        for part in processParts {
            guard let processID = Int(part) else { continue }
        
            print("\n=== KILLING PROCESS: \(processParts.joinWithSeparator(" ")) ===")
            
            let task = NSTask()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", "kill -9 \(processID)"]
            
            let standardOutputPipe = NSPipe()
            task.standardOutput = standardOutputPipe
            standardOutputPipe.fileHandleForReading.readabilityHandler = { handle in
                TRLog(handle.availableData)
            }
            let standardErrorPipe = NSPipe()
            task.standardError = standardErrorPipe
            standardErrorPipe.fileHandleForReading.readabilityHandler = { handle in
                TRLog(handle.availableData)
            }
            task.launch()
            task.waitUntilExit()
            
            return
        }
    }

    func resetDeviceWithID(deviceID: String, simulatorName: String) -> String? {
        shutdownDeviceWithID(deviceID)
        
        let parts = simulatorName.componentsSeparatedByString(",")
        if let deviceTypeID = deviceTypes[parts[1].trimmed()], runtimeID = runtimes[parts[2].trimmed()] {
            deleteDeviceWithID(deviceID)
            return createTestDevice(simulatorName, deviceTypeID: deviceTypeID, runtimeID: runtimeID)
        }
        
        let task = NSTask()
        task.launchPath = "/usr/bin/xcrun"
        task.arguments = ["simctl", "erase", deviceID]
        task.standardError = NSPipe()
        task.standardOutput = NSPipe()
        task.launch()
        task.waitUntilExit()
        
        return deviceID
    }
    
    func killallSimulators() {
        print("\n=== KILLING SIMULATORS ===")
        
        let task = NSTask()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["Simulator"]
        
        let standardOutputPipe = NSPipe()
        task.standardOutput = standardOutputPipe
        standardOutputPipe.fileHandleForReading.readabilityHandler = { handle in
            TRLog(handle.availableData)
        }
        let standardErrorPipe = NSPipe()
        task.standardError = standardErrorPipe
        standardErrorPipe.fileHandleForReading.readabilityHandler = { handle in
            TRLog(handle.availableData)
        }
        task.launch()
        task.waitUntilExit()
    }
    
    func createTestDevices() -> [String: [(simulatorName: String, deviceID: String)]] {
        var devices = [String: [(simulatorName: String, deviceID: String)]]()
        
        let devicesArg = AppArgs.shared.devices ?? "iPhone 5, iOS 9.3"
        let numberOfSimulators = (AppArgs.shared.simulatorsCount ?? 1)
        
        var simulatorNumber = 1
        
        for deviceFamily in devicesArg.componentsSeparatedByString(";") {
            let components = deviceFamily.componentsSeparatedByString(",")
            if components.count == 2, let name = components.first?.trimmed(), runtime = components.last?.trimmed(), deviceTypeID = deviceTypes[name], runtimeID = runtimes[runtime] {
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
                        
                        simulatorNumber++
                    }
                }
            }
        }
        
        return devices
    }
        
    func createTestDevice(simulatorName: String, deviceTypeID: String, runtimeID: String) -> String? {
        let task = NSTask()
        task.launchPath = "/usr/bin/xcrun"
        task.arguments = ["simctl", "create", simulatorName, deviceTypeID, runtimeID]
        
        let createDeviceOutput = NSPipe()
        task.standardOutput = createDeviceOutput
        let data = NSMutableData()
        createDeviceOutput.fileHandleForReading.readabilityHandler = { handle in
            data.appendData(handle.availableData)
        }
        
        task.launch()
        task.waitUntilExit()
        
        guard task.terminationStatus == 0 else { return nil }
        
        return String(data: data, encoding: NSUTF8StringEncoding)?.trimmed()
    }
    
    func killAndDeleteTestDevices() {
        killallSimulators()
        deleteTestDevices()
        print("\n")
    }
    
    func deleteTestDevices() {
        guard let deviceInfo = getDeviceInfoJSON() else { return }
        
        deleteDevicesWithIDs(getTestDeviceIDs(deviceInfo))
    }
    
}
