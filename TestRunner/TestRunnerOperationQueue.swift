//
//  TestRunnerOperationQueue.swift
//  TestRunner
//
//  Created by Stephan Heilner on 2/16/16.
//  Copyright © 2016 Stephan Heilner
//

import Foundation

class TestRunnerOperationQueue: OperationQueue {

    static let SimulatorLoadedNotification = "SimulatorLoadedNotification"
    
    var waitOperations = [Operation]()
    
    override init() {
        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(TestRunnerOperationQueue.simulatorLoaded), name: NSNotification.Name(rawValue: TestRunnerOperationQueue.SimulatorLoadedNotification), object: nil)
    }
    
    override func addOperation(_ operation: Operation) {
        // Causing it to hang, when just one build is added it has a wait operation but it
        if isWaitingToLoad() {
            let waitOperation = WaitOperation()
            waitOperations.append(waitOperation)
            operation.addDependency(waitOperation)
        }
        super.addOperation(operation)
    }
    
    fileprivate func isWaitingToLoad() -> Bool {
        for case let operation as TestRunnerOperation in operations where !operation.simulatorLaunched {
            return true
        }
        return false
    }
    
    func simulatorLoaded(_ notification: Notification) {
        guard let waitOperation = waitOperations.shift() as? WaitOperation else { return }
        
        waitOperation.isExecuting = false
        waitOperation.isFinished = true
    }
    
}
