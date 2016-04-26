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

let dataSynchronizationQueue: NSOperationQueue = {
    let queue = NSOperationQueue()
    queue.maxConcurrentOperationCount = 1
    return queue
}()

var lastSimulatorName = ""

func TRLog(logString: String, simulatorName: String? = nil) {
    guard let data = logString.dataUsingEncoding(NSUTF8StringEncoding) else { return }
    TRLog(data, simulatorName: simulatorName)
}

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
    private var allTests: [String]?
    private var succeededTests = [String]()
    private var failedTests = [String: Int]()
    private var finished = false
    
    func runTests() -> Bool {
        if AppArgs.shared.buildTests {
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
            DeviceController.sharedController.killAndDeleteTestDevices()
            
            guard let devices = DeviceController.sharedController.resetAndCreateDevices() where !devices.isEmpty else {
                NSLog("No Devices available")
                return false
            }
            
            for (deviceName, simulators) in devices {
                for simulator in simulators {
                    print("Created", deviceName, ":", simulator.simulatorName, "(", simulator.deviceID, ")")
                }
            }
            
            guard let allTests = TestPartitioner.sharedInstance.loadTestsForPartition(AppArgs.shared.partition) where !allTests.isEmpty else {
                NSLog("Unable to load list of tests")
                return false
            }
            
            self.allTests = allTests
            
            for (deviceFamily, deviceInfos) in devices {
                for (index, deviceInfo) in deviceInfos.enumerate() {
                    let tests = getNextTests()
                    guard !tests.isEmpty else { continue }
                    
                    let operation = createOperation(deviceFamily, simulatorName: deviceInfo.simulatorName, deviceID: deviceInfo.deviceID, tests: tests)
                    
                    // Wait for loaded to finish
                    testRunnerQueue.addOperation(operation, waitForLoad: true)
                }
            }
            
            testRunnerQueue.waitUntilAllOperationsAreFinished()
            
            // Shutdown, Delete and Kill all Simulators
            DeviceController.sharedController.killAndDeleteTestDevices()

            Summary.outputSummary(false)
        }
        
        logQueue.waitUntilAllOperationsAreFinished()
        dataSynchronizationQueue.waitUntilAllOperationsAreFinished()
        
        return allTestsPassed()
    }
    
    func allTestsPassed() -> Bool {
        var passed = false
        dataSynchronizationQueue.addOperationWithBlock {
            NSLog("all: \(self.allTests?.sort() ?? [])")
            NSLog("succeeded: \(self.succeededTests.unique().sort())")
            passed = self.succeededTests.unique().sort() == self.allTests?.sort() ?? []
        }
        
        dataSynchronizationQueue.waitUntilAllOperationsAreFinished()
        return passed
    }
    
    func cleanup() {
        self.testRunnerQueue.cancelAllOperations()
        DeviceController.sharedController.killAndDeleteTestDevices()
        dataSynchronizationQueue.waitUntilAllOperationsAreFinished()
        logQueue.waitUntilAllOperationsAreFinished()
    }
    
    func getNextTests() -> [String] {
        // Temporarily have all simulators run all tests because most are hanging at this point.
        return allTests?.filter { !succeededTests.contains($0) } ?? []
    }
    
    func createOperation(deviceFamily: String, simulatorName: String, deviceID: String, tests: [String], alreadyLoaded: Bool = false) -> TestRunnerOperation {
        let operation = TestRunnerOperation(deviceFamily: deviceFamily, simulatorName: simulatorName, deviceID: deviceID, tests: tests, alreadyLoaded: alreadyLoaded)
        operation.completion = { status, simulatorName, attemptedTests, succeededTests, deviceID in
            dataSynchronizationQueue.addOperationWithBlock {
                self.succeededTests += succeededTests
            }
            switch status {
            case .Success:
                TRLog("Tests PASSED\n", simulatorName: simulatorName)
                
                var nextTests = [String]()
                dataSynchronizationQueue.addOperationWithBlock {
                    nextTests = self.getNextTests()
                }
                
                logQueue.waitUntilAllOperationsAreFinished()
                dataSynchronizationQueue.waitUntilAllOperationsAreFinished()
                
                guard !self.allTestsPassed() else {
                    self.cleanup()
                    return
                }
                
                if !nextTests.isEmpty {
                    // Start next set of tests
                    let nextTestOperation = self.createOperation(deviceFamily, simulatorName: simulatorName, deviceID: deviceID, tests: nextTests, alreadyLoaded: true)
                    self.testRunnerQueue.addOperation(nextTestOperation, waitForLoad: false)
                }
            case .Failed:
                let failedTests = attemptedTests.filter { !succeededTests.contains($0) }
                TRLog("\n\nTests FAILED (\(failedTests)) on \(simulatorName)\n\n", simulatorName: simulatorName)
                
                var failedForRealzies = false
                var nextTests = [String]()
                dataSynchronizationQueue.addOperationWithBlock {
                    for failure in failedTests {
                        self.failedTests[failure] = (self.failedTests[failure] ?? 0) + 1
                        let failedCount = self.failedTests[failure]
                        TRLog("Test \(failure) failure number \(failedCount ?? -1)\n", simulatorName: simulatorName)
                        if failedCount >= AppArgs.shared.retryCount {
                            failedForRealzies = true
                            TRLog("\n\n***************Test \(failure) failed too many times. Aborting remaining tests.***************\n\n", simulatorName: simulatorName)
                        }
                    }
                    
                    nextTests = self.getNextTests()
                }
                
                logQueue.waitUntilAllOperationsAreFinished()
                dataSynchronizationQueue.waitUntilAllOperationsAreFinished()
                
                guard !self.allTestsPassed() else {
                    self.cleanup()
                    return
                }
                
                if failedForRealzies {
                    // Failed, kill all items in queue
                    NSLog("Failed for realzies")
                    self.testRunnerQueue.cancelAllOperations()
                } else if !nextTests.isEmpty {
                    // Create new device for retry
                    let retryDeviceID = DeviceController.sharedController.resetDeviceWithID(deviceID, simulatorName: simulatorName) ?? deviceID
                    
                    // Retry
                    let retryOperation = self.createOperation(deviceFamily, simulatorName: simulatorName, deviceID: retryDeviceID, tests: nextTests)
                    self.testRunnerQueue.addOperation(retryOperation, waitForLoad: true)
                }
            case .Running, .Stopped:
                break
            }
            
            logQueue.waitUntilAllOperationsAreFinished()
        }
        
        return operation
    }
    
}
