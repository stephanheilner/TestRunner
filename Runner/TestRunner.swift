//
//  TestRunner.swift
//  TestRunner
//
//  Created by Stephan Heilner on 12/4/15.
//  Copyright © 2015 The Church of Jesus Christ of Latter-day Saints. All rights reserved.
//

import Foundation
import Swiftification

enum FailureError: ErrorType {
    case Failed(log: String)
}

let dateFormatter: NSDateFormatter = {
   let dateFormatter = NSDateFormatter()
    dateFormatter.dateFormat = "M/d/yy h:mm:s a"
    return dateFormatter
}()

let logQueue: NSOperationQueue = {
    let queue = NSOperationQueue()
    queue.maxConcurrentOperationCount = 1
    return queue
}()

var lastSimulatorName = ""

func TRLog(logData: NSData, simulatorName: String? = nil) {
    logQueue.addOperation(NSBlockOperation() {
        guard let log = String(data: logData, encoding: NSUTF8StringEncoding) where !log.isEmpty else { return }

        if let simulatorName = simulatorName where simulatorName != lastSimulatorName {
            print("\n", dateFormatter.stringFromDate(NSDate()), "-----------", simulatorName, "-----------\n", log, terminator: "")
            lastSimulatorName = simulatorName
        } else {
            print(log, terminator: "")
        }
    })
}

public class TestRunner: NSObject {
    
    public static func start() {
        // Don't buffer output
        setbuf(__stdoutp, nil)

        let testRunner = TestRunner()
        let testsPassed = testRunner.runTests()

        exit(testsPassed ? 0 : 1)
    }
    
    let testRunnerQueue = TestRunnerOperationQueue()
    var simulatorPassStatus = [String: Bool]()
    
    func runTests() -> Bool {
        if AppArgs.shared.buildTests {
            do {
                try CleanBuild.sharedInstance.clean()
            } catch let failureError as FailureError {
                switch failureError {
                case let .Failed(log: log):
                    NSLog("Clean Failed: %@", log)
                }
                return false
            } catch {
                NSLog("Unknown error while building tests")
                return false
            }
            
            do {
                try BuildTests.sharedInstance.build()
            } catch let failureError as FailureError {
                switch failureError {
                case let .Failed(log: log):
                    NSLog("Build-Tests Failed: %@", log)
                }
                return false
            } catch {
                NSLog("Unknown error while building tests")
                return false
            }
        }

        if AppArgs.shared.runTests {
            CleanBuild.sharedInstance.deleteFilesInDirectory(AppArgs.shared.logsDir)
            DeviceController.sharedController.killAndDeleteTestDevices()
            
            guard let devices = DeviceController.sharedController.resetAndCreateDevices() where !devices.isEmpty else {
                NSLog("No Devices available")
                return false
            }
            
            guard let testsByPartition = TestPartitioner.sharedInstance.loadTestsByPartition() where !testsByPartition.isEmpty else {
                NSLog("Unable to load list of tests")
                return false
            }
            
            let partition = AppArgs.shared.partition
            let testsByDevice = testsByPartition[partition]
            
            for (deviceFamily, deviceInfos) in devices {
                for (index, deviceInfo) in deviceInfos.enumerate() {
                    guard let tests = testsByDevice[index] else { continue }
                    
                    let operation = createOperation(deviceFamily, simulatorName: deviceInfo.simulatorName, deviceID: deviceInfo.deviceID, tests: tests, retryCount: 0)
                    
                    // Wait for loaded to finish
                    testRunnerQueue.addOperation(operation)
                }
            }
            
            testRunnerQueue.waitUntilAllOperationsAreFinished()
            
            // Shutdown, Delete and Kill all Simulators
            DeviceController.sharedController.killAndDeleteTestDevices()

        }
        
        Summary.outputSummary(false)
        
        return simulatorPassStatus.values.reduce(true, combine: { passedSoFar, passed in
            return passedSoFar && passed
        })
    }
    
    func createOperation(deviceFamily: String, simulatorName: String, deviceID: String, tests: [String], retryCount: Int) -> TestRunnerOperation {
        let operation = TestRunnerOperation(deviceFamily: deviceFamily, simulatorName: simulatorName, deviceID: deviceID, tests: tests, retryCount: retryCount)
        operation.completion = { status, simulatorName, failedTests, deviceID, retryCount in
            switch status {
            case .Success:
                NSLog("Tests PASSED on %@\n", simulatorName)
                DeviceController.sharedController.deleteDeviceWithID(deviceID)
                
                self.simulatorPassStatus[simulatorName] = true
                
            case .Failed:
                let retryCount = retryCount + 1
                NSLog("\n\nTests FAILED (Attempt %d of %d) on %@\n", retryCount, AppArgs.shared.retryCount, simulatorName)
                
                self.simulatorPassStatus[simulatorName] = false
                
                if retryCount < AppArgs.shared.retryCount {
                    // Create new device for retry
                    let retryDeviceID = DeviceController.sharedController.resetDeviceWithID(deviceID, simulatorName: simulatorName) ?? deviceID
                    
                    // Retry
                    let retryOperation = self.createOperation(deviceFamily, simulatorName: simulatorName, deviceID: retryDeviceID, tests: failedTests, retryCount: retryCount)
                    self.testRunnerQueue.addOperation(retryOperation)
                }
            case .Running, .Stopped:
                break
            }
        }
        
        return operation
    }
    
}
