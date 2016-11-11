//
//  TestRunner.swift
//  TestRunner
//
//  Created by Stephan Heilner on 9/12/16.
//  Copyright © 2016 Stephan Heilner. All rights reserved.
//

//
//  TestRunner.swift
//  TestRunner
//
//  Created by Stephan Heilner on 12/4/15.
//  Copyright © 2015 The Church of Jesus Christ of Latter-day Saints. All rights reserved.
//

import Foundation

enum FailureError: Error {
    case failed(log: String)
}

let dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "M/d/yy h:mm:s a"
    return dateFormatter
}()

let logQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    return queue
}()

var lastSimulatorName = ""

func TRLog(_ logData: Data, simulatorName: String? = nil) {
    logQueue.addOperation(BlockOperation() {
        guard let log = String(data: logData, encoding: String.Encoding.utf8), !log.isEmpty else { return }
        
        if let simulatorName = simulatorName, simulatorName != lastSimulatorName {
            print("\n", dateFormatter.string(from: Date()), "-----------", simulatorName, "-----------\n", log, terminator: "")
            lastSimulatorName = simulatorName
        } else {
            print(log, terminator: "")
        }
    })
}

open class TestRunner: NSObject {
    
    open static func start() {
        // Don't buffer output
        setbuf(__stdoutp, nil)
        
        let testRunner = TestRunner()
        let testsPassed = testRunner.runTests()
        
        exit(testsPassed ? 0 : 1)
    }
    
    let testRunnerQueue = OperationQueue()
    var simulatorPassStatus = [String: Bool]()
    
    func runTests() -> Bool {
        testRunnerQueue.maxConcurrentOperationCount = 1
        DeviceController.sharedController.resetAndCreateDevices()
        
        if AppArgs.shared.buildTests {
            do {
                try BuildTests.sharedInstance.build(listTests: false)
                try BuildTests.sharedInstance.build(listTests: true)
            } catch let failureError as FailureError {
                switch failureError {
                case let .failed(log: log):
                    NSLog("Build-Tests Failed: %@", log)
                }
                return false
            } catch {
                NSLog("Unknown error while building tests")
                return false
            }
        }

        if AppArgs.shared.runTests {
            guard let devices = DeviceController.sharedController.resetAndCreateDevices(prepare: true), !devices.isEmpty else {
                NSLog("No Devices available")
                return false
            }
            
            guard let testsByPartition = TestPartitioner.sharedInstance.loadTestsByPartition(), !testsByPartition.isEmpty else {
                NSLog("Unable to load list of tests")
                return false
            }
            
            let partition = AppArgs.shared.partition
            let testsByDevice = testsByPartition[partition]
            
            for (deviceFamily, deviceInfos) in devices {
                for (index, deviceInfo) in deviceInfos.enumerated() {
                    guard let tests = testsByDevice[index] else { continue }
                    
                    let operation = createOperation(deviceFamily, simulatorName: deviceInfo.simulatorName, deviceID: deviceInfo.deviceID, tests: tests)
                    
                    // Wait for loaded to finish
                    testRunnerQueue.addOperation(operation)
                }
            }
            
            testRunnerQueue.waitUntilAllOperationsAreFinished()
            
            // Shutdown and kill all simulators
            DeviceController.sharedController.resetAndCreateDevices()
            
            Summary.outputSummary(attemptedTests: Array(testsByDevice.values.joined()))
        }

        let failed = simulatorPassStatus.any { _, passed in
            return !passed
        }
        return !failed
    }
    
    func createOperation(_ deviceFamily: String, simulatorName: String, deviceID: String, tests: [String], retryCount: Int = 0, launchRetryCount: Int = 0) -> TestRunnerOperation {
        let operation = TestRunnerOperation(deviceFamily: deviceFamily, simulatorName: simulatorName, deviceID: deviceID, tests: tests, retryCount: retryCount, launchRetryCount: launchRetryCount)
        operation.completion = { status, simulatorName, failedTests, deviceID, retryCount, launchRetryCount in
            switch status {
            case .success:
                NSLog("Tests PASSED on %@\n", simulatorName)
                self.simulatorPassStatus[simulatorName] = true
                
            case .failed, .testTimeout:
                let retryCount = retryCount + 1
                NSLog("\n\nTests FAILED (Attempt %d of %d) on %@\n", retryCount, AppArgs.shared.retryCount, simulatorName)
                
                self.simulatorPassStatus[simulatorName] = false
                
                let failedLog = "---------- Failed Tests ----------\n" + failedTests.joined(separator: "\n")
                if let failedData = failedLog.data(using: String.Encoding.utf8) {
                    TRLog(failedData, simulatorName: simulatorName)
                }
                
                if retryCount < AppArgs.shared.retryCount && !failedTests.isEmpty {
                    // Clear device for reuse
                    DeviceController.sharedController.reuseDevice(simulatorName: simulatorName, deviceID: deviceID)
                    
                    // Retry failed tests individually
                    for test in failedTests {
                        let retryOperation = self.createOperation(deviceFamily, simulatorName: simulatorName, deviceID: deviceID, tests: [test], retryCount: retryCount)
                        self.testRunnerQueue.addOperation(retryOperation)
                    }
                } else {
                    // Failed, kill all items in queue
                    self.testRunnerQueue.cancelAllOperations()
                }
            case .running, .stopped:
                break
            }
        }
        
        return operation
    }
    
}