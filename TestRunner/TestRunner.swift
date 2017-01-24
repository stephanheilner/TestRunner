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

let logQueue = DispatchQueue(label: "TestRunner.log")

var lastSimulatorName = ""

func TRLog(_ logData: Data, simulator: Simulator? = nil) {
    logQueue.async {
        guard !logData.isEmpty, let log = String(data: logData, encoding: .utf8), !log.isEmpty else { return }
        if let simulatorName = simulator?.name, simulatorName != lastSimulatorName {
            print("\n-----------", simulatorName, "-----------\n\n", log, terminator: "")
            lastSimulatorName = simulatorName
        } else {
            print(log, terminator: "")
        }
    }
}

func TRLog(_ logString: String, simulator: Simulator? = nil) {
    logQueue.async {
        guard !logString.isEmpty else { return }
        if let simulatorName = simulator?.name, simulatorName != lastSimulatorName {
            print("\n-----------", simulatorName, "-----------\n\n", logString)
            lastSimulatorName = simulatorName
        } else {
            print(logString)
        }
    }
}

open class TestRunner: NSObject {
    
    open static func start() {
        // Don't buffer output
        setbuf(__stdoutp, nil)
        
        let testRunner = TestRunner()
        let testsPassed = testRunner.runTests()
        
        exit(testsPassed ? 0 : 1)
    }
    
    let testRunnerQueue = TestRunnerOperationQueue()
    var simulatorPassStatus = [String: Bool]()
    
    func runTests() -> Bool {
        do {
            for logURL in try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: AppArgs.shared.logsDir), includingPropertiesForKeys: nil, options: []) {
                guard logURL.lastPathComponent != "tests.json" else { continue }
                
                try FileManager.default.removeItem(at: logURL)
            }
        } catch {}
        
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
            guard let devices = DeviceController.sharedController.resetAndCreateDevices(), !devices.isEmpty else {
                NSLog("No Devices available")
                return false
            }
            print("\n=== TESTING ON DEVICES ===")
            for (deviceName, simulators) in devices {
                for simulator in simulators {
                    print(deviceName, ":", simulator.name, "(", simulator.deviceID, ")")
                }
            }
            
            guard let testsByPartition = TestPartitioner.sharedInstance.loadTestsByPartition(), !testsByPartition.isEmpty else {
                NSLog("Unable to load list of tests")
                return false
            }
            
            let partition = AppArgs.shared.partition
            let testsByDevice = testsByPartition[partition]
            
            for (_, simulators) in devices {
                for (index, simulator) in simulators.enumerated() {
                    guard let tests = testsByDevice[index] else { continue }
                    
                    let operation = createOperation(simulator: simulator, tests: tests)
                    
                    // Wait for loaded to finish
                    testRunnerQueue.addOperation(operation)
                }
            }
            
            testRunnerQueue.waitUntilAllOperationsAreFinished()
            
            // Shutdown and kill all simulators
            DeviceController.sharedController.resetDevices()
            
            Summary.outputSummary()
        }

        let failed = simulatorPassStatus.any { _, passed in
            return !passed
        }
        return !failed
    }
    
    func createOperation(simulator: Simulator, tests: [String], retryCount: Int = 0, launchRetryCount: Int = 0) -> TestRunnerOperation {
        let operation = TestRunnerOperation(simulator: simulator, tests: tests, retryCount: retryCount, launchRetryCount: launchRetryCount)
        operation.completion = { status, simulator, failedTests, retryCount, launchRetryCount in
            switch status {
            case .success:
                TRLog("Tests PASSED on \(simulator.name)", simulator: simulator)
                self.simulatorPassStatus[simulator.name] = true
            case .failed, .testTimeout, .launchTimeout, .stopped, .terminatedAbnormally:
                var retryCount = retryCount
                if status == .failed {
                    retryCount = retryCount + 1
                }
                
                var launchRetryCount = launchRetryCount
                if status == .launchTimeout || status == .testTimeout || status == .terminatedAbnormally {
                     launchRetryCount = launchRetryCount + 1
                }

                TRLog("\n\nTests FAILED (Attempt \(retryCount) of \(AppArgs.shared.retryCount)) on \(simulator.name)", simulator: simulator)
                
                self.simulatorPassStatus[simulator.name] = false
                
                if retryCount < AppArgs.shared.retryCount && launchRetryCount < AppArgs.shared.launchRetryCount && !failedTests.isEmpty {
                    if !failedTests.isEmpty {
                        let retryOperation = self.createOperation(simulator: simulator, tests: failedTests, retryCount: retryCount, launchRetryCount: launchRetryCount)
                        self.testRunnerQueue.addOperation(retryOperation)
                    }
                } else {
                    // Failed, kill all items in queue
                    self.testRunnerQueue.cancelAllOperations()
                }
            case .running:
                break
            }
        }
        
        return operation
    }
    
}
